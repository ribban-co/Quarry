//
//  CodeView.swift
//  
//
//  Created by Fauzaan on 05/05/2021.
//
//  This file contains both the macOS and iOS versions of the subclass for `NSTextView` and `UITextView`, respectively,
//  which forms the heart of the code editor.

import os
import Combine
import AppKit

import Rearrange

@preconcurrency import LanguageSupport


private let logger = Logger(subsystem: "org.justtesting.CodeEditorView", category: "CodeView")


// MARK: -
// MARK: Message info

/// Information required to layout message views.
///
/// NB: This information is computed incrementally. We get the `lineFragementRect` from the text container during the
///     line fragment computations. This indicates that the message layout may have to change (if it was already
///     computed), but at this point, we cannot determine the new geometry yet; hence, `geometry` will be `nil`.
///     The `geometry` will be determined after text layout is complete. We get the `characterIndex` also from the text
///     container during line fragment computations.
///
struct MessageInfo {
  let view:                    MessageContainerView
  let backgroundView:          CodeBackgroundHighlightView
  var characterIndex:          Int                    // The starting character index for the line hosting the message
  var telescope:               Int?                   // The number of telescope lines (i.e., beyond starting line)
  var characterIndexTelescope: Int?                   // The last index of the last line of the telescope lines (if any)
  var lineFragementRect:       CGRect                 // The *full* line fragement rectangle (incl. message)
  var geometry:                MessageGeometry?
  var colour:                  OSColor                // The category colour of the most severe category
  var invalidated:             Bool                   // Greyed out and doesn't display a telescope

  var topAnchorConstraint:   NSLayoutConstraint?
  var rightAnchorConstraint: NSLayoutConstraint?
}

/// Dictionary of message views.
///
typealias MessageViews = [LineInfo.MessageBundle.ID: MessageInfo]


// MARK: -
// MARK: AppKit version

/// `NSTextView` with a gutter
///  
final class CodeView: NSTextView {

  // Delegates
  fileprivate let codeViewDelegate =                 CodeViewDelegate()
  fileprivate var codeStorageDelegate:               CodeStorageDelegate
  fileprivate let minimapCodeViewDelegate =          CodeViewDelegate()

  // Subviews
  var gutterView:               GutterView?
  var currentLineHighlightView: CodeBackgroundHighlightView?
  var minimapView:              NSTextView?
  var minimapGutterView:        GutterView?
  var documentVisibleBox:       NSBox?
  var minimapDividerView:       NSBox?

  /// Contains the line on which the insertion point was located, the last time the selection range got set (if the
  /// selection was an insertion point at all; i.e., it's length was 0).
  ///
  var oldLastLineOfInsertionPoint: Int? = 1

  /// The current highlighting theme
  ///
  @Invalidating(.layout, .display)
  var theme: Theme = .defaultLight {
    didSet {
      font                                 = theme.font
      backgroundColor                      = theme.backgroundColour
      insertionPointColor                  = theme.cursorColour
      selectedTextAttributes               = [.backgroundColor: theme.selectionColour]
      (textStorage as? CodeStorage)?.theme = theme
      gutterView?.theme                    = theme
      currentLineHighlightView?.color      = theme.currentLineColour
      minimapView?.backgroundColor         = theme.backgroundColour
      minimapGutterView?.theme             = theme
      documentVisibleBox?.fillColor        = theme.textColour.withAlphaComponent(0.1)
    }
  }

  /// The current language configuration.
  ///
  /// We keep track of it here to enable us to spot changes during processing of view updates.
  ///
  @Invalidating(.layout, .display)
  var language: LanguageConfiguration = .none {
    didSet {
      guard let codeStorage = optCodeStorage else { return }

      if oldValue != language {

        let lang = language
        let delegate = codeStorageDelegate
        let storage = codeStorage
        Task { @MainActor in
          do {

            try await delegate.change(language: lang, for: storage)
            try await startLanguageService()

          } catch let error {
            logger.trace("Failed to change language from \(oldValue.name) to \(self.language.name): \(error.localizedDescription)")
          }

          // FIXME: This is an awful kludge to get the code view to redraw with the new highlighting. Emitting
          //        `codeStorage.edited(:range:changeInLength)` doesn't seem to work reliably.
          Task { @MainActor in
            font = theme.font
          }
        }

      }
    }
  }

  /// The current view layout.
  ///
  @Invalidating(.layout)
  var viewLayout: CodeEditorTypes.LayoutConfiguration = .standard
  
  /// The current indentation configuration.
  ///
  var indentation: CodeEditorTypes.IndentationConfiguration = .standard

  /// Hook to propagate message sets upwards in the view hierarchy.
  ///
  let setMessages: (Set<TextLocated<Message>>) -> Void

  /// This is the last reported set of `messages`. New message sets can come from the context or from a language server.
  ///
  var lastMessages: Set<TextLocated<Message>> = Set()

  /// Keeps track of the set of message views.
  ///
  var messageViews: MessageViews = [:]

  /// For the consumption of the diagnostics stream.
  ///
  private var diagnosticsCancellable: Cancellable?

