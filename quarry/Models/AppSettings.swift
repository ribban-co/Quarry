//
//  AppSettings.swift
//  Quarry
//

import SwiftUI

enum AutoCompleteKey: String, CaseIterable {
    case enter = "Enter"
    case tab = "Tab"

    var icon: String {
        switch self {
        case .enter: "return"
        case .tab: "arrow.right.to.line"
        }
    }
}

enum IndentStyle: String, CaseIterable {
    case spaces = "Spaces"
    case tabs = "Tabs"
}

enum CSVDelimiter: String, CaseIterable {
    case comma = "Comma"
    case semicolon = "Semicolon"
    case tab = "Tab"
    case pipe = "Pipe"

    var icon: String {
        switch self {
        case .comma: "comma"
        case .semicolon: "semicolon"
        case .tab: "arrow.right.to.line"
        case .pipe: "line.vertical"
        }
    }
}

enum CSVQuoteStyle: String, CaseIterable {
    case quoteIfNeeded = "Quote if needed"
    case alwaysQuote = "Always quote"
    case neverQuote = "Never quote"

    var icon: String {
        switch self {
        case .quoteIfNeeded: "quote.opening"
        case .alwaysQuote: "quote.closing"
        case .neverQuote: "textformat"
        }
    }
}

enum CSVLineBreak: String, CaseIterable {
    case lf = "\\n"
    case crlf = "\\r\\n"
    case cr = "\\r"

    var icon: String {
        switch self {
        case .lf: "return"
        case .crlf: "return"
        case .cr: "return"
        }
    }
}

enum HistoryRetention: String, CaseIterable {
    case days30 = "30 days"
    case days60 = "60 days"
    case days90 = "90 days"
    case days180 = "180 days"
    case forever = "Forever"

    var icon: String {
        switch self {
        case .days30, .days60, .days90, .days180: "calendar"
        case .forever: "infinity"
        }
    }
}

enum NewTabBehavior: String, CaseIterable {
    case sqlEditor = "SQL Query Editor"
    case tableBrowser = "Table Browser"
    case lastUsed = "Last Used"

    var icon: String {
        switch self {
        case .sqlEditor: "chevron.left.forwardslash.chevron.right"
        case .tableBrowser: "tablecells"
        case .lastUsed: "clock"
        }
    }
}

enum SidebarIconSize: String, CaseIterable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"

    var icon: String {
        switch self {
        case .small: "textformat.size.smaller"
        case .medium: "textformat.size"
        case .large: "textformat.size.larger"
        }
    }
}

enum SyntaxTheme: String, CaseIterable {
    case `default` = "Default"
    case dracula = "Dracula"
    case solarizedLight = "Solarized Light"
    case solarizedDark = "Solarized Dark"
    case oneDark = "One Dark"
    case github = "GitHub"

    var icon: String {
        switch self {
        case .default: "paintpalette"
        case .dracula: "moon.fill"
        case .solarizedLight: "sun.max"
        case .solarizedDark: "sun.max.fill"
        case .oneDark: "circle.lefthalf.filled"
        case .github: "chevron.left.forwardslash.chevron.right"
        }
    }
}

enum PasswordTimeout: String, CaseIterable {
    case never = "Never"
    case minutes15 = "15 minutes"
    case hour1 = "1 hour"
    case hours4 = "4 hours"

    var icon: String {
        switch self {
        case .never: "infinity"
        case .minutes15, .hour1, .hours4: "clock"
        }
    }
}

enum AutoDisconnectTimeout: String, CaseIterable {
    case never = "Never"
    case minutes15 = "15 minutes"
    case hour1 = "1 hour"
    case hours4 = "4 hours"

    var icon: String {
        switch self {
        case .never: "infinity"
        case .minutes15, .hour1, .hours4: "clock"
        }
    }
}

enum KeymapPreset: String, CaseIterable {
    case `default` = "Default"
    case vsCode = "VS Code"
    case sublimeText = "Sublime Text"
    case jetBrains = "JetBrains"

    var icon: String {
        switch self {
        case .default: "keyboard"
        case .vsCode: "curlybraces"
        case .sublimeText: "text.cursor"
        case .jetBrains: "hammer"
        }
    }
}

/// Governs how much friction stands between the user and a query hitting the server.
/// Modelled on Sequel Ace's silent/alert/safe modes.
enum QueryAlertMode: String, CaseIterable {
    case silent = "Silent Mode"
    case alert1 = "Alert Mode 1"
    case alert2 = "Alert Mode 2"
    case safe1 = "Safe Mode 1"
    case safe2 = "Safe Mode 2"

    static let storageKey = "queryAlertMode"
    static let `default` = QueryAlertMode.silent

    var summary: String {
        switch self {
        case .silent: "Send queries to the server without any warnings"
        case .alert1: "Warn before sending queries to the server"
        case .alert2: "Warn before sending queries to the server except SELECT/EXPLAIN/SHOW queries"
        case .safe1: "Prompt for password before sending queries to the server"
        case .safe2: "Prompt for password before sending queries to the server except SELECT/EXPLAIN/SHOW queries"
        }
    }

    var icon: String {
        switch self {
        case .silent: "bolt"
        case .alert1: "exclamationmark.triangle"
        case .alert2: "exclamationmark.triangle.fill"
        case .safe1: "lock"
        case .safe2: "lock.fill"
        }
    }

    /// Whether the user has to re-enter the connection password to proceed.
    var requiresPassword: Bool {
        self == .safe1 || self == .safe2
    }

    /// Whether read-only queries pass through unprompted.
    var allowsReadOnlyQueries: Bool {
        self == .alert2 || self == .safe2
    }
}
