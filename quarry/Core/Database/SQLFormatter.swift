//
//  SQLFormatter.swift
//  Quarry
//
//  Created by Claude on 1/3/25.
//

import Foundation
import JavaScriptCore

@MainActor class SQLFormatter {
    private static let shared = SQLFormatter()
    private let jsContext: JSContext
    
    private init() {
        jsContext = JSContext()
        setupJavaScriptEnvironment()
    }
    
    private func setupJavaScriptEnvironment() {
        guard let jsPath = Bundle.main.path(forResource: "sql-formatter.min", ofType: "js"),
              let jsContent = try? String(contentsOfFile: jsPath, encoding: .utf8) else {
            return
        }

        jsContext.evaluateScript(jsContent)
    }
    
    static func format(_ sql: String, dialect: SQLDialect = .sqlite, options: SQLFormatOptions = SQLFormatOptions()) -> String {
        return shared.formatSQL(sql, dialect: dialect, options: options)
    }
    
    private func formatSQL(_ sql: String, dialect: SQLDialect, options: SQLFormatOptions) -> String {
        jsContext.setObject(sql, forKeyedSubscript: "__inputSQL" as NSString)

        let jsOptions = """
        {
            language: '\(dialect.rawValue)',
            tabWidth: \(options.tabWidth),
            useTabs: \(options.useTabs),
            keywordCase: '\(options.keywordCase.rawValue)',
            dataTypeCase: '\(options.dataTypeCase.rawValue)',
            functionCase: '\(options.functionCase.rawValue)',
            linesBetweenQueries: \(options.linesBetweenQueries)
        }
        """

        let jsCode = """
        (function() {
            try {
                return sqlFormatter.format(__inputSQL, \(jsOptions));
            } catch (error) {
                return null;
            }
        })()
        """

        guard let result = jsContext.evaluateScript(jsCode),
              !result.isNull,
              !result.isUndefined,
              let formattedSQL = result.toString() else {
            return sql
        }

        return formattedSQL
    }
}

// MARK: - Configuration Types

enum SQLDialect: String, CaseIterable {
    case sqlite = "sqlite"
    case postgresql = "postgresql"
    case mysql = "mysql"
    case mariadb = "mariadb"
    case bigquery = "bigquery"
    case redshift = "redshift"
    case spark = "spark"
    case snowflake = "snowflake"
    case tsql = "tsql"
    case plsql = "plsql"
    case transactsql = "transactsql"
    case hive = "hive"
    case n1ql = "n1ql"
    case db2 = "db2"
    case singlestoredb = "singlestoredb"
}

enum TextCase: String {
    case preserve = "preserve"
    case upper = "upper"
    case lower = "lower"
}

struct SQLFormatOptions {
    let tabWidth: Int
    let useTabs: Bool
    let keywordCase: TextCase
    let dataTypeCase: TextCase
    let functionCase: TextCase
    let linesBetweenQueries: Int
    
    init(
        tabWidth: Int = 2,
        useTabs: Bool = false,
        keywordCase: TextCase = .upper,
        dataTypeCase: TextCase = .upper,
        functionCase: TextCase = .upper,
        linesBetweenQueries: Int = 1
    ) {
        self.tabWidth = tabWidth
        self.useTabs = useTabs
        self.keywordCase = keywordCase
        self.dataTypeCase = dataTypeCase
        self.functionCase = functionCase
        self.linesBetweenQueries = linesBetweenQueries
    }
}