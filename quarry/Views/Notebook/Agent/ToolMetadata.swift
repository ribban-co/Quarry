import Foundation

@MainActor
enum ToolMetadata {

    static func groupKey(for toolName: String) -> String {
        switch toolName {
        case "create_chart_block", "create_text_block", "create_single_value_block", "create_query_block": return "create_block"
        case "update_chart_block", "update_text_block", "update_single_value_block", "update_query_block": return "update_block"
        default: return toolName
        }
    }

    static func pillIcon(for toolName: String) -> String {
        switch toolName {
        case "run_query": return "magnifyingglass"
        default: return icon(for: toolName)
        }
    }

    static func icon(for toolName: String) -> String {
        switch toolName {
        case "list_databases": return "cylinder.split.1x2"
        case "list_tables": return "tablecells"
        case "get_table_schema": return "square.stack.3d.up"
        case "run_query": return "rectangle.and.text.magnifyingglass"
        case "run_write_query": return "pencil.and.list.clipboard"
        case "open_query_tab": return "rectangle.badge.plus"
        case "set_notebook_info": return "text.document"
        case "list_notebook_blocks": return "list.bullet"
        case "create_chart_block", "update_chart_block": return "chart.bar"
        case "create_single_value_block", "update_single_value_block": return "numbers.rectangle"
        case "create_text_block", "update_text_block": return "text.append"
        case "create_query_block", "update_query_block": return "terminal"
        case "create_block": return "chart.bar"
        case "update_block": return "pencil"
        case "arrange_dashboard": return "rectangle.3.group"
        default: return "gearshape"
        }
    }

    static func groupHeader(for toolName: String) -> String {
        switch toolName {
        case "list_databases": return "Listing databases"
        case "list_tables": return "Exploring database"
        case "get_table_schema": return "Reading schema"
        case "run_query": return "Querying data"
        case "run_write_query": return "Modifying data"
        case "open_query_tab": return "Opening results"
        case "set_notebook_info": return "Setting up notebook"
        case "list_notebook_blocks": return "Reading notebook"
        case "create_chart_block", "create_text_block", "create_single_value_block", "create_query_block", "create_block": return "Building visualizations"
        case "update_chart_block", "update_text_block", "update_single_value_block", "update_query_block", "update_block": return "Updating block"
        case "arrange_dashboard": return "Arranging dashboard"
        default: return "Processing"
        }
    }

    static func displayInfo(for name: String, arguments: String = "") -> (text: String, icon: String) {
        let json = parseToolArguments(arguments)

        switch name {
        case "list_databases":
            return ("Listing databases", icon(for: name))

        case "list_tables":
            let schema = json["schema_name"] as? String
            let label = schema != nil ? "Listing tables in \(schema!)" : "Listing all tables"
            return (label, icon(for: name))

        case "get_table_schema":
            let table = json["table_name"] as? String
            let label = table != nil ? "Reading \(table!) schema" : "Reading table schema"
            return (label, icon(for: name))

        case "run_query":
            let query = json["query"] as? String ?? ""
            let preview = queryPreview(query)
            return (preview.isEmpty ? "Running query" : preview, icon(for: name))

        case "run_write_query":
            let query = json["query"] as? String ?? ""
            let preview = queryPreview(query)
            return (preview.isEmpty ? "Modifying data" : preview, icon(for: name))

        case "open_query_tab":
            return ("Opening results in a query tab", icon(for: name))

        case "set_notebook_info":
            let title = json["title"] as? String
            return (title != nil ? "Setting title: \(title!)" : "Setting notebook info", icon(for: name))

        case "create_chart_block":
            let title = json["title"] as? String
            return (title ?? "Chart", icon(for: name))

        case "create_single_value_block":
            let title = json["title"] as? String
            return (title ?? "Single Value", icon(for: name))

        case "create_text_block":
            let title = json["title"] as? String
            return (title ?? "Text block", icon(for: name))

        case "create_query_block":
            let title = json["title"] as? String
            return (title ?? "Query block", icon(for: name))

        case "list_notebook_blocks":
            return ("Listing existing blocks", icon(for: name))

        case "update_chart_block":
            let title = json["title"] as? String
            return (title != nil ? "Updating: \(title!)" : "Updating chart", icon(for: name))

        case "update_single_value_block":
            let title = json["title"] as? String
            return (title != nil ? "Updating: \(title!)" : "Updating metric", icon(for: name))

        case "update_text_block":
            let title = json["title"] as? String
            return (title != nil ? "Updating: \(title!)" : "Updating text block", icon(for: name))

        case "update_query_block":
            let title = json["title"] as? String
            return (title != nil ? "Updating: \(title!)" : "Updating query", icon(for: name))

        case "arrange_dashboard":
            let blocks = json["blocks"] as? [[String: Any]]
            let count = blocks?.count ?? 0
            return ("Arranging \(count) blocks", icon(for: name))

        default:
            return (name.replacing("_", with: " ").capitalized, icon(for: name))
        }
    }

    // MARK: - Private

    private static func parseToolArguments(_ arguments: String) -> [String: Any] {
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    private static func queryPreview(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let oneLine = trimmed.replacing(/\s+/, with: " ")
        if oneLine.count <= 60 { return oneLine }
        return String(oneLine.prefix(57)) + "..."
    }
}
