//
//  CodeActions.swift
//
//
//  Created by Fauzaan on 31/01/2023.
//

import Combine
import AppKit
import SwiftUI  // Required for LanguageService `any View` types (InfoPopover, completion row/doc views)
import os

@preconcurrency import LanguageSupport


private let logger = Logger(subsystem: "org.justtesting.CodeEditorView", category: "CodeActions")


// MARK: -
// MARK: Code info support

/// Popover used to display the result of an info code query.
///
/// NB: Retains `NSHostingController` because `LanguageService.info()` returns `any View`.
///
final class InfoPopover: NSPopover {

  init(displaying view: any View, width: CGFloat) {
    super.init()
    let rootView = ScrollView(.vertical){ AnyView(view).padding() }
                     .frame(width: width, alignment: .topLeading)
    contentViewController = NSHostingController(rootView: rootView)
    contentViewController?.preferredContentSize = CGSize(width: width, height: width * 1.1)
    behavior = .transient
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

extension CodeView {

  @MainActor
  func show(infoPopover: InfoPopover, for range: NSRange) {
    self.infoPopover?.close()
    self.infoPopover = infoPopover

    let screenRect         = firstRect(forCharacterRange: range, actualRange: nil),
        nonEmptyScreenRect = NSRect(origin: screenRect.origin, size: CGSize(width: 1, height: 1)),
        windowRect         = window!.convertFromScreen(nonEmptyScreenRect)

    infoPopover.show(relativeTo: convert(windowRect, from: nil), of: self, preferredEdge: .maxY)
  }

  func infoAction() {
    guard let languageService = optLanguageService else { return }

    let width = min((window?.frame.width ?? 250) * 0.75, 500)

    let range = selectedRange()
    Task {
      do {
        if let info = try await languageService.info(at: range.location) {
          show(infoPopover: InfoPopover(displaying: info.view, width: width), for: info.anchor ?? range)
        }
      } catch let error { logger.trace("Info action failed: \(error.localizedDescription)") }
    }
  }
}


// MARK: -
// MARK: Completions support

public enum CompletionProgress {
  case cancel
  case completion(String, NSRange?)
  case input(NSEvent)
}


// MARK: Completion display info

public struct CompletionDisplayInfo: Sendable {
  public enum Kind: Sendable, Hashable {
    case keyword, function, table, column, info

    /// Single character shown inside the kind badge. Uppercase so the letters
    /// sit consistently in a fixed-size monospaced badge.
    var badgeLetter: String {
      switch self {
      case .keyword: return "K"
      case .function: return "F"
      case .table: return "T"
      case .column: return "C"
      case .info: return "i"
      }
    }

    var badgeTint: NSColor {
      switch self {
      case .keyword: return NSColor(calibratedRed: 0.40, green: 0.58, blue: 0.95, alpha: 1.0)
      case .function: return NSColor(calibratedRed: 0.72, green: 0.46, blue: 0.91, alpha: 1.0)
      case .table: return NSColor(calibratedRed: 0.27, green: 0.70, blue: 0.54, alpha: 1.0)
      case .column: return .secondaryLabelColor
      case .info: return .tertiaryLabelColor
      }
    }
  }

  public let label: String
  public let detail: String?
  public let kind: Kind

  public init(label: String, detail: String?, kind: Kind) {
    self.label = label
    self.detail = detail
    self.kind = kind
  }
}


// MARK: Completion cell view

/// Language services that populate `displayInfo` get the AppKit-native render path;
/// everything else falls back to hosting the Completion's `rowView` in `NSHostingView`.
final class CompletionCellView: NSTableCellView {

  static let identifier = NSUserInterfaceItemIdentifier("CompletionCellView")

  private static let rowHeight: CGFloat = 26
  private static let horizontalInset: CGFloat = 10
  private static let contentPadding: CGFloat = 12
  private static let selectionInset: CGFloat = 6
  private static let selectionCornerRadius: CGFloat = 9

  private let badgeView = BadgeView()
  private let labelField: NSTextField = {
    let field = CompletionCellView.makeTextField(size: 12, weight: .regular, monospaced: true)
    field.lineBreakMode = .byTruncatingMiddle
    field.cell?.lineBreakMode = .byTruncatingMiddle
    return field
  }()
  private let detailField = CompletionCellView.makeTextField(size: 10, weight: .regular, monospaced: true)
  private let selectionBackgroundLayer = CALayer()
  private var hostingView: NSHostingView<AnyView>?

  private static func makeTextField(size: CGFloat, weight: NSFont.Weight, monospaced: Bool) -> NSTextField {
    let field = NSTextField(labelWithString: "")
    if monospaced {
      field.font = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    } else {
      field.font = NSFont.systemFont(ofSize: size, weight: weight)
    }
    field.isEditable = false
    field.isBordered = false
    field.drawsBackground = false
    field.lineBreakMode = .byTruncatingTail
    field.usesSingleLineMode = true
    field.cell?.truncatesLastVisibleLine = true
    field.translatesAutoresizingMaskIntoConstraints = false
    return field
  }

  private func installNativeLayoutIfNeeded() {
    guard badgeView.superview == nil else { return }

    wantsLayer = true
    selectionBackgroundLayer.cornerRadius = Self.selectionCornerRadius
    selectionBackgroundLayer.masksToBounds = true
    selectionBackgroundLayer.isHidden = true
    selectionBackgroundLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    layer?.addSublayer(selectionBackgroundLayer)

    addSubview(badgeView)
    addSubview(labelField)
    addSubview(detailField)

    detailField.alignment = .right
    detailField.setContentCompressionResistancePriority(.required, for: .horizontal)
    detailField.setContentHuggingPriority(.required, for: .horizontal)

    labelField.setContentHuggingPriority(.defaultLow, for: .horizontal)
    labelField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    NSLayoutConstraint.activate([
      badgeView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.contentPadding),
      badgeView.centerYAnchor.constraint(equalTo: centerYAnchor),
      badgeView.widthAnchor.constraint(equalToConstant: 14),
      badgeView.heightAnchor.constraint(equalToConstant: 14),

      labelField.leadingAnchor.constraint(equalTo: badgeView.trailingAnchor, constant: 8),
      labelField.centerYAnchor.constraint(equalTo: centerYAnchor),

      detailField.leadingAnchor.constraint(greaterThanOrEqualTo: labelField.trailingAnchor, constant: 8),
      detailField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.contentPadding),
      detailField.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  func configure(
    with item: Completions.Completion,
    isSelected: Bool,
    displayInfo: CompletionDisplayInfo?
  ) {
    if let displayInfo {
      configureNative(displayInfo: displayInfo, isSelected: isSelected)
    } else {
      configureHostingFallback(item: item, isSelected: isSelected)
    }
  }

  /// Selection-only update path used during arrow-key navigation.
  func setSelected(_ isSelected: Bool) {
    updateSelectionLayer(isSelected: isSelected)
  }

  private func configureNative(displayInfo: CompletionDisplayInfo, isSelected: Bool) {
    if let hostingView {
      hostingView.removeFromSuperview()
      self.hostingView = nil
    }
    installNativeLayoutIfNeeded()

    badgeView.isHidden = false
    labelField.isHidden = false
    detailField.isHidden = false

    labelField.stringValue = displayInfo.label
    labelField.textColor = .labelColor

    if let detail = displayInfo.detail, !detail.isEmpty {
      detailField.stringValue = detail
      detailField.textColor = .secondaryLabelColor
      detailField.isHidden = false
    } else {
      detailField.stringValue = ""
      detailField.isHidden = true
    }

    badgeView.apply(kind: displayInfo.kind)
    updateSelectionLayer(isSelected: isSelected)
  }

  private func configureHostingFallback(item: Completions.Completion, isSelected: Bool) {
    badgeView.isHidden = true
    labelField.isHidden = true
    detailField.isHidden = true
    selectionBackgroundLayer.isHidden = true

    let newRoot = AnyView(AnyView(item.rowView(isSelected)).lineLimit(1))
    if let hosting = hostingView {
      hosting.rootView = newRoot
    } else {
      let hosting = NSHostingView(rootView: newRoot)
      hosting.translatesAutoresizingMaskIntoConstraints = false
      addSubview(hosting)
      NSLayoutConstraint.activate([
        hosting.topAnchor.constraint(equalTo: topAnchor),
        hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
        hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
        hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
      ])
      hostingView = hosting
    }
  }

  private func updateSelectionLayer(isSelected: Bool) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }

    guard isSelected else {
      selectionBackgroundLayer.isHidden = true
      return
    }
    selectionBackgroundLayer.isHidden = false
    let inset = Self.selectionInset
    var frame = bounds
    frame.origin.x += inset
    frame.size.width -= inset * 2
    selectionBackgroundLayer.frame = frame

    let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    selectionBackgroundLayer.backgroundColor = (
      isDark
        ? NSColor(calibratedWhite: 1, alpha: 0.18)
        : NSColor(calibratedWhite: 0, alpha: 0.08)
    ).cgColor
  }

  override func layout() {
    super.layout()
    if !selectionBackgroundLayer.isHidden {
      let inset = Self.selectionInset
      var frame = bounds
      frame.origin.x += inset
      frame.size.width -= inset * 2
      selectionBackgroundLayer.frame = frame
    }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    if !selectionBackgroundLayer.isHidden {
      updateSelectionLayer(isSelected: true)
    }
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    hostingView?.removeFromSuperview()
    hostingView = nil
    badgeView.isHidden = false
    labelField.isHidden = false
    detailField.isHidden = false
    selectionBackgroundLayer.isHidden = true
  }
}


// MARK: Kind badge

private final class BadgeView: NSView {