  /// For the consumption of the events stream from the language service.
  ///
  private var eventsCancellable: Cancellable?

  /// Holds the info popover if there is one.
  ///
  var infoPopover: InfoPopover?

  /// Holds the completion panel. It is always available, but open, closed, and positioned on demand.
  ///
  var completionPanel: CompletionPanel = CompletionPanel()

  /// Cancellable task used to compute completions.
  ///
  var completionTask: Task<(), Error>?

  /// Observation tokens that need to be retained.
  ///
  var observations: [NSObject] = []

  /// Designated initialiser for code views with a gutter.
  ///
  init(frame: CGRect, 
       with language: LanguageConfiguration,
       viewLayout: CodeEditorTypes.LayoutConfiguration,
       indentation: CodeEditorTypes.IndentationConfiguration,
       theme: Theme,
       setText: @escaping (String) -> Void,
       setMessages: @escaping (Set<TextLocated<Message>>) -> Void)
  {

    self.theme       = theme
    self.language    = language
    self.viewLayout  = viewLayout
    self.indentation = indentation
    self.setMessages = setMessages

    // Use custom components that are gutter-aware and support code-specific editing actions and highlighting.
    let textLayoutManager  = NSTextLayoutManager(),
        codeContainer      = CodeContainer(size: frame.size),
        codeStorage        = CodeStorage(theme: theme),
        textContentStorage = CodeContentStorage()
    textLayoutManager.textContainer = codeContainer
    textContentStorage.addTextLayoutManager(textLayoutManager)
    textContentStorage.primaryTextLayoutManager = textLayoutManager
    textContentStorage.textStorage              = codeStorage

    codeStorageDelegate = CodeStorageDelegate(with: language, setText: setText)

    super.init(frame: frame, textContainer: codeContainer)

    MainActor.assumeIsolated {
      textLayoutManager.setSafeRenderingAttributesValidator(with: codeViewDelegate) { (textLayoutManager, layoutFragment) in
        guard let textContentStorage = textLayoutManager.textContentManager as? NSTextContentStorage else { return }

        codeStorage.setHighlightingAttributes(for: textContentStorage.range(for: layoutFragment.rangeInElement),
                                              in: textLayoutManager)
      }.flatMap { observations.append($0) }
    }

    // We can't do this — see [Note NSTextViewportLayoutControllerDelegate].
    //
    //    if let systemDelegate = codeLayoutManager.textViewportLayoutController.delegate {
    //      let codeViewportLayoutControllerDelegate = CodeViewportLayoutControllerDelegate(systemDelegate: systemDelegate,
    //                                                                                      codeView: self)
    //      self.codeViewportLayoutControllerDelegate = codeViewportLayoutControllerDelegate
    //      codeLayoutManager.textViewportLayoutController.delegate = codeViewportLayoutControllerDelegate
    //    }

    // Set basic display and input properties
    font                                 = theme.font
    backgroundColor                      = theme.backgroundColour
    insertionPointColor                  = theme.cursorColour
    selectedTextAttributes               = [.backgroundColor: theme.selectionColour]
    isRichText                           = false
    isAutomaticQuoteSubstitutionEnabled  = false
    isAutomaticLinkDetectionEnabled      = false
    smartInsertDeleteEnabled             = false
    isContinuousSpellCheckingEnabled     = false
    isGrammarCheckingEnabled             = false
    isAutomaticDashSubstitutionEnabled   = false
    isAutomaticDataDetectionEnabled      = false
    isAutomaticSpellingCorrectionEnabled = false
    isAutomaticTextReplacementEnabled    = false
    usesFontPanel                        = false

    // Line wrapping
    isHorizontallyResizable             = false
    isVerticallyResizable               = true
    textContainerInset                  = .zero
    textContainer?.widthTracksTextView  = false   // we need to be able to control the size (see `tile()`)
    textContainer?.heightTracksTextView = false
    textContainer?.lineBreakMode        = .byWordWrapping

    // FIXME: properties that ought to be configurable
    usesFindBar                   = true
    isIncrementalSearchingEnabled = true

    // Enable undo support
    allowsUndo = true

    // Add the view delegate
    delegate = codeViewDelegate

    // Add a text storage delegate that maintains a line map
    codeStorage.delegate = codeStorageDelegate

    // Create the main gutter view
    let gutterView = GutterView(frame: CGRect.zero,
                                textView: self,
                                codeStorage: codeStorage,
                                theme: theme,
                                getMessageViews: { [weak self] in self?.messageViews ?? [:] },
                                isMinimapGutter: false)
    gutterView.autoresizingMask  = .none
    self.gutterView              = gutterView
    // NB: The gutter view is floating. We cannot add it now, as we don't have an `enclosingScrollView` yet.

    let currentLineHighlightView = CodeBackgroundHighlightView(color: theme.currentLineColour)
    addBackgroundSubview(currentLineHighlightView)
    self.currentLineHighlightView = currentLineHighlightView


    // We register the text layout manager of the minimap view as a secondary layout manager of the code view's text
    // content storage, so that code view and minimap use the same content.
    textContentStorage.primaryTextLayoutManager = textLayoutManager


    let documentVisibleBox = NSBox()
    documentVisibleBox.boxType     = .custom
    documentVisibleBox.fillColor   = theme.textColour.withAlphaComponent(0.1)
    documentVisibleBox.borderWidth = 0
    self.documentVisibleBox = documentVisibleBox

    maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
      
    // We need to re-tile the subviews whenever the frame of the text view changes.
    NotificationCenter.default.addObserver(self,
                                           selector: #selector(handleEnclosingScrollViewFrameDidChange(_:)),
                                           name: NSView.frameDidChangeNotification,
                                           object: enclosingScrollView)

    // We need to check whether we need to look up completions or cancel a running completion process after every text
    // change. We also need to remove evicted message views.
    NotificationCenter.default.addObserver(self,
                                           selector: #selector(handleTextDidChangeNotification(_:)),
                                           name: NSText.didChangeNotification,
                                           object: self)

    Task {
      do {
        try await startLanguageService()
      } catch let error {
        logger.trace("Failed to start language service for \(language.name): \(error.localizedDescription)")
      }
    }
  }
  
