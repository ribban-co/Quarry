import Foundation

/// A custom logger that mimics the behavior of Swift's `print()` function.
///
/// Messages are always captured by the in-app `LogStore` (release builds
/// included, so users can inspect logs via the Logs window), but are only
/// printed to stdout in DEBUG builds.
///
/// - Parameters:
///   - items: Zero or more items to print.
///   - separator: A string to print between each item. The default is a single space (" ").
///   - terminator: The string to print after all items have been printed. The default is a newline ("\n").
public func debugLog(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    let output = items.map { "\($0)" }.joined(separator: separator)
    LogStore.record(output)
    #if DEBUG
    Swift.print(output, terminator: terminator)
    #endif
}