  private let letterField: NSTextField = {
    let field = NSTextField(labelWithString: "")
    field.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
    field.alignment = .center
    field.textColor = .white
    field.drawsBackground = false
    field.isBordered = false
    field.translatesAutoresizingMaskIntoConstraints = false
    return field
  }()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
    layer?.cornerRadius = 3
    layer?.masksToBounds = true
    addSubview(letterField)
    NSLayoutConstraint.activate([
      letterField.centerXAnchor.constraint(equalTo: centerXAnchor),
      letterField.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func apply(kind: CompletionDisplayInfo.Kind) {
    letterField.stringValue = kind.badgeLetter
    layer?.backgroundColor = kind.badgeTint.cgColor
  }
}


// MARK: Completion documentation view

final class CompletionDocumentationView: NSView {
  private enum Layout {
    static let horizontalInset: CGFloat = 10
    static let topInset: CGFloat = 8
    static let badgeSize: CGFloat = 14
    static let badgeSpacing: CGFloat = 6
    static let detailTopSpacing: CGFloat = 4
    static let bottomInset: CGFloat = 8
  }

  private let badgeView = BadgeView()
  private let labelField: NSTextField = {
    let field = NSTextField(labelWithString: "")
    field.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
    field.isEditable = false
    field.isBordered = false
    field.drawsBackground = false
    field.lineBreakMode = .byTruncatingMiddle
    field.cell?.lineBreakMode = .byTruncatingMiddle
    field.translatesAutoresizingMaskIntoConstraints = false
    return field
  }()
  private let detailField: NSTextField = {
    let field = NSTextField(labelWithString: "")
    field.font = NSFont.systemFont(ofSize: 12)
    field.textColor = .secondaryLabelColor
    field.isEditable = false
    field.isBordered = false
    field.drawsBackground = false
    field.lineBreakMode = .byWordWrapping
    field.cell?.lineBreakMode = .byWordWrapping
    field.cell?.wraps = true
    field.cell?.usesSingleLineMode = false
    field.translatesAutoresizingMaskIntoConstraints = false
    return field
  }()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    addSubview(badgeView)
    addSubview(labelField)
    addSubview(detailField)

    NSLayoutConstraint.activate([
      badgeView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.horizontalInset),
      badgeView.topAnchor.constraint(equalTo: topAnchor, constant: Layout.topInset),
      badgeView.widthAnchor.constraint(equalToConstant: Layout.badgeSize),
      badgeView.heightAnchor.constraint(equalToConstant: Layout.badgeSize),

      labelField.leadingAnchor.constraint(equalTo: badgeView.trailingAnchor, constant: Layout.badgeSpacing),
      labelField.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor),
      labelField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Layout.horizontalInset),

      detailField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.horizontalInset),
      detailField.topAnchor.constraint(equalTo: badgeView.bottomAnchor, constant: Layout.detailTopSpacing),
      detailField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.horizontalInset),
      detailField.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -Layout.bottomInset),
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func apply(info: CompletionDisplayInfo) {
    badgeView.apply(kind: info.kind)
    labelField.stringValue = info.label
    labelField.textColor = .labelColor
    if let detail = info.detail, !detail.isEmpty {
      detailField.stringValue = detail
      detailField.isHidden = false
    } else {
      detailField.stringValue = ""
      detailField.isHidden = true
    }
  }

  func requiredHeight(for info: CompletionDisplayInfo, width: CGFloat) -> CGFloat {
    let labelHeight = max(labelField.font?.ascender ?? 0, Layout.badgeSize)
    let detailHeight: CGFloat

    if let detail = info.detail, !detail.isEmpty {
      let availableWidth = max(width - (Layout.horizontalInset * 2), 1)
      let rect = (detail as NSString).boundingRect(
        with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: [.font: detailField.font as Any]
      )
      detailHeight = ceil(rect.height)
    } else {
      detailHeight = 0
    }

    return ceil(
      Layout.topInset
      + labelHeight
      + (detailHeight > 0 ? Layout.detailTopSpacing + detailHeight : 0)
      + Layout.bottomInset
    )
  }
}