  /// Try to activate the language service for the currently configured language.
  ///
  func startLanguageService() async throws {
    guard let textStorage else { return }

    diagnosticsCancellable = nil
    eventsCancellable      = nil

    if let languageService = codeStorageDelegate.languageService {

      try await languageService.openDocument(with: textStorage.string,
                                             locationService: codeStorageDelegate.lineMapLocationConverter)

      // Report diagnostic messages as they come in.
      diagnosticsCancellable = languageService.diagnostics
        .receive(on: DispatchQueue.main)
        .sink { [weak self] messages in

          self?.setMessages(messages)
          self?.update(messages: messages)
        }

      eventsCancellable = languageService.events
        .receive(on: DispatchQueue.main)
        .sink { [weak self] event in

          self?.process(event: event)
        }
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: nil)
    NotificationCenter.default.removeObserver(self, name: NSText.didChangeNotification, object: self)
  }


  // MARK: Overrides

  override func setSelectedRanges(_ ranges: [NSValue],
                                  affinity: NSSelectionAffinity,
                                  stillSelecting stillSelectingFlag: Bool)
  {
    let oldSelectedRanges = selectedRanges
    super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)

    // Updates only if there is an actual selection change.
    if oldSelectedRanges != selectedRanges {

      // FIXME: The following does not succeed for anything, but setting an insertion point. From macOS 15, selecting
      // FIXME: across more than one line, leads to a crash.
//      minimapView?.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
      // FIXME: Hence, we only set insertion points for now. (They lead to a line highlight.)
      if let insertionPoint {
        minimapView?.setSelectedRange(NSRange(location: insertionPoint, length: 0))
      }

      updateBackgroundFor(oldSelection: combinedRanges(ranges: oldSelectedRanges),
                          newSelection: combinedRanges(ranges: ranges))

    }
  }

  @objc private func handleEnclosingScrollViewFrameDidChange(_ notification: Notification) {
    // When resizing the window, explicit gutter redraw keeps line numbers in sync with updated wraps.
    gutterView?.needsDisplay = true
  }

  @objc private func handleTextDidChangeNotification(_ notification: Notification) {
    considerCompletionFor(range: rangeForUserCompletion)
    invalidateMessageViews(withIDs: codeStorageDelegate.lastInvalidatedMessageIDs)
  }

  override func layout() {
    tile()
    super.layout()
    gutterView?.needsDisplay        = true
    minimapGutterView?.needsDisplay = true
  }
}

final class CodeViewDelegate: NSObject, NSTextViewDelegate {

  // Hooks for events
  //
  var textDidChange:      ((NSTextView) -> ())?
  var selectionDidChange: ((NSTextView) -> ())?

  // MARK: NSTextViewDelegate protocol

  func textView(_ textView: NSTextView,
                willChangeSelectionFromCharacterRanges oldSelectedCharRanges: [NSValue],
                toCharacterRanges newSelectedCharRanges: [NSValue])
  -> [NSValue]
  {
    guard let codeStorageDelegeate = textView.textStorage?.delegate as? CodeStorageDelegate,
          textView is CodeView    // Don't execute this for the minimap view
    else { return newSelectedCharRanges }

    // If token completion added characters, we don't want to include them in the advance of the insertion point.
    if codeStorageDelegeate.tokenCompletionCharacters > 0,
       let selectionRange = newSelectedCharRanges.first as? NSRange,
       selectionRange.length == 0
    {

      let insertionPointWithoutCompletion = selectionRange.location - codeStorageDelegeate.tokenCompletionCharacters
      codeStorageDelegeate.tokenCompletionCharacters = 0
      return [NSRange(location: insertionPointWithoutCompletion, length: 0) as NSValue]

    } else { return newSelectedCharRanges }
  }

  func textDidChange(_ notification: Notification) {
    guard let textView = notification.object as? NSTextView else { return }

    textDidChange?(textView)
  }

  func textViewDidChangeSelection(_ notification: Notification) {
    guard let textView = notification.object as? NSTextView else { return }

    selectionDidChange?(textView)
  }
}

