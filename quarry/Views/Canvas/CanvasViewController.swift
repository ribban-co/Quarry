import AppKit

@MainActor
final class CanvasViewController: NSViewController, CanvasNSViewDelegate {
    private let canvasView = CanvasNSView()
    private let toolbarView = CanvasToolbarView()
    private let zoomOverlay = CanvasZoomOverlayView()
    private let loadingOverlay = NSView()
    private let spinner = NSProgressIndicator()
    private let instance: ConnectionInstance

    private var isGenerating = false
    private var schemas: [String] = []
    private var currentSchema: String?

    init(instance: ConnectionInstance) {
        self.instance = instance
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true

        canvasView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.delegate = self
        container.addSubview(canvasView)

        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.delegate = self
        container.addSubview(toolbarView)

        zoomOverlay.translatesAutoresizingMaskIntoConstraints = false
        zoomOverlay.onZoomOut = zoomAction { $0.zoomOut() }
        zoomOverlay.onZoomIn = zoomAction { $0.zoomIn() }
        zoomOverlay.onResetZoom = zoomAction { $0.resetZoom() }
        container.addSubview(zoomOverlay)

        loadingOverlay.translatesAutoresizingMaskIntoConstraints = false
        loadingOverlay.wantsLayer = true
        loadingOverlay.isHidden = true
        container.addSubview(loadingOverlay)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        loadingOverlay.addSubview(spinner)

        NSLayoutConstraint.activate([
            canvasView.topAnchor.constraint(equalTo: container.topAnchor),
            canvasView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            toolbarView.topAnchor.constraint(equalTo: container.topAnchor),
            toolbarView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbarView.heightAnchor.constraint(equalToConstant: 50),

            zoomOverlay.topAnchor.constraint(equalTo: container.topAnchor),
            zoomOverlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            zoomOverlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            zoomOverlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            loadingOverlay.topAnchor.constraint(equalTo: container.topAnchor),
            loadingOverlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            loadingOverlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            loadingOverlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: loadingOverlay.centerYAnchor),
        ])

        self.view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if canvasView.document.nodes.isEmpty {
            loadSchemasAndGenerate()
        }
    }

    private func loadSchemasAndGenerate() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            let dbType = instance.databaseType
            switch dbType {
            case .postgres, .supabase, .convex, .mysql:
                do {
                    let results = try await instance.databaseService.getInformationSchema()
                    schemas = results.map(\.name)
                } catch {
                    schemas = []
                }
            default:
                schemas = []
            }

            let defaultSchema = schemas.contains("public") ? "public" : schemas.first
            currentSchema = defaultSchema
            toolbarView.setSchemas(schemas, selected: defaultSchema)
            generateERD(schema: currentSchema)
        }
    }

    private var layoutStorageKey: String {
        let connectionId = instance.connection.persistentModelID.storeIdentifier ?? "unknown"
        return "erdLayout_\(connectionId)_\(currentSchema ?? "all")"
    }

    private func generateERD(schema: String?) {
        guard !isGenerating else { return }
        isGenerating = true
        loadingOverlay.isHidden = false
        spinner.startAnimation(nil)

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                var document = try await ERDSchemaReader.generateERD(from: instance, schema: schema)
                restoreSavedPositions(into: &document)
                canvasView.document = document
                updateZoomState()
            } catch {}
            spinner.stopAnimation(nil)
            loadingOverlay.isHidden = true
            isGenerating = false
        }
    }

    // MARK: - Layout Persistence

    private func saveNodePositions() {
        var positions: [String: [String: CGFloat]] = [:]
        for node in canvasView.document.nodes {
            guard case .erdTable(let data) = node.kind else { continue }
            positions[data.tableName] = ["x": node.position.x, "y": node.position.y]
        }

        guard let encoded = try? Foundation.JSONEncoder().encode(positions) else { return }
        UserDefaults.standard.set(encoded, forKey: layoutStorageKey)
    }

    private typealias PositionMap = [String: [String: CGFloat]]

    private func restoreSavedPositions(into document: inout CanvasDocument) {
        guard let savedData = UserDefaults.standard.data(forKey: layoutStorageKey),
              let positions = try? Foundation.JSONDecoder().decode(PositionMap.self, from: savedData) else {
            return
        }

        var restoredCount = 0
        for index in document.nodes.indices {
            guard case .erdTable(let tableData) = document.nodes[index].kind,
                  let pos = positions[tableData.tableName],
                  let x = pos["x"], let y = pos["y"] else {
                continue
            }
            document.nodes[index].position = CGPoint(x: x, y: y)
            restoredCount += 1
        }

        if restoredCount > 0 && restoredCount < document.nodes.count {
            var offset: CGFloat = 0
            for index in document.nodes.indices {
                guard case .erdTable(let tableData) = document.nodes[index].kind else { continue }
                if positions[tableData.tableName] == nil {
                    document.nodes[index].position = CGPoint(x: 120 + offset, y: 120 + offset)
                    offset += 40
                }
            }
        }
    }

    private func clearSavedPositions() {
        UserDefaults.standard.removeObject(forKey: layoutStorageKey)
    }

    private func zoomAction(_ action: @escaping (CanvasNSView) -> Void) -> () -> Void {
        { [weak self] in
            guard let self else { return }
            action(canvasView)
            updateZoomState()
        }
    }

    private func updateZoomState() {
        let zoom = Int(canvasView.document.viewport.zoomLevel * 100)
        zoomOverlay.zoomPercentage = zoom
    }

    // MARK: - CanvasNSViewDelegate

    nonisolated func canvasDidChangeSelection(_ selectedNodeIds: Set<UUID>) {
    }

    nonisolated func canvasDidChangeZoom() {
        Task { @MainActor [weak self] in
            self?.updateZoomState()
        }
    }

    nonisolated func canvasDidFinishDraggingNode() {
        Task { @MainActor [weak self] in
            self?.saveNodePositions()
        }
    }

    nonisolated func canvasDidDoubleClickNode(_ node: CanvasNode) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if case .erdTable(let data) = node.kind {
                instance.createNewTab(
                    name: data.tableName,
                    databaseSchema: data.schemaName
                )
            }
        }
    }
}

// MARK: - CanvasToolbarViewDelegate

extension CanvasViewController: CanvasToolbarViewDelegate {
    func toolbarDidSelectSchema(_ schema: String?) {
        currentSchema = schema
        generateERD(schema: schema)
    }

    func toolbarDidTapResetLayout() {
        clearSavedPositions()
        generateERD(schema: currentSchema)
    }
}