// MARK: Completion panel

final class CompletionPanel: NSPanel, NSTableViewDelegate, NSTableViewDataSource {
  private enum Metrics {
    static let minWidth: CGFloat = 280
    static let maxWidth: CGFloat = 300
    static let widthFractionOfEditor: CGFloat = 0.6
    static let rowHeight: CGFloat = 26
    static let listVerticalInset: CGFloat = 6
    static let minListHeight: CGFloat = 100
    static let maxListHeight: CGFloat = 240
    static let minDocumentationHeight: CGFloat = 52
    static let maxDocumentationHeight: CGFloat = 110
    static let screenInset: CGFloat = 16
    static let scrollbarAllowance: CGFloat = 18
    static let contentPadding: CGFloat = 32
  }

  private(set) var completions: Completions = .none
  private var selectedItemID: Int?

  var progressHandler: ((CompletionProgress) -> Void)?

  /// Optional lookup used by `CompletionCellView` to render rows in pure AppKit.
  /// Language services that want the faster path (see `CompletionDisplayInfo`)
  /// set this before calling `set(completions:)`.
  var displayInfoProvider: ((Int) -> CompletionDisplayInfo?)?

  private let container = CompletionContainerView()
  private let scrollView = NSScrollView()
  private let tableView = NSTableView()
  private let completionColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("CompletionColumn"))
  private let divider = NSBox()
  private let docScrollView = NSScrollView()
  private var docHostingView: NSHostingView<AnyView>?
  private let docNativeView = CompletionDocumentationView()
  private var anchorRect: CGRect?
  private var preferredMaximumWidth: CGFloat = Metrics.maxWidth
  private var currentDocumentationHeight: CGFloat = Metrics.minDocumentationHeight

  nonisolated(unsafe) private var didResignObserver: NSObjectProtocol?
  nonisolated(unsafe) private var outsideClickLocalMonitor: Any?
  nonisolated(unsafe) private var outsideClickGlobalMonitor: Any?

  init() {
    super.init(contentRect: NSRect(x: 0, y: 0, width: Metrics.minWidth, height: 300),
               styleMask: [.nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: true)
    collectionBehavior.insert(.fullScreenAuxiliary)
    isFloatingPanel             = true
    level                       = .floating
    titleVisibility             = .hidden
    titlebarAppearsTransparent  = true
    isMovableByWindowBackground = false
    hidesOnDeactivate           = true
    animationBehavior           = .utilityWindow
    backgroundColor             = .clear
    isOpaque                    = false
    hasShadow                   = false

    standardWindowButton(.closeButton)?.isHidden       = true
    standardWindowButton(.miniaturizeButton)?.isHidden = true
    standardWindowButton(.zoomButton)?.isHidden        = true

    setupViews()

    self.didResignObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didResignKeyNotification,
      object: self,
      queue: nil
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.close()
      }
    }
  }

  deinit {
    if let didResignObserver { NotificationCenter.default.removeObserver(didResignObserver) }
    if let outsideClickLocalMonitor { NSEvent.removeMonitor(outsideClickLocalMonitor) }
    if let outsideClickGlobalMonitor { NSEvent.removeMonitor(outsideClickGlobalMonitor) }
  }

  private func installOutsideClickMonitors() {
    guard outsideClickLocalMonitor == nil, outsideClickGlobalMonitor == nil else { return }

    outsideClickLocalMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] event in
      guard let self else { return event }
      if event.window !== self {
        MainActor.assumeIsolated { self.close() }
      }
      return event
    }

    outsideClickGlobalMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] _ in
      guard let self else { return }
      MainActor.assumeIsolated { self.close() }
    }
  }

  private func removeOutsideClickMonitors() {
    if let monitor = outsideClickLocalMonitor {
      NSEvent.removeMonitor(monitor)
      outsideClickLocalMonitor = nil
    }
    if let monitor = outsideClickGlobalMonitor {
      NSEvent.removeMonitor(monitor)
      outsideClickGlobalMonitor = nil
    }
  }

  private func setupViews() {
    container.frame = NSRect(x: 0, y: 0, width: Metrics.minWidth, height: 300)
    container.autoresizingMask = [.width, .height]
    container.autoresizesSubviews = true
    container.configureCompletionAppearance(cornerRadius: 16)

    // Table view
    completionColumn.resizingMask = .autoresizingMask
    tableView.addTableColumn(completionColumn)
    tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    tableView.headerView = nil
    tableView.rowHeight = Metrics.rowHeight
    tableView.intercellSpacing = .zero
    tableView.backgroundColor = .clear
    tableView.delegate = self
    tableView.dataSource = self
    tableView.selectionHighlightStyle = .none
    tableView.allowsEmptySelection = false
    tableView.focusRingType = .none
    tableView.style = .plain
    tableView.gridStyleMask = []
    tableView.frame = NSRect(x: 0, y: 0, width: Metrics.minWidth, height: Metrics.minListHeight)

    scrollView.documentView = tableView
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.borderType = .noBorder
    scrollView.drawsBackground = false
    scrollView.backgroundColor = .clear
    scrollView.automaticallyAdjustsContentInsets = false

    // Divider
    divider.boxType = .custom
    divider.borderWidth = 0
    divider.fillColor = NSColor(calibratedWhite: 0.0, alpha: 0.06)

    // Documentation area
    docScrollView.hasVerticalScroller = true
    docScrollView.hasHorizontalScroller = false
    docScrollView.autohidesScrollers = true
    docScrollView.borderType = .noBorder
    docScrollView.drawsBackground = false
    docScrollView.backgroundColor = .clear

    container.contentRoot.addSubview(scrollView)
    container.contentRoot.addSubview(divider)
    container.contentRoot.addSubview(docScrollView)

    contentView = container
    layoutPanelContent(
      width: Metrics.minWidth,
      listHeight: Metrics.minListHeight,
      documentationHeight: Metrics.minDocumentationHeight
    )
  }

  override var canBecomeKey: Bool { true }

  override func close() {
    if isKeyWindow { progressHandler?(.cancel) }
    removeOutsideClickMonitors()
    super.close()
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == keyCodeDownArrow || event.keyCode == keyCodeUpArrow {

      let row = tableView.selectedRow
      let newRow: Int
      if event.keyCode == keyCodeDownArrow {
        newRow = min(row + 1, tableView.numberOfRows - 1)
      } else {
        newRow = max(row - 1, 0)
      }
      tableView.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
      tableView.scrollRowToVisible(newRow)

    } else if event.keyCode == keyCodeReturn {

      let row = tableView.selectedRow
      if row >= 0 && row < completions.items.count {
        let item = completions.items[row]
        progressHandler?(.completion(item.insertText, item.insertRange))
      } else {
        progressHandler?(.cancel)
      }

    } else if event.keyCode == keyCodeESC {

      progressHandler?(.cancel)

    } else if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {

      progressHandler?(.input(event))
      close()

    } else {

      progressHandler?(.input(event))

    }
  }

  func updatePreferredMaximumWidth(for editorWidth: CGFloat) {
    preferredMaximumWidth = max(
      Metrics.minWidth,
      min(editorWidth * Metrics.widthFractionOfEditor, Metrics.maxWidth)
    )
  }

  // MARK: Set completions

  func set(completions: Completions,
           anchoredAt screenRect: CGRect? = nil,
           handler: @escaping (CompletionProgress) -> Void)
  {
    var completions = completions
    completions.items.sort()

    self.completions     = completions
    self.progressHandler = handler
    self.anchorRect      = screenRect

    selectedItemID = if let selected = (completions.items.first{ $0.selected }) { selected.id }
                     else { completions.items.first?.id }

    if completions.items.isEmpty {
      close()
    } else {
      resizePanel(anchoredAt: screenRect)
      tableView.reloadData()

      if let selectedID = selectedItemID,
         let index = completions.items.firstIndex(where: { $0.id == selectedID })
      {
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.scrollRowToVisible(index)
      }

      if !isVisible {
        orderFront(nil)
      }
      installOutsideClickMonitors()

      updateDocumentation()

      Task { @MainActor in
        for (offset, item) in self.completions.items.enumerated() {
          if let refinedItem = try? await item.refine() {
            self.completions.items[offset] = refinedItem
          }
        }
        self.resizePanel(anchoredAt: self.anchorRect)
        tableView.reloadData()
      }
    }
  }

  // MARK: NSTableViewDataSource

  func numberOfRows(in tableView: NSTableView) -> Int {
    completions.items.count
  }

  // MARK: NSTableViewDelegate

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard row < completions.items.count else { return nil }

    let cell = tableView.makeView(withIdentifier: CompletionCellView.identifier, owner: self)
                as? CompletionCellView
               ?? CompletionCellView()
    cell.identifier = CompletionCellView.identifier

    let item = completions.items[row]
    let isSelected = item.id == selectedItemID
    let info = displayInfoProvider?(item.id)
    cell.configure(with: item, isSelected: isSelected, displayInfo: info)
    return cell
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    let row = tableView.selectedRow
    if row >= 0 && row < completions.items.count {
      selectedItemID = completions.items[row].id
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    refreshVisibleRowSelection()
    CATransaction.commit()
    updateDocumentation()
  }

  private func refreshVisibleRowSelection() {
    tableView.enumerateAvailableRowViews { [weak self] rowView, row in
      guard let self,
            row < self.completions.items.count,
            let cell = rowView.view(atColumn: 0) as? CompletionCellView
      else { return }
      cell.setSelected(self.completions.items[row].id == self.selectedItemID)
    }
  }

  private func updateDocumentation() {
    guard let selectedID = selectedItemID,
          let item = completions.items.first(where: { $0.id == selectedID })
    else { return }

    if let info = displayInfoProvider?(item.id) {
      installNativeDocumentationViewIfNeeded()
      docNativeView.apply(info: info)
    } else {
      installHostingDocumentationView(for: item)
    }
  }

  private func installNativeDocumentationViewIfNeeded() {
    guard docScrollView.documentView !== docNativeView else { return }
    docHostingView?.removeFromSuperview()
    docHostingView = nil
    docNativeView.frame = NSRect(
      x: 0,
      y: 0,
      width: max(docScrollView.contentSize.width, container.bounds.width),
      height: currentDocumentationHeight
    )
    docScrollView.documentView = docNativeView
  }

  private func installHostingDocumentationView(for item: Completions.Completion) {
    let docView = AnyView(
      HStack(alignment: .top) {
        AnyView(item.documentationView)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
    )

    if let hosting = docHostingView, docScrollView.documentView === hosting {
      hosting.rootView = docView
    } else {
      let hosting = NSHostingView(rootView: docView)
      hosting.translatesAutoresizingMaskIntoConstraints = false
      hosting.frame = NSRect(
        x: 0,
        y: 0,
        width: max(docScrollView.contentSize.width, container.bounds.width),
        height: currentDocumentationHeight
      )
      docScrollView.documentView = hosting
      docHostingView = hosting
    }
  }

  private func resizePanel(anchoredAt screenRect: CGRect?) {
    let rowCount = max(completions.items.count, 1)
    let insetsHeight = Metrics.listVerticalInset * 2
    let availableForRows = Metrics.maxListHeight - insetsHeight
    let maxVisibleRows = max(1, Int(floor(availableForRows / Metrics.rowHeight)))
    let visibleRows = min(rowCount, maxVisibleRows)
    let listHeight = CGFloat(visibleRows) * Metrics.rowHeight + insetsHeight
    let panelWidth = desiredPanelWidth(anchoredAt: screenRect)
    let documentationHeight = desiredDocumentationHeight(for: panelWidth)
    currentDocumentationHeight = documentationHeight
    let panelHeight = listHeight + 1 + documentationHeight
    let panelSize = CGSize(width: panelWidth, height: panelHeight)

    setContentSize(panelSize)
    container.frame = NSRect(origin: .zero, size: panelSize)
    layoutPanelContent(width: panelWidth, listHeight: listHeight, documentationHeight: documentationHeight)

    if let screenRect {
      setFrameTopLeftPoint(panelOrigin(for: screenRect, size: panelSize))
    }
  }

  private func layoutPanelContent(width: CGFloat, listHeight: CGFloat, documentationHeight: CGFloat) {
    let dividerHeight: CGFloat = 1
    let listOriginY = documentationHeight + dividerHeight

    docScrollView.frame = NSRect(
      x: 0,
      y: 0,
      width: width,
      height: documentationHeight
    )
    divider.frame = NSRect(
      x: 0,
      y: documentationHeight,
      width: width,
      height: dividerHeight
    )
    let scrollHeight = max(listHeight - Metrics.listVerticalInset * 2, Metrics.rowHeight)
    scrollView.frame = NSRect(
      x: 0,
      y: listOriginY + Metrics.listVerticalInset,
      width: width,
      height: scrollHeight
    )

    let tableWidth = max(scrollView.contentSize.width, width)
    completionColumn.width = tableWidth
    let totalContentHeight = max(
      CGFloat(completions.items.count) * Metrics.rowHeight,
      scrollHeight
    )
    tableView.frame = NSRect(x: 0, y: 0, width: tableWidth, height: totalContentHeight)

    if docScrollView.documentView === docNativeView {
      docNativeView.frame = NSRect(
        x: 0,
        y: 0,
        width: max(docScrollView.contentSize.width, width),
        height: documentationHeight
      )
    }

    if let docHostingView {
      docHostingView.frame = NSRect(
        x: 0,
        y: 0,
        width: max(docScrollView.contentSize.width, width),
        height: documentationHeight
      )
    }
  }

  private func desiredPanelWidth(anchoredAt screenRect: CGRect?) -> CGFloat {
    let measuredWidth = max(measuredCompletionWidth(), measuredDocumentationWidth())
    let availableWidth = maximumAllowedWidth(anchoredAt: screenRect)
    let maximumWidth = max(
      Metrics.minWidth,
      min(availableWidth, preferredMaximumWidth)
    )
    return min(
      max(measuredWidth, Metrics.minWidth),
      maximumWidth
    )
  }

  private func measuredCompletionWidth() -> CGFloat {
    let measuredRows = completions.items.indices.compactMap { row in
      let view = tableView(tableView, viewFor: completionColumn, row: row)
      view?.layoutSubtreeIfNeeded()
      return view?.fittingSize.width
    }

    let widestMeasuredRow = measuredRows.max() ?? 0
    let widestFallbackText = completions.items.reduce(CGFloat.zero) { partial, item in
      max(partial, estimatedTextWidth(for: item))
    }

    return max(widestMeasuredRow, widestFallbackText) + Metrics.scrollbarAllowance
  }

  private func measuredDocumentationWidth() -> CGFloat {
    guard let selectedID = selectedItemID,
          let item = completions.items.first(where: { $0.id == selectedID })
    else {
      return Metrics.minWidth
    }

    let hosting = NSHostingView(
      rootView: AnyView(
        AnyView(item.documentationView)
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
      )
    )
    hosting.layoutSubtreeIfNeeded()
    return max(hosting.fittingSize.width, Metrics.minWidth)
  }

  private func desiredDocumentationHeight(for width: CGFloat) -> CGFloat {
    guard let selectedID = selectedItemID,
          let item = completions.items.first(where: { $0.id == selectedID })
    else {
      return Metrics.minDocumentationHeight
    }

    let height: CGFloat
    if let info = displayInfoProvider?(item.id) {
      height = docNativeView.requiredHeight(for: info, width: width)
    } else {
      let hosting = NSHostingView(
        rootView: AnyView(
          HStack(alignment: .top) {
            AnyView(item.documentationView)
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .frame(width: width, alignment: .topLeading)
        )
      )
      hosting.frame = NSRect(x: 0, y: 0, width: width, height: Metrics.minDocumentationHeight)
      hosting.layoutSubtreeIfNeeded()
      height = hosting.fittingSize.height
    }

    return min(max(height, Metrics.minDocumentationHeight), Metrics.maxDocumentationHeight)
  }

  private func estimatedTextWidth(for item: Completions.Completion) -> CGFloat {
    let primaryText = item.filterText.isEmpty ? item.insertText : item.filterText
    let fallbackText = item.insertText == primaryText ? "" : item.insertText
    let primaryWidth = primaryText.size(
      withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)]
    ).width
    let fallbackWidth = fallbackText.size(
      withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)]
    ).width
    return primaryWidth + fallbackWidth + Metrics.contentPadding
  }

  private func maximumAllowedWidth(anchoredAt screenRect: CGRect?) -> CGFloat {
    guard let screenRect else { return Metrics.maxWidth }
    guard let visibleFrame = visibleFrame(containing: screenRect) else { return Metrics.maxWidth }

    let spaceToRight = visibleFrame.maxX - screenRect.minX - Metrics.screenInset
    let totalVisibleWidth = visibleFrame.width - (Metrics.screenInset * 2)
    return max(Metrics.minWidth, min(spaceToRight, totalVisibleWidth))
  }

  private func panelOrigin(for screenRect: CGRect, size: CGSize) -> CGPoint {
    guard let visibleFrame = visibleFrame(containing: screenRect) else {
      return CGPoint(x: screenRect.minX, y: screenRect.minY)
    }

    let maxX = visibleFrame.maxX - size.width - Metrics.screenInset
    let clampedX = min(max(screenRect.minX, visibleFrame.minX + Metrics.screenInset), maxX)
    return CGPoint(x: clampedX, y: screenRect.minY)
  }

  private func visibleFrame(containing screenRect: CGRect) -> CGRect? {
    NSScreen.screens.first(where: { screen in
      screen.visibleFrame.intersects(screenRect) || screen.visibleFrame.contains(screenRect.origin)
    })?.visibleFrame
  }

  func moveSelection(by offset: Int) {
    guard !completions.items.isEmpty else { return }

    let currentRow = max(tableView.selectedRow, 0)
    let newRow = min(max(currentRow + offset, 0), completions.items.count - 1)
    tableView.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
    tableView.scrollRowToVisible(newRow)
  }

  func commitSelection() {
    let row = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
    guard row < completions.items.count else {
      progressHandler?(.cancel)
      close()
      return
    }

    let item = completions.items[row]
    progressHandler?(.completion(item.insertText, item.insertRange))
  }

  func cancelSelection() {
    progressHandler?(.cancel)
    close()
  }
}


