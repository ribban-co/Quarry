import Foundation
import JavaScriptCore

@MainActor class JSFormatter {
    private static let shared = JSFormatter()
    private let jsContext: JSContext
    private var isLoaded = false

    private init() {
        jsContext = JSContext()
        setupJavaScriptEnvironment()
    }

    private func setupJavaScriptEnvironment() {
        guard let jsPath = Bundle.main.path(forResource: "js-beautify.min", ofType: "js"),
              let jsContent = try? String(contentsOfFile: jsPath, encoding: .utf8) else {
            return
        }

        // js-beautify exports to `global.js_beautify` when no module system is detected.
        // JavaScriptCore doesn't have `global`, so create it pointing to `this` (the global object).
        jsContext.evaluateScript("var global = this;")
        jsContext.evaluateScript(jsContent)

        let check = jsContext.evaluateScript("typeof js_beautify")
        isLoaded = check?.toString() == "function"
    }

    static func format(_ code: String, options: JSFormatOptions = JSFormatOptions()) -> String {
        shared.formatJS(code, options: options)
    }

    private func formatJS(_ code: String, options: JSFormatOptions) -> String {
        guard isLoaded else { return code }

        jsContext.setObject(code, forKeyedSubscript: "__inputCode" as NSString)

        let jsOptions = """
        {
            indent_size: \(options.indentSize),
            indent_char: '\(options.useTabs ? "\\t" : " ")',
            max_preserve_newlines: \(options.maxPreserveNewlines),
            preserve_newlines: true,
            keep_array_indentation: false,
            break_chained_methods: false,
            space_before_conditional: true,
            unescape_strings: false,
            jslint_happy: false,
            end_with_newline: true,
            wrap_line_length: 0,
            e4x: false,
            comma_first: false,
            operator_position: 'before-newline'
        }
        """

        let jsCode = """
        (function() {
            try {
                return js_beautify(__inputCode, \(jsOptions));
            } catch (error) {
                return null;
            }
        })()
        """

        guard let result = jsContext.evaluateScript(jsCode),
              !result.isNull,
              !result.isUndefined,
              let formatted = result.toString() else {
            return code
        }

        return formatted
    }
}

struct JSFormatOptions {
    let indentSize: Int
    let useTabs: Bool
    let maxPreserveNewlines: Int

    init(
        indentSize: Int = 2,
        useTabs: Bool = false,
        maxPreserveNewlines: Int = 2
    ) {
        self.indentSize = indentSize
        self.useTabs = useTabs
        self.maxPreserveNewlines = maxPreserveNewlines
    }
}
