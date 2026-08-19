import Foundation

enum ConvexAggregator {

    static func aggregate(
        _ result: QueryResult,
        dimensions: [String],
        measures: [(column: String, aggregation: AggregationFunction)]
    ) -> QueryResult {
        guard !result.rows.isEmpty else {
            let columns = buildAggregateColumns(dimensions: dimensions, measures: measures)
            return QueryResult(columns: columns, rows: [], totalCount: 0, rawRows: [])
        }

        var groups: [[[String: QueryRowInfo]]] = []
        var groupIndex: [String: Int] = [:]

        for row in result.rows {
            let key = dimensions.map { dim in
                row[dim]?.value.map { "\($0)" } ?? "NULL"
            }.joined(separator: "\u{0}")

            if let idx = groupIndex[key] {
                groups[idx].append(row)
            } else {
                groupIndex[key] = groups.count
                groups.append([row])
            }
        }

        // Build dimension keys in insertion order
        let orderedKeys = groupIndex.sorted(by: { $0.value < $1.value }).map(\.key)

        let columns = buildAggregateColumns(dimensions: dimensions, measures: measures)

        var outputRows: [[String: QueryRowInfo]] = []
        var outputRawRows: [DatabaseRawRow] = []

        for key in orderedKeys {
            guard let idx = groupIndex[key],
                  let firstRow = groups[idx].first else { continue }
            let groupRows = groups[idx]

            var row: [String: QueryRowInfo] = [:]
            var rawRow: DatabaseRawRow = [:]

            for dim in dimensions {
                let info = firstRow[dim] ?? QueryRowInfo(value: nil, dataType: "text", format: nil)
                row[dim] = info
                rawRow[dim] = info.value
            }

            for measure in measures {
                let aliasCol = "\(measure.column)\(measure.aggregation.sqlAliasSuffix)"
                let value = computeAggregation(
                    rows: groupRows,
                    column: measure.column,
                    aggregation: measure.aggregation
                )
                let databaseValue = value.map(DatabaseValue.double)
                row[aliasCol] = QueryRowInfo(value: databaseValue, dataType: "float8", format: nil)
                rawRow[aliasCol] = databaseValue
            }

            outputRows.append(row)
            outputRawRows.append(rawRow)
        }

        return QueryResult(
            columns: columns,
            rows: outputRows,
            totalCount: outputRows.count,
            rawRows: outputRawRows
        )
    }

    static func singleValue(
        _ result: QueryResult,
        column: String,
        aggregation: AggregationFunction
    ) -> Double? {
        computeAggregation(rows: result.rows, column: column, aggregation: aggregation)
    }

    // MARK: - Private

    private static func buildAggregateColumns(
        dimensions: [String],
        measures: [(column: String, aggregation: AggregationFunction)]
    ) -> [QueryColumnInfo] {
        var columns: [QueryColumnInfo] = []
        var idx = 0
        for dim in dimensions {
            columns.append(QueryColumnInfo(name: dim, dataType: "text", format: nil, index: idx))
            idx += 1
        }
        for measure in measures {
            let alias = "\(measure.column)\(measure.aggregation.sqlAliasSuffix)"
            columns.append(QueryColumnInfo(name: alias, dataType: "float8", format: nil, index: idx))
            idx += 1
        }
        return columns
    }

    private static func computeAggregation(
        rows: [[String: QueryRowInfo]],
        column: String,
        aggregation: AggregationFunction
    ) -> Double? {
        switch aggregation {
        case .count:
            return Double(rows.count)
        case .countDistinct:
            var seen: Set<String> = []
            for row in rows {
                if let val = row[column]?.value {
                    seen.insert("\(val)")
                }
            }
            return Double(seen.count)
        case .sum:
            var total = 0.0
            for row in rows {
                if let v = toDouble(row[column]?.value) { total += v }
            }
            return total
        case .average:
            var total = 0.0
            var count = 0
            for row in rows {
                if let v = toDouble(row[column]?.value) {
                    total += v
                    count += 1
                }
            }
            return count > 0 ? total / Double(count) : nil
        case .min:
            var result: Double?
            for row in rows {
                if let v = toDouble(row[column]?.value) {
                    result = result.map { Swift.min($0, v) } ?? v
                }
            }
            return result
        case .max:
            var result: Double?
            for row in rows {
                if let v = toDouble(row[column]?.value) {
                    result = result.map { Swift.max($0, v) } ?? v
                }
            }
            return result
        case .none:
            return toDouble(rows.first?[column]?.value)
        }
    }

    private static func toDouble(_ value: DatabaseValue?) -> Double? {
        switch value {
        case .double(let value):
            value
        case .int(let value):
            Double(value)
        case .int64(let value):
            Double(value)
        case .string(let value), .decimalString(let value):
            Double(value)
        default:
            nil
        }
    }
}