// MARK: -
// MARK: CodeView completion extensions

extension CodeView {

  @MainActor
  func show(completions: Completions, for range: NSRange) {
    completionPanel.updatePreferredMaximumWidth(for: bounds.width)

    if let sqlService = optLanguageService as? SQLAutocompleteLanguageService {
      completionPanel.displayInfoProvider = { [weak sqlService] id in
        sqlService?.displayInfo(forId: id)
      }
    } else {
      completionPanel.displayInfoProvider = nil
    }

    completionPanel.set(completions: completions,
                        anchoredAt: firstRect(forCharacterRange: range, actualRange: nil)) {
      [weak self] completionProgress in

      switch completionProgress {

      case .cancel:
        self?.completionPanel.progressHandler = nil
        self?.completionPanel.close()

      case .completion(let insertText, _):
        self?.completionPanel.progressHandler = nil
        self?.completionPanel.close()
        let replacement = self?.currentIdentifierRange() ?? range
        self?.insertText(insertText, replacementRange: replacement)

      case .input(let event):
        self?.interpretKeyEvents([event])
      }
    }
  }

  func computeAndShowCompletions(at location: Int, reason: CompletionTriggerReason? = nil) async throws {
    guard let languageService = optLanguageService else { return }
    nonisolated(unsafe) let langService = languageService

    do {
      // Debounce a single frame so rapid typing doesn't kick off a compute
      // that'll be cancelled by the next keystroke anyway.
      try await Task.sleep(for: .milliseconds(16))
      try Task.checkCancellation()

      let currentText = string
      if let sqlService = languageService as? SQLAutocompleteLanguageService {
        sqlService.updateDocumentTextImmediately(currentText)
      }
      let resolvedReason = reason ?? (completionPanel.isVisible ? .incomplete : .standard),
          completions    = try await langService.completions(at: location, reason: resolvedReason)
      try Task.checkCancellation()
      show(completions: completions, for: rangeForUserCompletion)
    } catch let error { logger.trace("Completion action failed: \(error.localizedDescription)") }
  }

