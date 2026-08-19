import Foundation
import NIOCore

/// An empty protocol for encapsulating all errors that BSON package can throw.
public protocol BSONErrorProtocol: LocalizedError {}

/// Namespace containing all the error types introduced by this BSON library and their dependent types.
public enum BSONError {
    /// An error thrown when the user passes in invalid arguments to a BSON method.
    public struct InvalidArgumentError: BSONErrorProtocol {
        internal let message: String

        public var errorDescription: String? { self.message }
    }

    /// An error thrown when the BSON library encounters a internal error not caused by the user.
    /// This is usually indicative of a bug in the BSON library or system related failure.
    public struct InternalError: BSONErrorProtocol {
        internal let message: String

        public var errorDescription: String? { self.message }
    }

    /// An error thrown when the BSON library is incorrectly used.
    public struct LogicError: BSONErrorProtocol {
        internal let message: String

        public var errorDescription: String? { self.message }
    }
    
    public struct invalidDecimal128String: BSONErrorProtocol {
        internal let message: String

        public var errorDescription: String? { self.message }
    }
}