/// Custom view for background highlights.
///
final class CodeBackgroundHighlightView: NSBox {

  /// The background colour displayed by this view.
  ///
  var color: NSColor {
    get { fillColor }
    set { fillColor = newValue }
  }

  init(color: NSColor) {
    super.init(frame: .zero)
    self.color  = color
    boxType     = .custom
    borderWidth = 0
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}


// MARK: -
// MARK: Shared code

extension CodeView {

  // MARK: Background highlights
  
  /// Update the code background for the given selection change.
  ///
  /// - Parameters:
  ///   - oldRange: Old selection range.
  ///   - newRange: New selection range.
  ///
  /// This includes both invalidating rectangle for background redrawing as well as updating the frames of background
  /// (highlighting) views.
  ///
  func updateBackgroundFor(oldSelection oldRange: NSRange, newSelection newRange: NSRange) {
    guard let textContentStorage = optTextContentStorage else { return }

    let lineOfInsertionPoint = insertionPoint.flatMap{ optLineMap?.lineOf(index: $0) }

    // If the insertion point changed lines, we need to redraw at the old and new location to fix the line highlighting.
    // NB: We retain the last line and not the character index as the latter may be inaccurate due to editing that let
    //     to the selected range change.
    if lineOfInsertionPoint != oldLastLineOfInsertionPoint {

      if let textLocation = textContentStorage.textLocation(for: oldRange.location) {
        minimapView?.invalidateBackground(forLineContaining: textLocation)
      }

      if let textLocation = textContentStorage.textLocation(for: newRange.location) {
        updateCurrentLineHighlight(for: textLocation)
        minimapView?.invalidateBackground(forLineContaining: textLocation)
      }
    }
    oldLastLineOfInsertionPoint = lineOfInsertionPoint

    // Needed as the selection affects line number highlighting.
    // NB: Invalidation of the old and new ranges needs to happen separately. If we were to union them, an insertion
    //     point (range length = 0) at the start of a line would be absorbed into the previous line, which results in
    //     a lack of invalidation of the line on which the insertion point is located.
    gutterView?.invalidateGutter(for: oldRange)
    gutterView?.invalidateGutter(for: newRange)
    minimapGutterView?.invalidateGutter(for: oldRange)
    minimapGutterView?.invalidateGutter(for: newRange)

    Task { @MainActor in
      collapseMessageViews()
      updateMessageLineHighlights()
    }
  }

  func updateCurrentLineHighlight(for location: NSTextLocation) {
    guard let textLayoutManager = optTextLayoutManager else { return }

    ensureLayout(includingMinimap: false)

    // The current line highlight view needs to be visible if we have an insertion point (and not a selection range).
    currentLineHighlightView?.isHidden = insertionPoint == nil

    // The insertion point is inside the body of the text
    if let fragmentFrame = textLayoutManager.textLayoutFragment(for: location)?.layoutFragmentFrameWithoutExtraLineFragment,
       let highlightRect = lineBackgroundRect(y: fragmentFrame.minY, height: fragmentFrame.height)
    {
      currentLineHighlightView?.frame = highlightRect
    } else 
    // OR the insertion point is behind the end of the text, which ends with a trailing newline (=> extra line fragement)
    if let previousLocation = optTextContentStorage?.location(location, offsetBy: -1),
       let fragmentFrame    = textLayoutManager.textLayoutFragment(for: previousLocation)?.layoutFragmentFrameExtraLineFragment,
       let highlightRect    = lineBackgroundRect(y: fragmentFrame.minY, height: fragmentFrame.height)
    {
      currentLineHighlightView?.frame = highlightRect
    } else
    // OR the insertion point is behind the end of the text, which does NOT end with a trailing newline
    if let previousLocation = optTextContentStorage?.location(location, offsetBy: -1),
       let fragmentFrame    = textLayoutManager.textLayoutFragment(for: previousLocation)?.layoutFragmentFrame,
       let highlightRect    = lineBackgroundRect(y: fragmentFrame.minY, height: fragmentFrame.height)
    {
      currentLineHighlightView?.frame = highlightRect
    } else
    // OR the document is empty
    if text.isEmpty,
       let highlightRect = lineBackgroundRect(y: 0, height: font?.lineHeight ?? 0)
    {
      currentLineHighlightView?.frame = highlightRect
    }
  }

  func updateMessageLineHighlights() {
    ensureLayout(includingMinimap: false)

    for messageView in messageViews {

      if let telescopeCharacterIndex = messageView.value.characterIndexTelescope,
         !messageView.value.invalidated     // No telesopes for invalidates messages
      {

        if let startLocation  = optTextContentStorage?.textLocation(for: messageView.value.characterIndex),
           let endLocation    = optTextContentStorage?.textLocation(for: telescopeCharacterIndex),
           let textRange      = NSTextRange(location: startLocation, end: endLocation),
           let extent         = optTextLayoutManager?.textLayoutFragmentExtent(for: textRange),
           let highlightRect  = lineBackgroundRect(y: extent.y, height: extent.height)
        {
          messageView.value.backgroundView.frame = highlightRect
        }

      } else {

        if let textLocation  = optTextContentStorage?.textLocation(for: messageView.value.characterIndex),
           let fragmentFrame = optTextLayoutManager?.textLayoutFragment(for: textLocation)?.layoutFragmentFrameWithoutExtraLineFragment,
           let highlightRect = lineBackgroundRect(y: fragmentFrame.minY, height: fragmentFrame.height),
           messageView.value.backgroundView.frame != highlightRect
        {
          messageView.value.backgroundView.frame = highlightRect
        }
      }
    }
  }

  
  // MARK: Tiling
  
