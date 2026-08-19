import Foundation

struct CachedChartData: Codable {
    let points: [Point]

    struct Point: Codable {
        let x: String
        let y: Double
        let series: String
    }
}

struct CachedSingleValue: Codable {
    let value: Double
}

struct CachedQueryData: Codable {
    let columns: [Column]
    let rows: [[String: String?]]

    struct Column: Codable {
        let name: String
        let dataType: String
        let format: String?
        let index: Int
    }
}

extension CachedChartData {
    init(from chartData: [ChartDataPoint]) {
        points = chartData.map { Point(x: $0.x, y: $0.y, series: $0.series) }
    }

    func toChartData() -> [ChartDataPoint] {
        points.map { ChartDataPoint(x: $0.x, y: $0.y, series: $0.series) }
    }
}

extension CachedQueryData {
    private static let maxCachedRows = 500

    init(from result: QueryResult) {
        columns = result.columns.map {
            Column(name: $0.name, dataType: $0.dataType, format: $0.format, index: $0.index)
        }
        rows = result.rows.prefix(Self.maxCachedRows).map { row in
            var stringRow: [String: String?] = [:]
            for (key, info) in row {
                if let val = info.value {
                    stringRow[key] = val.stringValue ?? val.description
                } else {
                    stringRow[key] = nil
                }
            }
            return stringRow
        }
    }

    func toQueryResult() -> QueryResult {
        let columnInfos = columns.map {
            QueryColumnInfo(name: $0.name, dataType: $0.dataType, format: $0.format, index: $0.index)
        }
        let typeByName = Dictionary(uniqueKeysWithValues: columns.map { ($0.name, ($0.dataType, $0.format)) })
        let resultRows: [[String: QueryRowInfo]] = rows.map { row in
            var infoRow: [String: QueryRowInfo] = [:]
            for (key, val) in row {
                let (dt, fmt) = typeByName[key] ?? ("text", nil)
                infoRow[key] = QueryRowInfo(value: val as Any?, dataType: dt, format: fmt)
            }
            return infoRow
        }
        let rawRows: [DatabaseRawRow] = rows.map { row in
            var raw: DatabaseRawRow = [:]
            for (key, val) in row {
                raw[key] = val.map(DatabaseValue.string)
            }
            return raw
        }
        return QueryResult(
            columns: columnInfos,
            rows: resultRows,
            totalCount: resultRows.count,
            rawRows: rawRows
        )
    }
}

extension NotebookBlock {
    private func decodeCachedResult<T: Decodable>(_ type: T.Type) -> T? {
        guard !cachedResultJSON.isEmpty,
              let data = cachedResultJSON.data(using: .utf8) else { return nil }
        return try? Foundation.JSONDecoder().decode(type, from: data)
    }

    func cachedChartData() -> CachedChartData? { decodeCachedResult(CachedChartData.self) }
    func cachedSingleValue() -> CachedSingleValue? { decodeCachedResult(CachedSingleValue.self) }
    func cachedQueryData() -> CachedQueryData? { decodeCachedResult(CachedQueryData.self) }

    func saveCachedResult(_ result: some Encodable) {
        guard let data = try? JSONEncoder().encode(result),
              let json = String(data: data, encoding: .utf8) else { return }
        cachedResultJSON = json
    }
}
