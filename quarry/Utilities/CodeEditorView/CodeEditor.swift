//
//  CodeEditor.swift
//
//  Created by Fauzaan on 23/08/2020.
//
//  Public value types for the code editor (Position, LayoutConfiguration, IndentationConfiguration, etc.).
//  The actual editor view controller is in CodeEditorViewController.swift.
//  The SwiftUI adapter is in CodeEditorRepresentable.swift (which provides `typealias CodeEditor`).

import Foundation

import LanguageSupport


// MARK: -
// MARK: Namespace for value types

/// Namespace for code editor value types. The SwiftUI view `CodeEditor` is a typealias defined
/// in CodeEditorRepresentable.swift.
///
public enum CodeEditorTypes {

  /// Specification of a text editing position; i.e., text selection and scroll position.
  ///
  public struct Position: Equatable {

    /// Specification of a list of selection ranges.
    ///
    public var selections: [NSRange]

    /// The editor vertical scroll position.
    ///
    public var verticalScrollPosition: CGFloat

    public init(selections: [NSRange], verticalScrollPosition: CGFloat) {
      self.selections             = selections
      self.verticalScrollPosition = verticalScrollPosition
    }

    public init() {
      self.init(selections: [.zero], verticalScrollPosition: 0)
    }
  }

  // MARK: Layout configuration

  /// Specification of the editor layout.
  ///
  public struct LayoutConfiguration: Equatable, RawRepresentable {

    public var wrapText: Bool
    public var dynamicHeight: Bool

    public init(wrapText: Bool, dynamicHeight: Bool = false) {
      self.wrapText      = wrapText
      self.dynamicHeight = dynamicHeight
    }

    nonisolated(unsafe) public static let standard = LayoutConfiguration(wrapText: true)

    public var rawValue: String { "\(wrapText ? "t" : "f")" }

    public init?(rawValue: String) {
      guard rawValue.count >= 1
      else { return nil }

      self.wrapText = rawValue[rawValue.startIndex] == "t"

      if rawValue.count > 1 {
        self.dynamicHeight = rawValue[rawValue.index(after: rawValue.startIndex)] == "t"
      } else {
        self.dynamicHeight = false
      }
    }
  }

  // MARK: Indentation configuration

  public struct IndentationConfiguration: Equatable, RawRepresentable {

    public enum Preference: Equatable {
      case preferSpaces
      case preferTabs

      init (tag: String) {
        switch tag {
        case "s": self = .preferSpaces
        case "t": self = .preferTabs
        default:  self = .preferSpaces
        }
      }

      var tag: String {
        switch self {
        case .preferSpaces: return "s"
        case .preferTabs:   return "t"
        }
      }
    }

    public enum TabKey: Equatable {
      case identsInWhitespace
      case indentsAlways
      case insertsTab

      init(tag: String) {
        switch tag {
        case "w": self = .identsInWhitespace
        case "a": self = .indentsAlways
        case "t": self = .insertsTab
        default:  self = .identsInWhitespace
        }
      }

      var tag: String {
        switch self {
        case .identsInWhitespace: return "w"
        case .indentsAlways:      return "a"
        case .insertsTab:         return "t"
        }
      }
    }

    public var preference: Preference
    public var tabWidth: Int
    public var indentWidth: Int
    public var tabKey: TabKey
    public var indentOnReturn: Bool

    public init (preference: Preference, tabWidth: Int, indentWidth: Int, tabKey: TabKey, indentOnReturn: Bool) {
      self.preference     = preference
      self.tabWidth       = tabWidth
      self.indentWidth    = indentWidth
      self.tabKey         = tabKey
      self.indentOnReturn = indentOnReturn
    }

    nonisolated(unsafe) public static let standard = IndentationConfiguration(preference: .preferSpaces,
                                                          tabWidth: 2,
                                                          indentWidth: 2,
                                                          tabKey: .identsInWhitespace,
                                                          indentOnReturn: true)