  /// Ensure that layout of the viewport region is complete.
  ///
  func ensureLayout(includingMinimap: Bool = true) {
    if let textLayoutManager {
      textLayoutManager.ensureLayout(for: textLayoutManager.textViewportLayoutController.viewportBounds)
    }
    if includingMinimap,
       let textLayoutManager = minimapView?.textLayoutManager 
    {
      textLayoutManager.ensureLayout(for: textLayoutManager.textViewportLayoutController.viewportBounds)
    }
  }

  /// Position and size the gutter and minimap and set the text container sizes and exclusion paths. Take the current
  /// view layout in `viewLayout` into account.
  ///
  /// * The main text view contains three subviews: (1) the main gutter on its left side, (2) the minimap on its right
  ///   side, and (3) a divider in between the code view and the minimap gutter.
  /// * The main text view by way of `lineFragmentRect(forProposedRect:at:writingDirection:remaining:)`and the minimap
  ///   view (or rather their text container) by way of an exclusion path keep text out of the gutter view. The main
  ///   text view is moreover sized to avoid overlap with the minimap.
  /// * The minimap is a fixed factor `minimapRatio` smaller than the main text view and uses a correspondingly smaller
  ///   font accomodate exactly the same number of characters, so that line breaking procceds in the exact same way.
  ///
  /// NB: We don't use a ruler view for the gutter on macOS to be able to use the same setup on macOS and iOS.
  ///
  @MainActor
  private func tile() {
    guard let codeContainer = optTextContainer as? CodeContainer else { return }

    // Add the floating views if they are not yet in the view hierachy.
    // NB: Since macOS 14, we need to explicitly set clipping; otherwise, views will draw outside of the bounds of the
    //     scroll view. We need to do this vor each view, as it is not guaranteed that they share a container view.
    if let view = gutterView, view.superview == nil {
      enclosingScrollView?.addFloatingSubview(view, for: .horizontal)
      view.superview?.clipsToBounds = true
    }
    if let view = minimapDividerView, view.superview == nil {
      enclosingScrollView?.addFloatingSubview(view, for: .horizontal)
      view.superview?.clipsToBounds = true
    }
    if let view = minimapView, view.superview == nil {
      enclosingScrollView?.addFloatingSubview(view, for: .horizontal)
      view.superview?.clipsToBounds = true
    }

    // Compute size of the main view gutter
    //
    let theFont                 = font ?? OSFont.systemFont(ofSize: 0),
        fontWidth               = theFont.maximumHorizontalAdvancement,  // NB: we deal only with fixed width fonts
        gutterWidthInCharacters = CGFloat(4),
        gutterWidth             = ceil(fontWidth * gutterWidthInCharacters),
        minimumHeight           = max(contentSize.height, documentVisibleRect.height),
        gutterSize              = CGSize(width: gutterWidth, height: minimumHeight),
        lineFragmentPadding     = CGFloat(5)

    if gutterView?.frame.size != gutterSize { gutterView?.frame = CGRect(origin: .zero, size: gutterSize) }

    let visibleWidth         = documentVisibleRect.width,
        codeViewWidth        = visibleWidth,
        minimapWidth         = visibleWidth - codeViewWidth,

    isHorizontallyResizable                    = !viewLayout.wrapText
    if !isHorizontallyResizable && frame.size.width != visibleWidth { frame.size.width = visibleWidth }  // don't update frames in vain

    // Set the text container area of the main text view to reach up to the minimap
    // NB: We use the `excess` width to capture the slack that arises when the window width admits a fractional
    //     number of characters. Adding the slack to the code view's text container size doesn't work as the line breaks
    //     of the minimap and main code view are then sometimes not entirely in sync.
    let codeContainerWidth = if viewLayout.wrapText { codeViewWidth - gutterWidth } else { CGFloat.greatestFiniteMagnitude }
    if codeContainer.size.width != codeContainerWidth {
      codeContainer.size = CGSize(width: codeContainerWidth, height: CGFloat.greatestFiniteMagnitude)
    }

    codeContainer.lineFragmentPadding = lineFragmentPadding
    if textContainerInset.width != gutterWidth {
      textContainerInset = CGSize(width: gutterWidth, height: 0)
    }

    // Set the width of the text container for the minimap just like that for the code view as the layout engine works
    // on the original code view metrics. (Only after the layout is done, we scale it down to the size of the minimap.)
    let minimapTextContainerWidth = codeContainerWidth
    let minimapTextContainer = minimapView?.textContainer
    if minimapWidth != minimapView?.frame.width || minimapTextContainerWidth != minimapTextContainer?.size.width {

      minimapTextContainer?.size                = CGSize(width: minimapTextContainerWidth,
                                                               height: CGFloat.greatestFiniteMagnitude)
      minimapTextContainer?.lineFragmentPadding = 0

    }

    // Only after tiling can we get the correct frame for the highlight views.
    if let textLocation = optTextContentStorage?.textLocation(for: selectedRange.location) {
      updateCurrentLineHighlight(for: textLocation)
    }
    updateMessageLineHighlights()
  }


