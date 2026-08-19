//
//  MongoKitten+BuildInfo.swift
//  Collection
//
//  Created by Fauzaan on 3/23/25.
//

import MongoKitten

extension MongoDatabase {
    func getBuildInfo() async throws -> MongoBuildInfo {
        // Use self instead of requiring an external database parameter
        let connection = try await self.pool.next(for: .basic)
        
        // Execute the command against the admin database
        let buildInfo = try await connection.executeCodable(
            ["buildInfo": 1],
            decodeAs: MongoBuildInfo.self,
            namespace: .administrativeCommand,
            sessionId: connection.implicitSessionId,
            traceLabel: "getMongoDBVersion"
        )
        
        return buildInfo
    }
}


struct MongoBuildInfo: Decodable {
    private enum CodingKeys: String, CodingKey {
        case version
        case ok
    }
    
    public let version: String
    public let ok: Int

    public var isSuccessful: Bool { ok == 1 }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.ok = try container.decode(Int.self, forKey: .ok)
        self.version = try container.decode(String.self, forKey: .version)
    }
}

