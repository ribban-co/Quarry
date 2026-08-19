//
//  CodeEditorViewController.swift
//
//
//  Created by Claude on 15/03/2026.
//
//  Pure AppKit view controller for the code editor. Primary public API for embedding the editor
//  in AppKit view hierarchies. For SwiftUI usage, use CodeEditorRepresentable.

import AppKit
import Combine

import LanguageSupport


// MARK: -
// MARK: Delegate protocol

@MainActor
public protocol CodeEditorViewControllerDelegate: AnyObject {
  func codeEditorDidChangeText(_ controller: CodeEditorViewController, text: String)
  func codeEditorDidChangeSelection(_ controller: CodeEditorViewController, selections: [NSRange])
  func codeEditorDidScroll(_ controller: CodeEditorViewController, verticalPosition: CGFloat)
  func codeEditorDidUpdateInfo(_ controller: CodeEditorViewController, info: CodeEditorTypes.Info)
  func codeEditorDidUpdateActions(_ controller: CodeEditorViewController, actions: CodeEditorTypes.Actions)
}

extension CodeEditorViewControllerDelegate {
  public func codeEditorDidChangeText(_ controller: CodeEditorViewController, text: String) {}
  public func codeEditorDidChangeSelection(_ controller: CodeEditorViewController, selections: [NSRange]) {}
  public func codeEditorDidScroll(_ controller: CodeEditorViewController, verticalPosition: CGFloat) {}
  public func codeEditorDidUpdateInfo(_ controller: CodeEditorViewController, info: CodeEditorTypes.Info) {}
  public func codeEditorDidUpdateActions(_ controller: CodeEditorViewController, actions: CodeEditorTypes.Actions) {}
}


// MARK: -
// MARK: View Controller

@MainActor
public final class CodeEditorViewController: NSViewController {

  weak var delegate: (any CodeEditorViewControllerDelegate)?

  // MARK: Configuration

  private let initialLanguage: LanguageConfiguration
  private let initialTheme: Theme
  private let initialLayout: CodeEditorTypes.LayoutConfiguration
  private let initialIndentation: CodeEditorTypes.IndentationConfiguration

  // MARK: Internal views

  private(set) var codeView: CodeView!
  private var scrollView: NSScrollView!
  nonisolated(unsafe) private var boundsChangedObserver: NSObjectProtocol?
  private var extraActionsCancellable: Cancellable?

  /// Prevents delegate callbacks during programmatic updates to avoid feedback loops.
  var updatingProgrammatically = false

  /// When true, the code view becomes first responder on first `viewDidAppear` (one-shot).
  public var autoFocusOnAppear = false
  private var didAutoFocus = false
  private var autoFocusTask: Task<Void, Never>?

  // MARK: Public properties

  var text: String {
    get { codeView.string }
    set {
      guard newValue != codeView.string else { return }
      updatingProgrammatically = true
      defer { updatingProgrammatically = false }

      if let codeStorageDelegate = codeView.optCodeStorage?.delegate as? CodeStorageDelegate {
        codeStorageDelegate.skipNextChangeNotificationToLanguageService = true
      }
      codeView.string = newValue
    }
  }

  var selections: [NSRange] {
    get { codeView.selectedRanges.map { $0.rangeValue } }
    set {
      let nsValues = newValue.map { NSValue(range: $0) }
      guard nsValues != codeView.selectedRanges else { return }
      updatingProgrammatically = true
      defer { updatingProgrammatically = false }
      codeView.selectedRanges = nsValues
    }
  }

  var verticalScrollPosition: CGFloat {
    get { scrollView.verticalScrollPosition }
    set {
      guard abs(newValue - scrollView.verticalScrollPosition) > 0.0001 else { return }
      updatingProgrammatically = true
      defer { updatingProgrammatically = false }
      scrollView.verticalScrollPosition = newValue
    }
  }

  var theme: Theme {
    get { codeView.theme }
    set {
      guard newValue.id != codeView.theme.id else { return }
      codeView.theme = newValue
    }
  }

  var language: LanguageConfiguration {
    get { codeView.language }
    set {
      guard newValue != codeView.language else { return }

      let languageServiceChanged = newValue.languageService !== codeView.language.languageService
      if languageServiceChanged {
        if let codeStorageDelegate = codeView.optCodeStorage?.delegate as? CodeStorageDelegate {
          codeStorageDelegate.skipNextChangeNotificationToLanguageService = true
        }
      }

      codeView.language = newValue

      if languageServiceChanged {
        if let extraActions = codeView.optLanguageService?.extraActions.value {
          currentActions.language.extraActions = extraActions
        }
        extraActionsCancellable = newValue.languageService?.extraActions
          .sink { [weak self] actions in
            Task { @MainActor [weak self] in
              self?.currentActions.language.extraActions = actions
            }
          }
      }
    }
  }

  var layout: CodeEditorTypes.LayoutConfiguration {
    get { codeView.viewLayout }
    set {
      guard newValue != codeView.viewLayout else { return }
      codeView.viewLayout = newValue
    }
  }

  var indentation: CodeEditorTypes.IndentationConfiguration {
    get { codeView.indentation }
    set {
      guard newValue != codeView.indentation else { return }
      codeView.indentation = newValue
    }
  }