  // MARK: Message views

  /// Update the layout of the specified message view if its geometry got invalidated by
  /// `CodeTextContainer.lineFragmentRect(forProposedRect:at:writingDirection:remaining:)`.
  ///
  fileprivate func layoutMessageView(identifiedBy id: UUID) {

    guard let textLayoutManager  = textLayoutManager,
          let textContentManager = textLayoutManager.textContentManager as? NSTextContentStorage,
          let codeContainer      = optTextContainer as? CodeContainer,
          let messageBundle      = messageViews[id]
    else { return }

    if messageBundle.geometry == nil {

      guard let startLocation         = textContentManager.textLocation(for: messageBundle.characterIndex),
            let textLayoutFragment    = textLayoutManager.textLayoutFragment(for: startLocation),
            let firstLineFragmentRect = textLayoutFragment.textLineFragments.first?.typographicBounds
      else { return }

      // Compute the message view geometry from the text layout information
      let geometry = MessageGeometry(lineWidth: messageBundle.lineFragementRect.width - firstLineFragmentRect.maxX,
                                          lineHeight: firstLineFragmentRect.height,
                                          popupWidth:
                                            (codeContainer.size.width - MessageGeometry.popupRightSideOffset) * 0.75,
                                          popupOffset: textLayoutFragment.layoutFragmentFrame.height + 2)
      messageViews[id]?.geometry = geometry

      // Configure the view with the new geometry
      messageBundle.view.geometry = geometry
      if messageBundle.view.superview == nil {

        // Add the messages view
        addSubview(messageBundle.view)
        let topOffset           = textContainerOrigin.y + messageBundle.lineFragementRect.minY,
            topAnchorConstraint = messageBundle.view.topAnchor.constraint(equalTo: self.topAnchor,
                                                                          constant: topOffset)
        let leftOffset            = textContainerOrigin.x + messageBundle.lineFragementRect.maxX,
            rightAnchorConstraint = messageBundle.view.rightAnchor.constraint(equalTo: self.leftAnchor,
                                                                              constant: leftOffset)
        messageViews[id]?.topAnchorConstraint   = topAnchorConstraint
        messageViews[id]?.rightAnchorConstraint = rightAnchorConstraint
        NSLayoutConstraint.activate([topAnchorConstraint, rightAnchorConstraint])

        // Also add the corresponding background highlight view, such that it lies on top of the current line highlight.
        if let currentLineHighlightView {
          insertSubview(messageBundle.backgroundView, aboveSubview: currentLineHighlightView)
        }

      } else {

        // Update the messages view constraints
        let topOffset  = textContainerOrigin.y + messageBundle.lineFragementRect.minY,
            leftOffset = textContainerOrigin.x + messageBundle.lineFragementRect.maxX
        messageViews[id]?.topAnchorConstraint?.constant   = topOffset
        messageViews[id]?.rightAnchorConstraint?.constant = leftOffset

      }
    }
  }
  
  /// Update the whole set of current messages to a new set.
  ///
  /// - Parameter messages: The new set of messages.
  ///
  func update(messages: Set<TextLocated<Message>>) {

    // FIXME: Retracting all and then adding them again my be bad with animation of we re-add many of the same.
    retractMessages()
    for message in messages { report(message: message) }

    lastMessages = messages
  }

  /// Adds a new message to the set of messages for this code view.
  ///
  func report(message: TextLocated<Message>) {
    guard let messageBundle = codeStorageDelegate.add(message: message) else { return }

    updateMessageView(for: messageBundle, at: message.location.zeroBasedLine)
  }

  /// Removes a given message. If it doesn't exist, do nothing. This function is quite expensive.
  ///
  func retract(message: Message) {
    guard let (messageBundle, line) = codeStorageDelegate.remove(message: message) else { return }

    updateMessageView(for: messageBundle, at: line)
  }