  func completionAction() {
    completionTask?.cancel()

    if completionPanel.isVisible {
      completionPanel.close()
    } else {
      completionTask = Task {
        try await computeAndShowCompletions(at: selectedRange().location)
      }
    }
  }

  func considerCompletionFor(range: NSRange) {
    guard let codeStorageDelegate = optCodeStorage?.delegate as? CodeStorageDelegate else { return }

    completionTask?.cancel()

    if let triggerCharacter = completionTriggerCharacterAtInsertionPoint(),
       codeStorageDelegate.processingOneCharacterAddition
    {
      completionTask = Task {
        try await computeAndShowCompletions(at: selectedRange().location, reason: .character(triggerCharacter))
      }

    } else if range.length > 0 && codeStorageDelegate.processingOneCharacterAddition
                && lastTypedCharacterIsWordCharacter() {

      completionTask = Task {
        if range.length < 3 && !completionPanel.isVisible { try await Task.sleep(for: .seconds(0.2)) }
        try await computeAndShowCompletions(at: range.max)
      }

    } else if completionPanel.isVisible {
      if range.length > 0 {
        completionTask = Task {
          try await computeAndShowCompletions(at: range.max, reason: .incomplete)
        }
      } else {
        completionPanel.close()
      }
    }
  }

  /// Walks back from the cursor over identifier characters (letters, digits, `_`) and
  /// returns the range of the partial identifier currently being typed. Used as the
  /// replacement range when committing a completion so we never over-replace across
  /// word boundaries like `.` or whitespace.
  private func currentIdentifierRange() -> NSRange {
    let cursor = selectedRange().location
    let nsString = string as NSString
    let safeCursor = max(0, min(cursor, nsString.length))
    var start = safeCursor
    while start > 0 {
      let scalar = nsString.character(at: start - 1)
      guard let unicode = UnicodeScalar(UInt32(scalar)) else { break }
      let isIdentifier = scalar == 95 || scalar == 36 || CharacterSet.alphanumerics.contains(unicode)
      if !isIdentifier { break }
      start -= 1
    }
    return NSRange(location: start, length: safeCursor - start)
  }

