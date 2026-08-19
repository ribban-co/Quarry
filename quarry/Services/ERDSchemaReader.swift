import Foundation

struct ERDSchemaReader {
    @MainActor static func generateERD(from instance: ConnectionInstance, schema: String? = nil) async throws -> CanvasDocument {
        let databaseService = instance.databaseService

        let collections = try await databaseService.listCollections(schema: schema)
        let tableNames = collections
            .filter { !["function", "procedure"].contains($0.type) }
            .map { (name: $0.name, schema: $0.schema) }

        guard !tableNames.isEmpty else {
            return CanvasDocument()
        }

        var nodes: [CanvasNode] = []
        var edges: [CanvasEdge] = []
        var nodeIdByTable: [String: UUID] = [:]

        for table in tableNames {
            guard let schemaResult = try await databaseService.getSchema(
                for: table.name,
                databaseSchema: table.schema
            ) else {
                continue
            }

            let columns = schemaResult.columns.map { col in
                ERDColumnInfo(
                    name: col.columnName,
                    dataType: col.dataType,
                    isPrimaryKey: col.isPrimaryKey,
                    isForeignKey: col.hasForeignKey,
                    isNullable: col.isNullable == "YES",
                    foreignKeyTarget: col.primaryForeignKeyConstraint.flatMap { constraint in
                        guard let refTable = constraint.referencedTable,
                              let refCol = constraint.referencedColumns?.first else {
                            return nil
                        }
                        return ForeignKeyRef(
                            schema: constraint.referencedSchema,
                            table: refTable,
                            column: refCol
                        )
                    }
                )
            }

            let tableData = ERDTableData(
                schemaName: table.schema,
                tableName: table.name,
                columns: columns
            )

            let rowHeight: CGFloat = 28
            let headerHeight: CGFloat = 40
            let nodeHeight = headerHeight + 8 + CGFloat(columns.count) * rowHeight + 8
            let nodeWidth: CGFloat = 280

            let node = CanvasNode(
                position: .zero,
                size: CGSize(width: nodeWidth, height: nodeHeight),
                kind: .erdTable(tableData),
                zIndex: 0
            )

            nodeIdByTable[table.name] = node.id
            nodes.append(node)
        }

        // Build directed edges from foreign keys
        // source (child with FK) → target (referenced parent)
        var outgoing: [UUID: Set<UUID>] = [:]
        var incoming: [UUID: Set<UUID>] = [:]
        for node in nodes {
            outgoing[node.id] = []
            incoming[node.id] = []
        }

        for node in nodes {
            guard case .erdTable(let tableData) = node.kind else { continue }

            for column in tableData.columns {
                guard let fkRef = column.foreignKeyTarget,
                      let targetNodeId = nodeIdByTable[fkRef.table] else {
                    continue
                }

                let edge = CanvasEdge(
                    sourceNodeId: node.id,
                    sourcePort: column.name,
                    targetNodeId: targetNodeId,
                    targetPort: fkRef.column,
                    kind: .foreignKey
                )
                edges.append(edge)

                outgoing[node.id, default: []].insert(targetNodeId)
                incoming[targetNodeId, default: []].insert(node.id)
            }
        }

        layoutNodesHierarchical(&nodes, outgoing: outgoing, incoming: incoming)

        var document = CanvasDocument(nodes: nodes, edges: edges)
        document.viewport.zoomLevel = 0.5
        return document
    }

    // MARK: - Hierarchical Layout (Dagre-inspired)

    private static let rankSep: CGFloat = 100
    private static let nodeSep: CGFloat = 50
    private static let layoutMargin: CGFloat = 120
    private static let nodeWidth: CGFloat = 280

    private static func layoutNodesHierarchical(
        _ nodes: inout [CanvasNode],
        outgoing: [UUID: Set<UUID>],
        incoming: [UUID: Set<UUID>]
    ) {
        guard !nodes.isEmpty else { return }

        // Phase 1: Rank assignment via longest-path from roots
        let ranks = assignRanks(nodes: nodes, outgoing: outgoing, incoming: incoming)

        // Group node indices by rank
        var rankBuckets: [Int: [Int]] = [:]
        for (nodeIndex, rank) in ranks {
            rankBuckets[rank, default: []].append(nodeIndex)
        }

        let maxRank = rankBuckets.keys.max() ?? 0

        // Phase 2: Minimize crossings with barycenter heuristic (4 passes)
        guard maxRank > 0 else {
            // All nodes in a single rank — skip crossing minimization, go to positioning
            assignPositions(nodes: &nodes, rankBuckets: rankBuckets, maxRank: maxRank)
            return
        }

        for pass in 0..<4 {
            if pass % 2 == 0 {
                // Forward pass (L→R): order by neighbor positions in previous rank
                for rank in 1...maxRank {
                    guard var bucket = rankBuckets[rank] else { continue }
                    let prevBucket = rankBuckets[rank - 1] ?? []
                    let prevPositions = Dictionary(uniqueKeysWithValues: prevBucket.enumerated().map { (nodes[$1].id, $0) })

                    bucket.sort { a, b in
                        let baryA = barycenter(nodeIndex: a, nodes: nodes, neighbors: incoming, positions: prevPositions)
                        let baryB = barycenter(nodeIndex: b, nodes: nodes, neighbors: incoming, positions: prevPositions)
                        return baryA < baryB
                    }
                    rankBuckets[rank] = bucket
                }
            } else {
                // Backward pass (R→L): order by neighbor positions in next rank
                for rank in stride(from: maxRank - 1, through: 0, by: -1) {
                    guard var bucket = rankBuckets[rank] else { continue }
                    let nextBucket = rankBuckets[rank + 1] ?? []
                    let nextPositions = Dictionary(uniqueKeysWithValues: nextBucket.enumerated().map { (nodes[$1].id, $0) })

                    bucket.sort { a, b in
                        let baryA = barycenter(nodeIndex: a, nodes: nodes, neighbors: outgoing, positions: nextPositions)
                        let baryB = barycenter(nodeIndex: b, nodes: nodes, neighbors: outgoing, positions: nextPositions)
                        return baryA < baryB
                    }
                    rankBuckets[rank] = bucket
                }
            }
        }

        // Phase 3: Position assignment
        assignPositions(nodes: &nodes, rankBuckets: rankBuckets, maxRank: maxRank)
    }