  /// Given a new or updated message bundle, update the corresponding message view appropriately. This includes covering
  /// the two special cases, where we create a new view or we remove a view for good (as its last message got deleted).
  ///
  /// NB: The `line` argument is zero-based.
  ///
  private func updateMessageView(for messageBundle: LineInfo.MessageBundle, at line: Int) {
    guard let charRange = codeStorageDelegate.lineMap.lookup(line: line)?.range else { return }

    // NB: If the message info with that id has been invalidated, it just gets removed here, and hence, we don't have to
    //      worry about a mix of invalidated and new messages.
    removeMessageViews(withIDs: [messageBundle.id])

    // If we removed the last message of this view, we don't need to create a new version
    if messageBundle.messages.isEmpty { return }

    // TODO: CodeEditor needs to be parameterised by message theme
    let messageTheme = Message.defaultTheme

    let messageView = MessageContainerView(messages: messageBundle.messages,
                                                      theme: messageTheme,
                                                      background: backgroundColor,
                                                      geometry: MessageGeometry(lineWidth: 100,
                                                                               lineHeight: 15,
                                                                               popupWidth: 300,
                                                                               popupOffset: 16),
                                                      fontSize: font?.pointSize ?? OSFont.systemFontSize),
        principalCategory = messagesByCategory(messageBundle.messages)[0].key,
        colour            = messageTheme(principalCategory).colour,
        backgroundView    = CodeBackgroundHighlightView(color: colour.withAlphaComponent(0.1)),
        telescope: Int?   = if messageBundle.messages.count == 1 { messageBundle.messages[0].telescope } else { nil }

    messageViews[messageBundle.id] = MessageInfo(view: messageView,
                                                 backgroundView: backgroundView,
                                                 characterIndex: 0,
                                                 telescope: telescope,
                                                 characterIndexTelescope: telescope.map{ _ in 0 },
                                                 lineFragementRect: .zero,
                                                 geometry: nil,
                                                 colour: colour,
                                                 invalidated: false)

    // We invalidate the layout of the line where the message belongs as their may be less space for the text now and
    // because the layout process for the text fills the `lineFragmentRect` property of the above `MessageInfo`.
    if let textRange = optTextContentStorage?.textRange(for: charRange) {

      optTextLayoutManager?.invalidateLayout(for: textRange)

    }
    updateMessageLineHighlights()
  }

  /// Remove the messages associated with a specified range of lines.
  ///
  /// - Parameter onLines: The line range where messages are to be removed. If `nil`, all messages on this code view are
  ///     to be removed.
  ///
  func retractMessages(onLines lines: Range<Int>? = nil) {
    var messageIds: [LineInfo.MessageBundle.ID] = []

    // Remove all message bundles in the line map and collect their ids for subsequent view removal.
    for line in lines ?? codeStorageDelegate.lineMap.lines.indices {

      if let messageBundle = codeStorageDelegate.messages(at: line) {

        messageIds.append(messageBundle.id)
        codeStorageDelegate.removeMessages(at: line)

      }

    }

    // Make sure to remove all views that are still around if necessary.
    if lines == nil { removeMessageViews() } else { removeMessageViews(withIDs: messageIds) }
  }

  /// Invalidate the message views with the given ids.
  ///
  /// - Parameter ids: The IDs of the message bundles that ought to be invalidated. If `nil`, invalidate all.
  ///
  /// IDs that do not have an associated message view cause no harm.
  ///
  fileprivate func invalidateMessageViews(withIDs ids: [LineInfo.MessageBundle.ID]? = nil) {

    for id in ids ?? Array<LineInfo.MessageBundle.ID>(messageViews.keys) {
      messageViews[id]?.invalidated = true
      if let info = messageViews[id] {

        info.backgroundView.color = OSColor.gray.withAlphaComponent(0.1)
        info.view.invalidated     = true

      }
    }
  }

  /// Remove the message views with the given ids.
  ///
  /// - Parameter ids: The IDs of the message bundles that ought to be removed. If `nil`, remove all.
  ///
  /// IDs that do not have an associated message view cause no harm.
  ///
  fileprivate func removeMessageViews(withIDs ids: [LineInfo.MessageBundle.ID]? = nil) {

    for id in ids ?? Array<LineInfo.MessageBundle.ID>(messageViews.keys) {

      if let info = messageViews[id] {
        info.view.removeFromSuperview()
        info.backgroundView.removeFromSuperview()
      }
      messageViews.removeValue(forKey: id)

    }
  }

  /// Ensure that all message views are in their collapsed state.
  ///
  func collapseMessageViews() {
    for messageView in messageViews {
      messageView.value.view.isExpanded = false
    }
  }

  // MARK: Events


  func process(event: LanguageServiceEvent) {
    guard let codeStorage = optCodeStorage else { return }

    switch event {

    case .tokensAvailable(lineRange: let lineRange):
      codeStorageDelegate.requestSemanticTokens(for: lineRange, in: codeStorage)
    }
  }
}


// MARK: Code container

final class CodeContainer: NSTextContainer, @unchecked Sendable {

  #if os(iOS) || os(visionOS)
  weak var textView: UITextView?
  #endif