  var messages: Set<TextLocated<Message>> = [] {
    didSet {
      guard messages != oldValue else { return }
      codeView.update(messages: messages)
    }
  }

  private var currentActions: CodeEditorTypes.Actions = CodeEditorTypes.Actions() {
    didSet { delegate?.codeEditorDidUpdateActions(self, actions: currentActions) }
  }

  private var currentInfo: CodeEditorTypes.Info = CodeEditorTypes.Info() {
    didSet { delegate?.codeEditorDidUpdateInfo(self, info: currentInfo) }
  }

  func breakUndoCoalescing() {
    codeView.breakUndoCoalescing()
  }

  // MARK: Initializer

  init(language: LanguageConfiguration = .none,
       theme: Theme = .defaultDark,
       layout: CodeEditorTypes.LayoutConfiguration = .standard,
       indentation: CodeEditorTypes.IndentationConfiguration = .standard)
  {
    self.initialLanguage = language
    self.initialTheme = theme
    self.initialLayout = layout
    self.initialIndentation = indentation
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: Lifecycle

  override public func loadView() {

    func setText(_ text: String) {
      guard !updatingProgrammatically else { return }
      delegate?.codeEditorDidChangeText(self, text: text)
    }

    // Create scroll view
    scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
    scrollView.borderType          = .noBorder
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalRuler  = false
    scrollView.autoresizingMask    = [.width, .height]
    scrollView.drawsBackground     = false
    scrollView.contentView.drawsBackground = false
    scrollView.contentInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

    // Create code view
    codeView = CodeView(frame: CGRect(x: 0, y: 0, width: 100, height: 40),
                        with: initialLanguage,
                        viewLayout: initialLayout,
                        indentation: initialIndentation,
                        theme: initialTheme,
                        setText: setText(_:),
                        setMessages: { [weak self] messages in self?.messages = messages })
    codeView.isVerticallyResizable   = true
    codeView.isHorizontallyResizable = false
    codeView.autoresizingMask        = .width

    scrollView.documentView = codeView

    currentInfo.language = initialLanguage.name

    if let codeStorageDelegate = codeView.optCodeStorage?.delegate as? CodeStorageDelegate {
      codeStorageDelegate.skipNextChangeNotificationToLanguageService = true
    }

    // Wire delegate callbacks
    if let codeViewDelegate = codeView.delegate as? CodeViewDelegate {
      let existingSelectionDidChange = codeViewDelegate.selectionDidChange
      codeViewDelegate.selectionDidChange = { [weak self, existingSelectionDidChange] textView in
        existingSelectionDidChange?(textView)
        self?.handleSelectionDidChange(textView)
      }
    }

    // Set up actions
    currentActions = CodeEditorTypes.Actions(
      language: CodeEditorTypes.Actions.Language(name: initialLanguage.name),
      info: { [weak codeView] in codeView?.infoAction() },
      completions: { [weak codeView] in codeView?.completionAction() }
    )

    if let extraActions = codeView.optLanguageService?.extraActions.value {
      currentActions.language.extraActions = extraActions
    }
    extraActionsCancellable = initialLanguage.languageService?.extraActions
      .sink { [weak self] actions in
        Task { @MainActor [weak self] in
          self?.currentActions.language.extraActions = actions
        }
      }

    self.view = scrollView
  }

  override public func viewDidAppear() {
    super.viewDidAppear()

    boundsChangedObserver = NotificationCenter.default.addObserver(
      forName: NSView.boundsDidChangeNotification,
      object: scrollView.contentView,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self, !self.updatingProgrammatically else { return }
        self.delegate?.codeEditorDidScroll(self, verticalPosition: self.scrollView.verticalScrollPosition)
      }
    }

    if autoFocusOnAppear && !didAutoFocus {
      didAutoFocus = true
      autoFocusTask = Task { @MainActor [weak self] in
        for _ in 0..<30 {
          if Task.isCancelled { return }
          guard let self else { return }
          if let window = self.view.window, let codeView = self.codeView {
            if window.makeFirstResponder(codeView) { return }
          }
          try? await Task.sleep(for: .milliseconds(16))
        }
      }
    }
  }

  override public func viewWillDisappear() {
    super.viewWillDisappear()
    autoFocusTask?.cancel()
    autoFocusTask = nil
    if let observer = boundsChangedObserver {
      NotificationCenter.default.removeObserver(observer)
      boundsChangedObserver = nil
    }
  }

  deinit {
    if let observer = boundsChangedObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  // MARK: Internal handlers

  private func handleSelectionDidChange(_ textView: NSTextView) {
    guard !updatingProgrammatically else { return }

    let newSelections = textView.selectedRanges.map { $0.rangeValue }
    delegate?.codeEditorDidChangeSelection(self, selections: newSelections)

    if let codeStorageDelegate = codeView.optCodeStorage?.delegate as? CodeStorageDelegate {
      currentInfo.selectionSummary = CodeEditorTypes.Info.SelectionSummary(
        selections: newSelections, with: codeStorageDelegate.lineMap
      )
    }
  }
}
