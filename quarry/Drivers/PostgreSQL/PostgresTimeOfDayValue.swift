//
//  PostgresTimeOfDayValue.swift
//  Quarry
//
//  Created by Fauzaan on 7/5/25.
//

import Foundation
import PostgresNIO

/// Represents a count of microseconds since the start of an arbitrary unspecified day, between 0 (exactly midnight) and
/// `86_399_999_999` (`23:59:59.999999`), encodable and decodable as the PostgreSQL type `time`.
struct PostgresTimeOfDayValue:
    Codable,
    PostgresNonThrowingEncodable,
    PostgresDecodable,
    PostgresArrayDecodable,
    PostgresArrayEncodable,
    LosslessStringConvertible,
    Hashable,
    Sendable
{
    /// Swift identifiers may use the majority of Unicode codepoints, they don't have to be ASCII.
    /// You can even use emoji in variable names, though the result tends to be unreadable.
    private static let µsPerSec: Int64 = 1_000_000

    private static func parse(string: String) -> Int64? {
        /// This regex matches a string with the datetime formats `H:mm:ss` or `H:mm:ss.SSSSSS`.
        ///
        /// Note that the `#/ /#` delimiters imply the `(?x)` "extended syntax" option which causes whitespace to
        /// be ignored, allows embedded newlines, and enables #-prefixed comments.
        ///
        /// Using `wholeMatch(of:)` means that the regex must consume the entire string to be considered matching.
        guard let match = string.wholeMatch(of: #/
                  (?nD)                       # n: Unnamed groups are non-capturing, D: \d matches only ASCII
                  (?<hour>(0?\d)|1\d|2[0-3])  # Match 0-9 or 00-23
                  :(?<min>[0-5]\d)            # Match ':' followed by 00-59
                  :(?<sec>[0-5]\d)            # Match ':' followed by 00-59
                  (\.(?<us>\d{1,6}))?         # Optionally match . followed by between 1 and 6 digits
              /#),
              let hour = Int64(match.hour),
              let minute = Int64(match.min),
              let second = Int64(match.sec),
              let us = Int64(match.us ?? "0")
        else {
            return nil
        }

        return ((hour * 3600) + (minute * 60) + second) * Self.µsPerSec + us
    }

    // See `PostgresEncodable.psqlType`.
    static var psqlType: PostgresDataType { .time }
    
    // See `PostgresEncodable.psqlFormat`.
    static var psqlFormat: PostgresFormat { .binary }

    // See `PostgresArrayEncodable.psqlArrayType`.
    public static var psqlArrayType: PostgresDataType { .timeArray }

    public let microseconds: Int64

    /// Memberwise initializer
    public init(microseconds: Int64) {
        self.microseconds = microseconds
    }

    // See `LosslessStringConvertible.init?(_:)`.
    public init?(_ value: String) {
        guard let us = Self.parse(string: value) else { return nil }
        self.init(microseconds: us)
    }

    // See `Decodable.init(from:)`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let us = Self.parse(string: try container.decode(String.self)) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unable to decode time string")
        }
        self.init(microseconds: us)
    }

    // See `PostgresDecodable.init(from:type:format:context:)`.
    public init(
        from buffer: inout ByteBuffer, type: PostgresDataType, format: PostgresFormat,
        context: PostgresDecodingContext<some PostgresJSONDecoder>
    ) throws {
        switch type {
        case .time:
            guard let inValue: Int64 = buffer.readInteger() else { throw PostgresDecodingError.Code.missingData }
            self.init(microseconds: inValue)
        default:
            throw PostgresDecodingError.Code.typeMismatch
        }
    }

    // See `Encodable.encode(to:)`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.description)
    }

    // See `PostgresNonThrowingEncodable.encode(into:context:)`.
    public func encode(into byteBuffer: inout ByteBuffer, context: PostgresEncodingContext<some PostgresJSONEncoder>) {
        byteBuffer.writeInteger(self.microseconds)
    }

    // See `CustomStringConvertible.description`.
    public var description: String {
        let hours   = "0\(self.microseconds / Self.µsPerSec / 3600)".suffix(2),
            minutes = "0\(self.microseconds / Self.µsPerSec % 3600 / 60)".suffix(2),
            seconds = "0\(self.microseconds / Self.µsPerSec % 3600 % 60)".suffix(2),
            us      = "00000\(self.microseconds % Self.µsPerSec)".suffix(6)

        return "\(hours):\(minutes):\(seconds)\(us != "000000" ? ".\(us)" : "")"
    }
}
