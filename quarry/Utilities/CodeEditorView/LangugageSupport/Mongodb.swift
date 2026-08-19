//
//  Mongodb.swift
//  Quarry
//
//  Created by Fauzaan on 4/1/25.
//

import Foundation
import RegexBuilder
import CodeEditorView
import LanguageSupport

extension LanguageConfiguration {
  
  public static func mongodb(_ languageService: LanguageService? = nil) -> LanguageConfiguration {
    
    // MongoDB number literals including integer, decimal, and scientific notation
    let numberRegex: Regex<Substring> = Regex {
      Optionally("-")
      ChoiceOf {
        Regex { /0[xX]/; hexalLit }            // Hexadecimal
        Regex { "."; decimalLit; Optionally { exponentLit } } // .123e4
        Regex { decimalLit; "."; decimalLit; Optionally { exponentLit } } // 123.456e7
        Regex { decimalLit; exponentLit }      // 123e4
        decimalLit                            // 123
      }
    }
    
    // MongoDB identifiers (field names, variables)
    let plainIdentifierRegex: Regex<Substring> = Regex {
      mongodbIdentifierHeadCharacters
      ZeroOrMore {
        mongodbIdentifierCharacters
      }
    }
    
    // MongoDB allows dot notation for accessing nested fields
    let identifierRegex: Regex<Substring> = Regex {
      ChoiceOf {
        plainIdentifierRegex
        Regex { plainIdentifierRegex; OneOrMore { "."; plainIdentifierRegex } } // field.nestedField
        Regex { "\""; OneOrMore { .any }; "\"" } // "quoted identifier"
        Regex { "'"; OneOrMore { .any }; "'" }   // 'quoted identifier'
      }
    }
    .matchingSemantics(.unicodeScalar)
    
    return LanguageConfiguration(name: "MongoDB",
                               supportsSquareBrackets: true,    // MongoDB uses [] for arrays
                               supportsCurlyBrackets: true,     // MongoDB uses {} for documents/objects
                               caseInsensitiveReservedIdentifiers: false, // MongoDB is case-sensitive
                               stringRegex: /"(?:\\"|[^"])*+"|'(?:\\'|[^'])*+'/,  // Support both " and ' for strings
                               characterRegex: nil,
                               numberRegex: numberRegex,
                               singleLineComment: "//",        // JavaScript-like comments
                               nestedComment: (open: "/*", close: "*/"),
                               identifierRegex: identifierRegex,
                               operatorRegex: nil,
                               reservedIdentifiers: mongodbReservedIdentifiers,
                               reservedOperators: mongodbReservedOperators,
                               languageService: languageService)
  }
  
  // MongoDB identifier rules (similar to JavaScript)
  nonisolated(unsafe) private static let mongodbIdentifierHeadCharacters: CharacterClass = CharacterClass(
    "a"..."z",
    "A"..."Z",
    .anyOf("_$"),
    "\u{80}" ... "\u{10FFFF}"
  )
  
  nonisolated(unsafe) private static let mongodbIdentifierCharacters: CharacterClass = CharacterClass(
    mongodbIdentifierHeadCharacters,
    "0"..."9"
  )
  
  // MongoDB operators and keywords
  // Includes CRUD operations, aggregation framework operators, and query operators
  private static let mongodbReservedIdentifiers = [
    // Query and Projection Operators
    "and", "or", "not", "nor", "eq", "gt", "gte", "in", "lt", "lte", "ne", "nin",
    "exists", "type", "expr", "jsonSchema", "mod", "regex", "where", "geoIntersects",
    "geoWithin", "near", "nearSphere", "all", "elemMatch", "size", "bitsAllClear",
    "bitsAllSet", "bitsAnyClear", "bitsAnySet", "slice", "meta", "comment", "rand",
    
    // Update Operators
    "currentDate", "inc", "min", "max", "mul", "rename", "set", "setOnInsert", "unset",
    "addToSet", "pop", "pull", "push", "pullAll", "each", "position", "sort", "slice",
    
    // Aggregation Operators
    "abs", "accumulator", "acos", "acosh", "add", "addToSet", "allElementsTrue", "and",
    "anyElementTrue", "arrayElemAt", "arrayToObject", "asin", "asinh", "atan", "atan2",
    "atanh", "avg", "binarySize", "bsonSize", "ceil", "cmp", "concat", "concatArrays",
    "cond", "convert", "cos", "cosh", "count", "dateAdd", "dateDiff", "dateFromParts",
    "dateFromString", "dateSubtract", "dateToParts", "dateToString", "dayOfMonth",
    "dayOfWeek", "dayOfYear", "degreesToRadians", "divide", "documentNumber", "exp",
    "filter", "first", "floor", "function", "getField", "hour", "ifNull", "indexOfArray",
    "indexOfBytes", "indexOfCP", "isArray", "isNumber", "isoDayOfWeek", "isoWeek",
    "isoWeekYear", "last", "let", "literal", "ln", "log", "log10", "map", "max", "mergeObjects",
    "meta", "min", "millisecond", "minute", "mod", "month", "multiply", "natural", "objectToArray",
    "pow", "push", "radiansToDegrees", "rand", "range", "reduce", "regexFind", "regexFindAll",
    "regexMatch", "replaceAll", "replaceOne", "reverseArray", "round", "second", "setDifference",
    "setEquals", "setIntersection", "setIsSubset", "setUnion", "sin", "sinh", "size", "slice",
    "split", "sqrt", "stdDevPop", "stdDevSamp", "strLenBytes", "strLenCP", "strcasecmp",
    "substr", "substring", "subtract", "sum", "switch", "tan", "tanh", "toBool", "toDate",
    "toDecimal", "toDouble", "toInt", "toLong", "toObjectId", "toString", "toLower", "toUpper",
    "trim", "trunc", "type", "week", "year", "zip",
    
    // Database Commands
    "find", "findOne", "insertOne", "insertMany", "updateOne", "updateMany", "deleteOne",
    "deleteMany", "aggregate", "count", "distinct", "bulkWrite", "listCollections",
    "createCollection", "createIndex", "dropIndex", "dropCollection", "dropDatabase",
    "explain", "collStats", "dbStats", "validate",
    
    // Shell-specific
    "db", "use", "show", "it", "help", "rs", "sh", "admin", "config", "local",
    "ObjectId", "ISODate", "NumberLong", "NumberDecimal", "NumberInt", "BinData",
    "UUID", "MD5", "BSON", "DBRef", "Timestamp"
  ]
  
  // MongoDB operators (mostly for querying and aggregation)
  private static let mongodbReservedOperators = [
    // Comparison operators
    ":", "==", "!=", ">", ">=", "<", "<=",
    
    // Logical operators
    "&&", "||", "!",
    
    // Arithmetic operators
    "+", "-", "*", "/", "%",
    
    // Array operators
    "[]", "[:]",
    
    // Object access
    ".", "[]",
    
    // MongoDB-specific
    "$", "$$"  // Used for variables and field references
  ]
}