  // We adapt line fragment rects in two ways: (1) we leave `gutterWidth` space on the left hand side and (2) on every
  // line that contains a message, we leave `MessageGeometry.minimumInlineWidth` space on the right hand side (but only for
  // the first line fragment of a layout fragment).
  override func lineFragmentRect(forProposedRect proposedRect: CGRect,
                                 at characterIndex: Int,
                                 writingDirection baseWritingDirection: NSWritingDirection,
                                 remaining remainingRect: UnsafeMutablePointer<CGRect>?)
  -> CGRect
  { 
    let superRect      = super.lineFragmentRect(forProposedRect: proposedRect,
                                                at: characterIndex,
                                                writingDirection: baseWritingDirection,
                                                remaining: remainingRect),
        calculatedRect = CGRect(x: 0, y: superRect.minY, width: size.width, height: superRect.height)
    let tv = textView

    return MainActor.assumeIsolated {
      guard let codeView    = tv as? CodeView,
            let codeStorage = codeView.textStorage as? CodeStorage,
            let delegate    = codeStorage.delegate as? CodeStorageDelegate,
            let line        = delegate.lineMap.lineOf(index: characterIndex),
            let oneLine     = delegate.lineMap.lookup(line: line),
            characterIndex == oneLine.range.location
      else { return calculatedRect }

      if let messageBundleId = delegate.messages(at: line)?.id,
         calculatedRect.width > 2 * MessageGeometry.minimumInlineWidth
      {

        codeView.messageViews[messageBundleId]?.characterIndex    = characterIndex
        codeView.messageViews[messageBundleId]?.lineFragementRect = calculatedRect
        codeView.messageViews[messageBundleId]?.geometry = nil

        if let lines   = codeView.messageViews[messageBundleId]?.telescope,
           let oneLine = delegate.lineMap.lookup(line: line + lines)
        {
          codeView.messageViews[messageBundleId]?.characterIndexTelescope = oneLine.range.max
        }

        Task { @MainActor in
          codeView.layoutMessageView(identifiedBy: messageBundleId)
        }

        return CGRect(origin: calculatedRect.origin,
                      size: CGSize(width: calculatedRect.width - MessageGeometry.minimumInlineWidth,
                                   height: calculatedRect.height))

      } else { return calculatedRect }
    }
  }
}


// MARK: [Note NSTextViewportLayoutControllerDelegate]
//
// According to the TextKit 2 documentation, a 'NSTextViewportLayoutControllerDelegate' is the right place to be
// notified of the start and end of a layout pass. When using TextKit 2 with a standard 'NS/UITextView' there curiously
// is already a delegate set for the 'NSTextViewportLayoutController'. It uses a private class, so we cannot subclass
// it. The obvious alternative is to wrap it as in the code below. However, this leads to redraw problems on iOS (when
// repeatedly inserting and again deleting lines).
//
//final class CodeViewportLayoutControllerDelegate: NSObject, NSTextViewportLayoutControllerDelegate {
//
//  /// When TextKit 2 initialises a text view, it provides a default delegate for the `NSTextViewportLayoutController`.
//  /// We keep that here when overwriting it with an instance of this very class.
//  ///
//  let systemDelegate: any NSTextViewportLayoutControllerDelegate
//  
//  /// The code view to which this delegate belongs.
//  ///
//  weak var codeView: CodeView?
//
//  init(systemDelegate: any NSTextViewportLayoutControllerDelegate, codeView: CodeView) {
//    self.systemDelegate = systemDelegate
//    self.codeView       = codeView
//  }
//
//  public func viewportBounds(for textViewportLayoutController: NSTextViewportLayoutController) -> CGRect {
//    systemDelegate.viewportBounds(for: textViewportLayoutController)
//  }
//
//  public func textViewportLayoutController(_ textViewportLayoutController: NSTextViewportLayoutController,
//                                           configureRenderingSurfaceFor textLayoutFragment: NSTextLayoutFragment)
//  {
//    systemDelegate.textViewportLayoutController(textViewportLayoutController,
//                                                configureRenderingSurfaceFor: textLayoutFragment)
//  }
//
//  public func textViewportLayoutControllerWillLayout(_ textViewportLayoutController: NSTextViewportLayoutController) {
//    systemDelegate.textViewportLayoutControllerWillLayout?(textViewportLayoutController)
//  }
//
//  public func textViewportLayoutControllerDidLayout(_ textViewportLayoutController: NSTextViewportLayoutController) {
//    systemDelegate.textViewportLayoutControllerDidLayout?(textViewportLayoutController)
//
//    if let location     = codeView?.selectedRange.location,
//       let textLocation = codeView?.optTextContentStorage?.textLocation(for: location) {
//      codeView?.updateCurrentLineHighlight(for: textLocation)
//    }
//    codeView?.updateMessageLineHighlights()
//  }
//}


// MARK: Selection change management

/// Common code view actions triggered on a selection change.
///
@MainActor func selectionDidChange<TV: TextView>(_ textView: TV) {
  guard let codeStorage  = textView.optCodeStorage,
        let visibleLines = textView.documentVisibleLines
  else { return }

  if let location             = textView.insertionPoint,
     let matchingBracketRange = codeStorage.matchingBracket(at: location, in: visibleLines)
  {
    textView.showFindIndicator(for: matchingBracketRange)
  }
}


// MARK: NSRange

/// Combine selection ranges into the smallest ranges encompassing them all.
///
private func combinedRanges(ranges: [NSValue]) -> NSRange {
  let actualranges = ranges.compactMap{ $0 as? NSRange }
  return actualranges.dropFirst().reduce(actualranges.first ?? .zero) {
    NSUnionRange($0, $1)
  }
}