    public var rawValue: String {
      "\(preference.tag),\(tabWidth),\(indentWidth),\(tabKey.tag),\(indentOnReturn ? "t" : "f")"
    }

    public init?(rawValue: String) {
      let pieces = rawValue.split(separator: ",")
      guard pieces.count == 5
      else { return nil }

      self.preference     = Preference(tag: String(pieces[0]))
      self.tabWidth       = Int(pieces[1]) ?? 2
      self.indentWidth    = Int(pieces[2]) ?? 2
      self.tabKey         = TabKey(tag: String(pieces[3]))
      self.indentOnReturn = pieces[4] == "t"
    }
  }

  // MARK: Code actions

  public struct Actions {

    public struct Language {
      public let name: String
      public var extraActions: [ExtraAction] = []
    }

    public var language: Language = Language(name: "Text")
    public var info: (() -> Void)?
    public var completions: (() -> Void)?
  }

  public struct SetActions {
    let setActions: (Actions) -> Void

    nonisolated(unsafe) public static let ignore: SetActions = .init({ _ in })

    public init(_ setActions: @escaping (Actions) -> Void) {
      self.setActions = setActions
    }

    func callAsFunction(_ actions: Actions) {
      setActions(actions)
    }
  }

  // MARK: Editor info

  public struct Info {

    public enum SelectionSummary {
      case insertionPoint(Int, Int)
      case characters(Int)
      case lines(Int)
      case ranges(Int)

      init(selections: [NSRange], with lineMap: LineMap<LineInfo>) {
        if let range = selections.first,
           selections.count == 1,
           let line    = lineMap.lineOf(index: range.location),
           let oneLine = lineMap.lookup(line: line)
        {
          if range.length == 0 {
            self = .insertionPoint(line + 1, range.location - oneLine.range.location + 1)
          } else {
            let lastLine = lineMap.lineOf(index: range.upperBound) ?? lineMap.lines.count
            if line == lastLine {
              self = .characters(range.length)
            } else {
              self = .lines(lastLine - line + 1)
            }
          }
        } else if selections.count > 1 {
          self = .ranges(selections.count)
        } else {
          self = .insertionPoint(1, 1)
        }
      }
    }

    public var language: String
    public var selectionSummary: SelectionSummary

    public init(language: String = "Text", selectionSummary: SelectionSummary = .insertionPoint(1, 1)) {
      self.language         = language
      self.selectionSummary = selectionSummary
    }
  }

  public struct SetInfo {
    let setInfo: (Info) -> Void

    nonisolated(unsafe) public static let ignore: SetInfo = .init({ _ in })

    public init(_ setInfo: @escaping (Info) -> Void) {
      self.setInfo = setInfo
    }

    func callAsFunction(_ info: Info) {
      setInfo(info)
    }
  }
}


// MARK: -
// MARK: Position serialization

extension CodeEditorTypes.Position: RawRepresentable, Codable {

  public init?(rawValue: String) {

    func parseNSRange(lexeme: String) -> NSRange? {
      let components = lexeme.components(separatedBy: ":")
      guard components.count == 2,
            let location = Int(components[0]),
            let length   = Int(components[1])
      else { return nil }
      return NSRange(location: location, length: length)
    }

    let components = rawValue.components(separatedBy: "|")
    if components.count == 2 {

      selections             = components[0].components(separatedBy: ";").compactMap{ parseNSRange(lexeme: $0) }
      verticalScrollPosition = CGFloat(Double(components[1]) ?? 0)

    } else { self = CodeEditorTypes.Position() }
  }

  public var rawValue: String {
    let selectionsString             = selections.map{ "\($0.location):\($0.length)" }.joined(separator: ";"),
        verticalScrollPositionString = String(describing: verticalScrollPosition)
    return selectionsString + "|" + verticalScrollPositionString
  }
}


// Environment values are defined in CodeEditorRepresentable.swift (SwiftUI-only file).