  private func lastTypedCharacterIsWordCharacter() -> Bool {
    let cursor = selectedRange().location
    guard cursor > 0, cursor <= string.utf16.count else { return false }
    let nsString = string as NSString
    let previousCharacter = nsString.substring(with: NSRange(location: cursor - 1, length: 1))
    guard let character = previousCharacter.first else { return false }
    return character.isLetter || character.isNumber || character == "_"
  }

  private func completionTriggerCharacterAtInsertionPoint() -> Character? {
    guard let languageService = optLanguageService else { return nil }

    let cursorLocation = selectedRange().location
    guard cursorLocation > 0, cursorLocation <= string.utf16.count else { return nil }

    let previousCharacterRange = NSRange(location: cursorLocation - 1, length: 1)
    let previousCharacter = (string as NSString).substring(with: previousCharacterRange)

    guard previousCharacter.count == 1,
          let character = previousCharacter.first,
          languageService.completionTriggerCharacters.value.contains(character)
    else {
      return nil
    }

    return character
  }
}


// MARK: -
// MARK: Completion container

final class CompletionContainerView: NSView {

  let contentRoot = NSView()

  func configureCompletionAppearance(cornerRadius: CGFloat) {
    wantsLayer = true
    layer?.cornerRadius = cornerRadius
    layer?.cornerCurve = .continuous
    layer?.borderWidth = 0.5
    layer?.masksToBounds = true

    contentRoot.frame = bounds
    contentRoot.autoresizingMask = [.width, .height]
    contentRoot.autoresizesSubviews = true
    contentRoot.wantsLayer = true
    addSubview(contentRoot)

    applyAppearanceColors()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    applyAppearanceColors()
  }

  private func applyAppearanceColors() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      let isDark = self.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      self.layer?.backgroundColor = isDark
        ? NSColor(calibratedWhite: 0.14, alpha: 1.0).cgColor
        : NSColor.white.cgColor
      self.layer?.borderColor = isDark
        ? NSColor(calibratedWhite: 1.0, alpha: 0.14).cgColor
        : NSColor(calibratedWhite: 0.0, alpha: 0.15).cgColor
    }
  }

  private static func roundedMaskImage(cornerRadius: CGFloat) -> NSImage {
    let inset = cornerRadius + 2
    let size = NSSize(width: inset * 2 + 1, height: inset * 2 + 1)
    let image = NSImage(size: size, flipped: false) { rect in
      NSColor.black.setFill()
      NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
      return true
    }
    image.capInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
    image.resizingMode = .stretch
    return image
  }
}
