//
//  CodeEditorRepresentable.swift
//
//
//  Created by Claude on 15/03/2026.
//
//  NSViewControllerRepresentable adapter for using CodeEditorViewController from SwiftUI.
//  This is the only file in the CodeEditorView subsystem that imports SwiftUI (aside from
//  CodeActions.swift which needs it for LanguageService `any View` types).

import Combine
import SwiftUI

import LanguageSupport


// MARK: -
// MARK: Environment keys

public struct CodeEditorTheme: EnvironmentKey {
  nonisolated(unsafe) public static var defaultValue: Theme = Theme.defaultLight
}

extension EnvironmentValues {
  public var codeEditorTheme: Theme {
    get { self[CodeEditorTheme.self] }
    set { self[CodeEditorTheme.self] = newValue }
  }
}


// MARK: -
// MARK: Representable

public struct CodeEditorRepresentable: NSViewControllerRepresentable {

  let language:            LanguageConfiguration
  let breakUndoCoalescing: PassthroughSubject<(), Never>?
  let autoFocus:           Bool

  @Binding private var text:     String
  @Binding private var position: CodeEditorTypes.Position
  @Binding private var messages: Set<TextLocated<Message>>

  @Environment(\.codeEditorTheme)                      private var theme
  @Environment(\.codeEditorLayoutConfiguration)        private var layoutConfiguration
  @Environment(\.codeEditorIndentationConfiguration)   private var indentationConfiguration
  @Environment(\.codeEditorSetActions)                 private var setActions
  @Environment(\.codeEditorSetInfo)                    private var setInfo

  public init(text:                Binding<String>,
              position:            Binding<CodeEditorTypes.Position>,
              messages:            Binding<Set<TextLocated<Message>>>,
              language:            LanguageConfiguration = .none,
              breakUndoCoalescing: PassthroughSubject<(), Never>? = nil,
              autoFocus:           Bool = false)
  {
    self._text               = text
    self._position           = position
    self._messages           = messages
    self.language            = language
    self.breakUndoCoalescing = breakUndoCoalescing
    self.autoFocus           = autoFocus
  }

  public func makeNSViewController(context: Context) -> CodeEditorViewController {
    let vc = CodeEditorViewController(
      language: language,
      theme: theme,
      layout: layoutConfiguration,
      indentation: indentationConfiguration
    )
    vc.delegate = context.coordinator

    context.coordinator.updateCallbacks(setActions: setActions, setInfo: setInfo)

    // Force loadView() so codeView is available
    _ = vc.view

    // Set initial state synchronously to avoid race with updateNSViewController
    vc.updatingProgrammatically = true
    vc.text = text
    vc.selections = position.selections
    vc.verticalScrollPosition = position.verticalScrollPosition
    vc.messages = messages
    vc.updatingProgrammatically = false

    // Break undo coalescing subscription
    context.coordinator.breakUndoCoalescingCancellable = breakUndoCoalescing?.sink { [weak vc] _ in
      vc?.breakUndoCoalescing()
    }

    vc.autoFocusOnAppear = autoFocus

    return vc
  }

  public func updateNSViewController(_ vc: CodeEditorViewController, context: Context) {
    vc.updatingProgrammatically = true
    defer { vc.updatingProgrammatically = false }

    context.coordinator.updateCallbacks(setActions: setActions, setInfo: setInfo)
    context.coordinator.updateBindings(text: $text, position: $position)

    if vc.codeView != nil {
      if text != vc.text {
        vc.breakUndoCoalescing()
        vc.text = text
        if language == vc.language {
          Task { @MainActor in
            vc.codeView.font = theme.font
          }
        }
      }

      if vc.messages != messages { vc.messages = messages }

      let newSelections = position.selections
      if newSelections != vc.selections {
        vc.selections = newSelections
        if let codeStorageDelegate = vc.codeView.optCodeStorage?.delegate as? CodeStorageDelegate {
          context.coordinator.info.selectionSummary = CodeEditorTypes.Info.SelectionSummary(
            selections: newSelections, with: codeStorageDelegate.lineMap
          )
        }
      }

      if layoutConfiguration.dynamicHeight {
        if let codeStorageDelegate = vc.codeView.optCodeStorage?.delegate as? CodeStorageDelegate {
          let lineCount = codeStorageDelegate.lineMap.lines.count
          let lineHeight = vc.codeView.font?.lineHeight ?? 14
          let calculatedHeight = CGFloat(lineCount) * lineHeight
          let finalHeight = max(calculatedHeight, 100)

          if let heightConstraint = vc.view.constraints.first(where: {
            $0.firstAttribute == .height && $0.secondItem == nil
          }) {
            heightConstraint.constant = finalHeight
          } else {
            vc.view.translatesAutoresizingMaskIntoConstraints = false
            let heightConstraint = NSLayoutConstraint(
              item: vc.view, attribute: .height,
              relatedBy: .equal, toItem: nil, attribute: .notAnAttribute,
              multiplier: 1, constant: finalHeight
            )
            heightConstraint.isActive = true
          }
        }
      }

      if abs(position.verticalScrollPosition - vc.verticalScrollPosition) > 0.0001 {
        vc.verticalScrollPosition = position.verticalScrollPosition
      }

      if theme.id != vc.theme.id { vc.theme = theme }
      if layoutConfiguration != vc.layout { vc.layout = layoutConfiguration }
      if indentationConfiguration != vc.indentation { vc.indentation = indentationConfiguration }

      if language != vc.language {
        let languageServiceChanged = language.languageService !== vc.language.languageService
        vc.language = language
        context.coordinator.info.language = language.name

        if languageServiceChanged {
          if let extraActions = vc.codeView.optLanguageService?.extraActions.value {
            context.coordinator.actions.language.extraActions = extraActions
          }
          context.coordinator.extraActionsCancellable = language.languageService?.extraActions
            .sink { [coordinator = context.coordinator] actions in
              Task { @MainActor in
                coordinator.actions.language.extraActions = actions
              }
            }
        }
      }
    }
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator(text: $text, position: $position, setActions: setActions, setInfo: setInfo)
  }

