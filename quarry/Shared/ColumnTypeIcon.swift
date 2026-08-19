import Foundation

/// Maps a database column's data type to the SF Symbol used to represent it.
/// Shared by the table-view header cell and the sidebar's schema list so both
/// surfaces show the same glyph for a given type.
enum ColumnTypeIcon {

    /// SF Symbol shown for a foreign-key column on any surface.
    static let foreignKeySymbol = "link"

    /// SF Symbol + recommended point size for a column's data type.
    static func icon(forType fieldType: String) -> (symbol: String, size: CGFloat) {
        switch fieldType.lowercased() {
        case let type where type.contains("text") || type.hasPrefix("char") || type.contains("varchar") || type.contains("var") || type.hasPrefix("string"):
            return ("textformat.alt", 10)
        case let type where type.contains("int") || type.contains("short") || type.contains("tiny") || type == "id":
            return ("number", 12)
        case "numeric", "decimal", "real", "double precision", "float", "money", "double", "float64":
            return ("dollarsign", 13)
        case "enum":
            return ("list.bullet", 13)
        case let type where type.hasPrefix("unknown"):
            return ("tag", 14)
        case "bool", "boolean":
            return ("switch.2", 14)
        case "xml":
            return ("ellipsis.curlybraces", 13)
        case let type where type.hasPrefix("timestamp") || type.hasPrefix("date") || type == "year":
            return ("calendar", 13)
        case let type where type.contains("time"):
            return ("clock", 14)
        case "uuid":
            return ("barcode", 12)
        case "json", "jsonb", "object", "record":
            return ("curlybraces", 13)
        case "array":
            return ("square.stack", 13)
        case "bytea", "bytes":
            return ("cpu", 12)
        default:
            return ("questionmark.circle", 14)
        }
    }
}
