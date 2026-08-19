import Foundation
import RegexBuilder
import CodeEditorView
import LanguageSupport

extension LanguageConfiguration {

    public static func javascript(_ languageService: LanguageService? = nil) -> LanguageConfiguration {

        let numberRegex: Regex<Substring> = Regex {
            Optionally("-")
            ChoiceOf {
                Regex { /0[xX]/; hexalLit }
                Regex { "."; decimalLit; Optionally { exponentLit } }
                Regex { decimalLit; "."; decimalLit; Optionally { exponentLit } }
                Regex { decimalLit; exponentLit }
                decimalLit
            }
        }

        let identifierRegex: Regex<Substring> = Regex {
            CharacterClass("a"..."z", "A"..."Z", .anyOf("_$"))
            ZeroOrMore {
                CharacterClass("a"..."z", "A"..."Z", "0"..."9", .anyOf("_$"))
            }
        }

        return LanguageConfiguration(
            name: "JavaScript",
            supportsSquareBrackets: true,
            supportsCurlyBrackets: true,
            caseInsensitiveReservedIdentifiers: false,
            stringRegex: /"(?:\\"|[^"])*"|'(?:\\'|[^'])*'/,
            characterRegex: nil,
            numberRegex: numberRegex,
            singleLineComment: "//",
            nestedComment: (open: "/*", close: "*/"),
            identifierRegex: identifierRegex,
            operatorRegex: nil,
            reservedIdentifiers: jsReservedIdentifiers,
            reservedOperators: jsReservedOperators,
            languageService: languageService
        )
    }

    private static let jsReservedIdentifiers = [
        // Literals
        "true", "false", "null", "undefined",

        // Declarations
        "const", "let", "var", "function", "class",

        // Control flow
        "if", "else", "for", "while", "do", "switch", "case", "break", "continue",
        "return", "throw", "try", "catch", "finally",

        // Modules
        "export", "default", "import", "from",

        // Async
        "async", "await",

        // Operators & keywords
        "new", "this", "typeof", "instanceof", "in", "of", "delete", "void",
        "yield", "super", "extends", "static",
    ]

    private static let jsReservedOperators = [
        "===", "!==", "==", "!=",
        ">=", "<=", ">", "<",
        "&&", "||", "!",
        "=>", "...",
        "+=", "-=", "*=", "/=",
        "+", "-", "*", "/", "%",
        "=", ":", ",", "?",
    ]
}