  // MARK: Coordinator

  public final class Coordinator: CodeEditorViewControllerDelegate {
    @Binding var text: String
    @Binding var position: CodeEditorTypes.Position

    var setActions: CodeEditorTypes.SetActions
    var setInfo: CodeEditorTypes.SetInfo

    var actions: CodeEditorTypes.Actions = CodeEditorTypes.Actions() {
      didSet { setActions(actions) }
    }

    var info: CodeEditorTypes.Info = CodeEditorTypes.Info() {
      didSet { setInfo(info) }
    }

    var breakUndoCoalescingCancellable: Cancellable?
    var extraActionsCancellable: Cancellable?

    private var updatingView = false

    init(text: Binding<String>, position: Binding<CodeEditorTypes.Position>,
         setActions: CodeEditorTypes.SetActions, setInfo: CodeEditorTypes.SetInfo)
    {
      self._text      = text
      self._position  = position
      self.setActions = setActions
      self.setInfo    = setInfo
    }

    func updateBindings(text: Binding<String>, position: Binding<CodeEditorTypes.Position>) {
      self._text     = text
      self._position = position
    }

    func updateCallbacks(setActions: CodeEditorTypes.SetActions, setInfo: CodeEditorTypes.SetInfo) {
      self.setActions = setActions
      self.setInfo    = setInfo
    }

    // MARK: CodeEditorViewControllerDelegate

    @MainActor
    public func codeEditorDidChangeText(_ controller: CodeEditorViewController, text: String) {
      guard !updatingView else { return }
      if self.text != text { self.text = text }
    }

    @MainActor
    public func codeEditorDidChangeSelection(_ controller: CodeEditorViewController, selections: [NSRange]) {
      guard !updatingView else { return }
      if self.position.selections != selections {
        self.position.selections = selections
      }
    }

    @MainActor
    public func codeEditorDidScroll(_ controller: CodeEditorViewController, verticalPosition: CGFloat) {
      guard !updatingView else { return }
      if abs(position.verticalScrollPosition - verticalPosition) > 0.0001 {
        position.verticalScrollPosition = verticalPosition
      }
    }

    @MainActor
    public func codeEditorDidUpdateInfo(_ controller: CodeEditorViewController, info: CodeEditorTypes.Info) {
      self.info = info
    }

    @MainActor
    public func codeEditorDidUpdateActions(_ controller: CodeEditorViewController, actions: CodeEditorTypes.Actions) {
      self.actions = actions
    }
  }
}

// MARK: -
// MARK: Backward compatibility

// MARK: -
// MARK: Nested type aliases for backward compatibility

extension CodeEditorRepresentable {
  public typealias Position = CodeEditorTypes.Position
  public typealias LayoutConfiguration = CodeEditorTypes.LayoutConfiguration
  public typealias IndentationConfiguration = CodeEditorTypes.IndentationConfiguration
  public typealias Actions = CodeEditorTypes.Actions
  public typealias SetActions = CodeEditorTypes.SetActions
  public typealias Info = CodeEditorTypes.Info
  public typealias SetInfo = CodeEditorTypes.SetInfo
}


// MARK: -
// MARK: Environment values

extension EnvironmentValues {
  @Entry public var codeEditorLayoutConfiguration: CodeEditorTypes.LayoutConfiguration = .standard
}

extension EnvironmentValues {
  @Entry public var codeEditorIndentationConfiguration: CodeEditorTypes.IndentationConfiguration = .standard
}

extension EnvironmentValues {
  @Entry public var codeEditorSetActions: CodeEditorTypes.SetActions = .ignore
}

extension EnvironmentValues {
  @Entry public var codeEditorSetInfo: CodeEditorTypes.SetInfo = .ignore
}


// MARK: -
// MARK: Backward compatibility

/// Typealias for backward compatibility — all existing SwiftUI call sites use `CodeEditor(...)`.
public typealias CodeEditor = CodeEditorRepresentable
