import Foundation

enum NotebookCellType: String, CaseIterable {
    case query = "Query"
    case python = "Python"
    case text = "Text"
    case chart = "Chart"
    case singleValue = "Single Value"
    case parameter = "Parameter"

    var icon: String {
        switch self {
        case .query: "terminal"
        case .python: "chevron.left.forwardslash.chevron.right"
        case .text: "doc.text"
        case .chart: "chart.bar"
        case .singleValue: "numbers.rectangle"
        case .parameter: "slider.horizontal.3"
        }
    }

    var blockKind: NotebookBlockKind? {
        switch self {
        case .chart: .chart
        case .text: .text
        case .singleValue: .singleValue
        case .query: .query
        default: nil
        }
    }

    var isEnabled: Bool {
        blockKind != nil
    }
}