    private static func assignPositions(
        nodes: inout [CanvasNode],
        rankBuckets: [Int: [Int]],
        maxRank: Int
    ) {
        var rankHeights: [Int: CGFloat] = [:]
        for rank in 0...maxRank {
            let bucket = rankBuckets[rank] ?? []
            let totalHeight = bucket.reduce(CGFloat(0)) { acc, idx in
                acc + nodes[idx].size.height
            } + CGFloat(max(0, bucket.count - 1)) * nodeSep
            rankHeights[rank] = totalHeight
        }

        let globalMaxHeight = rankHeights.values.max() ?? 0

        for rank in 0...maxRank {
            let bucket = rankBuckets[rank] ?? []
            let rankHeight = rankHeights[rank] ?? 0
            let yOffset = layoutMargin + (globalMaxHeight - rankHeight) / 2

            var currentY = yOffset
            for nodeIndex in bucket {
                nodes[nodeIndex].position = CGPoint(
                    x: layoutMargin + CGFloat(rank) * (nodeWidth + rankSep),
                    y: currentY
                )
                currentY += nodes[nodeIndex].size.height + nodeSep
            }
        }
    }

    /// Assigns ranks using longest-path from roots (Kahn's algorithm).
    /// Disconnected components each get their own topological ordering.
    private static func assignRanks(
        nodes: [CanvasNode],
        outgoing: [UUID: Set<UUID>],
        incoming: [UUID: Set<UUID>]
    ) -> [Int: Int] {
        let indexById = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })
        var ranks: [Int: Int] = [:]

        // Find connected components using undirected BFS
        var visited = Set<UUID>()
        var components: [[UUID]] = []

        for node in nodes {
            guard !visited.contains(node.id) else { continue }
            var component: [UUID] = []
            var queue: [UUID] = [node.id]
            visited.insert(node.id)

            while !queue.isEmpty {
                let current = queue.removeFirst()
                component.append(current)

                let neighbors = (outgoing[current] ?? []).union(incoming[current] ?? [])
                for neighbor in neighbors where !visited.contains(neighbor) {
                    visited.insert(neighbor)
                    queue.append(neighbor)
                }
            }
            components.append(component)
        }

        for component in components {
            let componentSet = Set(component)

            // In-degree = number of children referencing this node
            // Nodes with 0 incoming = leaf/child tables = rank 0 (leftmost)
            // Matches Supabase/Dagre: edge sources (children) on left, targets (parents) on right
            var inDegree: [UUID: Int] = [:]
            for nodeId in component {
                let children = (incoming[nodeId] ?? []).filter { componentSet.contains($0) }
                inDegree[nodeId] = children.count
            }

            // Kahn's algorithm — BFS from nodes with no incoming edges
            var queue: [UUID] = component.filter { inDegree[$0] == 0 }
            if queue.isEmpty {
                let minNode = component.min { (inDegree[$0] ?? 0) < (inDegree[$1] ?? 0) }!
                queue = [minNode]
                inDegree[minNode] = 0
            }

            var dist: [UUID: Int] = [:]
            for nodeId in queue {
                dist[nodeId] = 0
            }

            while !queue.isEmpty {
                let current = queue.removeFirst()
                let currentRank = dist[current] ?? 0

                // Traverse along FK direction: current → parents it references
                let parents = (outgoing[current] ?? []).filter { componentSet.contains($0) }
                for parent in parents {
                    let newRank = currentRank + 1
                    if newRank > (dist[parent] ?? -1) {
                        dist[parent] = newRank
                    }
                    inDegree[parent, default: 0] -= 1
                    if inDegree[parent] == 0 {
                        queue.append(parent)
                    }
                }
            }

            // Assign any unvisited nodes (cycles) to rank 0
            for nodeId in component {
                if let idx = indexById[nodeId] {
                    ranks[idx] = dist[nodeId] ?? 0
                }
            }
        }

        return ranks
    }

    /// Computes the barycenter (average position) of a node's neighbors in the adjacent rank.
    private static func barycenter(
        nodeIndex: Int,
        nodes: [CanvasNode],
        neighbors: [UUID: Set<UUID>],
        positions: [UUID: Int]
    ) -> Double {
        let nodeId = nodes[nodeIndex].id
        let connected = (neighbors[nodeId] ?? []).compactMap { positions[$0] }
        guard !connected.isEmpty else { return Double(nodeIndex) }
        return Double(connected.reduce(0, +)) / Double(connected.count)
    }
}
