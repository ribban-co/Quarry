import Darwin
import Foundation

struct SSHTunnelEndpoint: Sendable {
    let id: UUID
    let localHost: String
    let localPort: Int
}

actor SSHTunnelService {
    static let shared = SSHTunnelService()

    private var tunnels: [UUID: SystemSSHTunnel] = [:]
    private let portRange = 60_000...65_000

    private init() {}

    func createTunnel(
        config: SSHConfiguration,
        sshPassword: String?,
        keyPassphrase: String?,
        remoteHost: String,
        remotePort: Int
    ) async throws -> SSHTunnelEndpoint {
        guard config.enabled else {
            throw DatabaseError.configurationError("SSH tunnel is not enabled")
        }

        let tunnelId = UUID()
        let candidates = portRange.shuffled()

        for localPort in candidates {
            do {
                let tunnel = try makeTunnel(
                    id: tunnelId,
                    localPort: localPort,
                    config: config,
                    sshPassword: sshPassword,
                    keyPassphrase: keyPassphrase,
                    remoteHost: remoteHost,
                    remotePort: remotePort
                )

                do {
                    try await waitUntilReady(tunnel)
                } catch {
                    tunnel.terminate()
                    throw error
                }

                // Auth is done once the tunnel is up; remove the askpass helper
                // and its credential files immediately.
                tunnel.cleanupAskPassHelper()
                tunnels[tunnelId] = tunnel
                return SSHTunnelEndpoint(id: tunnelId, localHost: "127.0.0.1", localPort: localPort)
            } catch let error as SSHTunnelError where error.isLocalPortCollision {
                continue
            } catch let error as SSHTunnelError {
                throw DatabaseError.connectionFailed(error.message)
            } catch {
                throw error
            }
        }

        throw DatabaseError.connectionFailed("No available local port for SSH tunnel")
    }

    func closeTunnel(id: UUID?) {
        guard let id, let tunnel = tunnels.removeValue(forKey: id) else { return }
        tunnel.terminate()
    }

    func closeAllTunnels() {
        let activeTunnels = Array(tunnels.values)
        tunnels.removeAll()
        for tunnel in activeTunnels {
            tunnel.terminate()
        }
    }

    private func makeTunnel(
        id: UUID,
        localPort: Int,
        config: SSHConfiguration,
        sshPassword: String?,
        keyPassphrase: String?,
        remoteHost: String,
        remotePort: Int
    ) throws -> SystemSSHTunnel {
        let process = Process()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = sshArguments(
            localPort: localPort,
            config: config,
            remoteHost: remoteHost,
            remotePort: remotePort
        )
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = stderr
        process.environment = sshEnvironment(
            base: ProcessInfo.processInfo.environment,
            sshPassword: sshPassword,
            keyPassphrase: keyPassphrase
        )

        let askPassURL = try makeAskPassHelperIfNeeded(
            sshPassword: sshPassword,
            keyPassphrase: keyPassphrase
        )
        if let askPassURL {
            process.environment?["SSH_ASKPASS"] = askPassURL.path
        }

        let tunnel = SystemSSHTunnel(
            id: id,
            localPort: localPort,
            process: process,
            stderr: stderr,
            askPassURL: askPassURL
        )

        do {
            try process.run()
            return tunnel
        } catch {
            tunnel.cleanupAskPassHelper()
            throw DatabaseError.connectionFailed("Failed to launch ssh: \(error.localizedDescription)")
        }
    }

    private func sshArguments(
        localPort: Int,
        config: SSHConfiguration,
        remoteHost: String,
        remotePort: Int
    ) -> [String] {
        var arguments = [
            "-N",
            "-T",
            "-L", "127.0.0.1:\(localPort):\(remoteHost):\(remotePort)",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-o", "ConnectTimeout=15",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "LogLevel=ERROR",
        ]

        if let port = config.port {
            arguments.append(contentsOf: ["-p", String(port)])
        }

        switch config.authMethod {
        case .sshAgent:
            break
        case .privateKey:
            arguments.append(contentsOf: ["-o", "PreferredAuthentications=publickey"])
            if !config.privateKeyPath.isEmpty {
                arguments.append(contentsOf: ["-i", expandedPath(config.privateKeyPath)])
            }
        case .password:
            arguments.append(contentsOf: [
                "-o", "PreferredAuthentications=password,keyboard-interactive",
                "-o", "PubkeyAuthentication=no",
                "-o", "NumberOfPasswordPrompts=1",
            ])
        }

        if config.username.isEmpty {
            arguments.append(config.host)
        } else {
            arguments.append("\(config.username)@\(config.host)")
        }

        return arguments
    }

    private func sshEnvironment(
        base: [String: String],
        sshPassword: String?,
        keyPassphrase: String?
    ) -> [String: String] {
        var environment = base
        let hasPassword = sshPassword?.isEmpty == false
        let hasPassphrase = keyPassphrase?.isEmpty == false

        guard hasPassword || hasPassphrase else {
            return environment
        }

        environment["SSH_ASKPASS_REQUIRE"] = "force"
        environment["DISPLAY"] = environment["DISPLAY"] ?? "localhost:0"

        // Secrets are never placed in the child environment (readable by other
        // same-user processes); the askpass helper reads them from 0600 files
        // in a private per-launch directory instead.
        return environment
    }

    private func makeAskPassHelperIfNeeded(
        sshPassword: String?,
        keyPassphrase: String?
    ) throws -> URL? {
        let hasPassword = sshPassword?.isEmpty == false
        let hasPassphrase = keyPassphrase?.isEmpty == false
        guard hasPassword || hasPassphrase else { return nil }

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("quarry-ssh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let passwordURL = directory.appendingPathComponent("password")
        let passphraseURL = directory.appendingPathComponent("passphrase")

        if let sshPassword, hasPassword {
            try writeSecretFile(sshPassword, to: passwordURL)
        }
        if let keyPassphrase, hasPassphrase {
            try writeSecretFile(keyPassphrase, to: passphraseURL)
        }

        let scriptURL = directory.appendingPathComponent("askpass.sh")
        let script = """
        #!/bin/sh
        case "$1" in
          *passphrase*) cat "\(passphraseURL.path)" 2>/dev/null ;;
          *) cat "\(passwordURL.path)" 2>/dev/null ;;
        esac
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private func writeSecretFile(_ secret: String, to url: URL) throws {
        let created = FileManager.default.createFile(
            atPath: url.path,
            contents: Data(secret.utf8),
            attributes: [.posixPermissions: 0o600]
        )
        guard created else {
            throw DatabaseError.connectionFailed("Failed to write SSH credential file")
        }
    }

    private func waitUntilReady(_ tunnel: SystemSSHTunnel) async throws {
        let startedAt = Date()
        while Date().timeIntervalSince(startedAt) < 12 {
            try Task.checkCancellation()

            if !tunnel.isRunning {
                let message = tunnel.errorOutput()
                tunnel.terminate()
                throw SSHTunnelError.processExited(message)
            }

            if canConnectToLocalPort(tunnel.localPort) {
                return
            }

            try await Task.sleep(for: .milliseconds(100))
        }

        let message = tunnel.errorOutput()
        tunnel.terminate()
        throw DatabaseError.connectionFailed(message.isEmpty ? "Timed out waiting for SSH tunnel" : message)
    }

    private func canConnectToLocalPort(_ port: Int) -> Bool {
        let socketDescriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else { return false }
        defer { Darwin.close(socketDescriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(
                    socketDescriptor,
                    sockaddrPointer,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                ) == 0
            }
        }
    }

    private func expandedPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}

private enum SSHTunnelError: Error {
    case processExited(String)

    var message: String {
        switch self {
        case .processExited(let message):
            return message.isEmpty ? "SSH tunnel process exited" : message
        }
    }

    var isLocalPortCollision: Bool {
        switch self {
        case .processExited(let message):
            let lowercased = message.lowercased()
            return lowercased.localizedStandardContains("address already in use")
                || lowercased.localizedStandardContains("cannot listen to port")
        }
    }
}

private final class SystemSSHTunnel: @unchecked Sendable {
    let id: UUID
    let localPort: Int

    private let process: Process
    private let stderr: Pipe
    private let askPassURL: URL?

    init(id: UUID, localPort: Int, process: Process, stderr: Pipe, askPassURL: URL?) {
        self.id = id
        self.localPort = localPort
        self.process = process
        self.stderr = stderr
        self.askPassURL = askPassURL
    }

    var isRunning: Bool {
        process.isRunning
    }

    func terminate() {
        if process.isRunning {
            process.terminate()
        }
        cleanupAskPassHelper()
    }

    func errorOutput() -> String {
        guard !process.isRunning else { return "" }
        let data = stderr.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func cleanupAskPassHelper() {
        guard let askPassURL else { return }
        try? FileManager.default.removeItem(at: askPassURL.deletingLastPathComponent())
    }
}
