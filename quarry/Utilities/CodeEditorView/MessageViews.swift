//
//  MessageViews.swift
//
//
//  Created by Fauzaan on 23/03/2021.
//
//  Defines the visuals that present messages, both inline and as popovers.

import AppKit

import LanguageSupport


// MARK: -
// MARK: Message category themes

extension Message {

  typealias Theme = (Message.Category) -> (colour: OSColor, icon: NSImage?)

  static func defaultTheme(for category: Message.Category) -> (colour: OSColor, icon: NSImage?) {
    switch category {
    case .live:
      return (colour: OSColor.green,
              icon: NSImage(systemSymbolName: "line.horizontal.3", accessibilityDescription: "Live"))
    case .error:
      return (colour: OSColor.red,
              icon: NSImage(systemSymbolName: "xmark.octagon.fill", accessibilityDescription: "Error"))
    case .hole:
      return (colour: OSColor.orange,
              icon: NSImage(systemSymbolName: "questionmark.circle.fill", accessibilityDescription: "Hole"))
    case .warning:
      return (colour: OSColor.yellow,
              icon: NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Warning"))
    case .informational:
      return (colour: OSColor.cyan,
              icon: NSImage(systemSymbolName: "info.circle.fill", accessibilityDescription: "Info"))
    }
  }
}


// MARK: -
// MARK: Message geometry

struct MessageGeometry {
  let lineWidth:   CGFloat
  let lineHeight:  CGFloat
  let popupWidth:  CGFloat
  let popupOffset: CGFloat
}

extension MessageGeometry {
  static let minimumInlineWidth = CGFloat(60)
  static let popupRightSideOffset = CGFloat(20)
}


// MARK: -
// MARK: Inline view

final class MessageInlineNSView: NSView {
  var messages: [Message]
  var theme: Message.Theme
  var background: NSColor
  var invalidated: Bool

  override var isFlipped: Bool { true }

  init(messages: [Message], theme: @escaping Message.Theme, background: NSColor, invalidated: Bool) {
    self.messages = messages
    self.theme = theme
    self.background = background
    self.invalidated = invalidated
    super.init(frame: .zero)
    wantsLayer = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func draw(_ dirtyRect: NSRect) {
    let categorized = messagesByCategory(messages)
    let categories = categorized.map { $0.key }
    guard let topCategory = categories.first,
          let topMessage = messages.first(where: { $0.category == topCategory }),
          !topMessage.summary.isEmpty
    else { return }

    // Cache theme lookups
    let themeResults = Dictionary(uniqueKeysWithValues: categories.map { ($0, theme($0)) })
    let colour: NSColor = invalidated ? .gray : (themeResults[topCategory]?.colour ?? .gray)
    let height = bounds.height

    // Draw background with left-rounded corners
    let cornerRadius: CGFloat = 5
    let path = NSBezierPath()
    let minXCorner = bounds.minX + cornerRadius
    let minYCorner = bounds.minY + cornerRadius
    let maxYCorner = bounds.maxY - cornerRadius

    path.move(to: CGPoint(x: bounds.maxX, y: bounds.minY))
    path.line(to: CGPoint(x: bounds.maxX, y: bounds.maxY))
    path.line(to: CGPoint(x: minXCorner, y: bounds.maxY))
    path.appendArc(withCenter: CGPoint(x: minXCorner, y: maxYCorner),
                   radius: cornerRadius, startAngle: 90, endAngle: 180)
    path.line(to: CGPoint(x: bounds.minX, y: minYCorner))
    path.appendArc(withCenter: CGPoint(x: minXCorner, y: minYCorner),
                   radius: cornerRadius, startAngle: 180, endAngle: 270)
    path.close()

    background.setFill()
    path.fill()

    // Category badge area
    var badgeX: CGFloat = 0
    let count = messages.count

    // Message count
    if count > 1 {
      let countStr = "\(count)" as NSString
      let countAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        .foregroundColor: NSColor.white
      ]
      let countSize = countStr.size(withAttributes: countAttrs)
      let countRect = CGRect(x: badgeX + 3, y: (height - countSize.height) / 2,
                             width: countSize.width, height: countSize.height)
      countStr.draw(in: countRect, withAttributes: countAttrs)
      badgeX += countSize.width + 6
    }

    // Category icons
    let iconSize: CGFloat = min(height - 2, 14)
    for category in categories {
      if let icon = themeResults[category]?.icon {
        let tintedIcon = icon.withSymbolConfiguration(.init(pointSize: iconSize, weight: .regular))
                         ?? icon
        let iconRect = CGRect(x: badgeX + 2, y: (height - iconSize) / 2,
                              width: iconSize, height: iconSize)
        tintedIcon.draw(in: iconRect)
        badgeX += iconSize + 4
      }
    }

    // Badge background (left portion)
    let badgePath = NSBezierPath()
    let badgeWidth = badgeX + 2
    badgePath.move(to: CGPoint(x: badgeWidth, y: bounds.minY))
    badgePath.line(to: CGPoint(x: badgeWidth, y: bounds.maxY))
    badgePath.line(to: CGPoint(x: minXCorner, y: bounds.maxY))
    badgePath.appendArc(withCenter: CGPoint(x: minXCorner, y: maxYCorner),
                        radius: cornerRadius, startAngle: 90, endAngle: 180)
    badgePath.line(to: CGPoint(x: bounds.minX, y: minYCorner))
    badgePath.appendArc(withCenter: CGPoint(x: minXCorner, y: minYCorner),
                        radius: cornerRadius, startAngle: 180, endAngle: 270)
    badgePath.close()
    colour.withAlphaComponent(0.5).setFill()
    badgePath.fill()

    // Message text area
    let textX = badgeWidth + 2
    let textRect = CGRect(x: textX + 5, y: 0,
                          width: bounds.width - textX - 10, height: height)
    colour.withAlphaComponent(0.5).setFill()
    NSBezierPath(rect: CGRect(x: textX, y: 0, width: bounds.width - textX, height: height)).fill()

    let textAttrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
      .foregroundColor: NSColor.white
    ]
    (topMessage.summary as NSString).draw(with: textRect,
                                           options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                           attributes: textAttrs)
  }
}


// MARK: -
// MARK: Popup view

final class MessagePopupNSView: NSView {
  let messages: [Message]
  let theme: Message.Theme
  var invalidated: Bool

  override var isFlipped: Bool { true }

  init(messages: [Message], theme: @escaping Message.Theme, invalidated: Bool) {
    self.messages = messages
    self.theme = theme
    self.invalidated = invalidated
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 10

    setupContent()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupContent() {
    let categories = messagesByCategory(messages)
    let stackView = NSStackView()
    stackView.orientation = .vertical
    stackView.spacing = 4
    stackView.translatesAutoresizingMaskIntoConstraints = false

    for (category, msgs) in categories {
      let categoryRow = makeCategoryRow(category: category, messages: msgs)
      stackView.addArrangedSubview(categoryRow)
    }

    addSubview(stackView)
    NSLayoutConstraint.activate([
      stackView.topAnchor.constraint(equalTo: topAnchor),
      stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
      stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
      stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  private func makeCategoryRow(category: Message.Category, messages: [Message]) -> NSView {
    let colour: NSColor = invalidated ? .gray : theme(category).colour

    let container = NSView()
    container.wantsLayer = true
    container.layer?.cornerRadius = 10
    container.layer?.masksToBounds = true

    // Icon column
    let iconView = NSImageView()
    iconView.translatesAutoresizingMaskIntoConstraints = false
    if let icon = theme(category).icon {
      iconView.image = icon
      iconView.contentTintColor = .white
    }
    iconView.setContentHuggingPriority(.required, for: .horizontal)

    let iconContainer = NSView()
    iconContainer.wantsLayer = true
    iconContainer.layer?.backgroundColor = colour.withAlphaComponent(0.5).cgColor
    iconContainer.translatesAutoresizingMaskIntoConstraints = false
    iconContainer.addSubview(iconView)

    NSLayoutConstraint.activate([
      iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
      iconView.topAnchor.constraint(equalTo: iconContainer.topAnchor, constant: 5),
      iconView.widthAnchor.constraint(equalToConstant: 16),
      iconView.heightAnchor.constraint(equalToConstant: 16),
      iconContainer.widthAnchor.constraint(equalToConstant: 26),
    ])

    // Messages column
    let messagesStack = NSStackView()
    messagesStack.orientation = .vertical
    messagesStack.alignment = .leading
    messagesStack.spacing = 6
    messagesStack.translatesAutoresizingMaskIntoConstraints = false
    messagesStack.edgeInsets = NSEdgeInsets(top: 3, left: 5, bottom: 3, right: 5)

    for msg in messages {
      let summaryField = NSTextField(labelWithString: msg.summary)
      summaryField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
      summaryField.textColor = .labelColor
      summaryField.lineBreakMode = .byWordWrapping
      summaryField.maximumNumberOfLines = 0
      messagesStack.addArrangedSubview(summaryField)

      if let description = msg.description {
        let descField = NSTextField(labelWithString: String(description.characters[...]))
        descField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        descField.textColor = .secondaryLabelColor
        descField.lineBreakMode = .byWordWrapping
        descField.maximumNumberOfLines = 0
        messagesStack.addArrangedSubview(descField)
      }
    }

    let messagesContainer = NSView()
    messagesContainer.wantsLayer = true
    messagesContainer.layer?.backgroundColor = colour.withAlphaComponent(0.3).cgColor
    messagesContainer.translatesAutoresizingMaskIntoConstraints = false
    messagesContainer.addSubview(messagesStack)

    NSLayoutConstraint.activate([
      messagesStack.topAnchor.constraint(equalTo: messagesContainer.topAnchor),
      messagesStack.leadingAnchor.constraint(equalTo: messagesContainer.leadingAnchor),
      messagesStack.trailingAnchor.constraint(equalTo: messagesContainer.trailingAnchor),
      messagesStack.bottomAnchor.constraint(equalTo: messagesContainer.bottomAnchor),
    ])

    // Assemble row
    container.addSubview(iconContainer)
    container.addSubview(messagesContainer)
    container.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      iconContainer.topAnchor.constraint(equalTo: container.topAnchor),
      iconContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      iconContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor),

      messagesContainer.topAnchor.constraint(equalTo: container.topAnchor),
      messagesContainer.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor),
      messagesContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      messagesContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])

    // Border and shadow
    container.layer?.borderColor = NSColor.separatorColor.cgColor
    container.layer?.borderWidth = 1
    container.shadow = NSShadow()
    container.layer?.shadowColor = NSColor.black.withAlphaComponent(0.2).cgColor
    container.layer?.shadowOpacity = 1
    container.layer?.shadowOffset = CGSize(width: 0, height: -1)
    container.layer?.shadowRadius = 2

    return container
  }
}


// MARK: -
// MARK: Combined container view

final class MessageContainerView: OSView {
  let messages: [Message]
  let theme: Message.Theme
  var background: NSColor
  let fontSize: CGFloat

  var geometry: MessageGeometry {
    didSet { updateLayout() }
  }

  var invalidated: Bool {
    didSet {
      inlineView.invalidated = invalidated
      inlineView.needsDisplay = true
      if let popup = popupView {
        popup.invalidated = invalidated
        popup.removeFromSuperview()
        popupView = nil
        if isExpanded { showPopup() }
      }
    }
  }

  var isExpanded: Bool = false {
    didSet {
      if isExpanded {
        inlineView.isHidden = true
        showPopup()
      } else {
        inlineView.isHidden = false
        popupView?.removeFromSuperview()
        popupView = nil
      }
    }
  }

  private let inlineView: MessageInlineNSView
  private var popupView: MessagePopupNSView?
  var topAnchorConstraint: NSLayoutConstraint?
  var rightAnchorConstraint: NSLayoutConstraint?

  override var isFlipped: Bool { true }

  init(messages: [Message],
       theme: @escaping Message.Theme,
       background: NSColor,
       geometry: MessageGeometry,
       fontSize: CGFloat)
  {
    self.messages = messages
    self.theme = theme
    self.background = background
    self.geometry = geometry
    self.fontSize = fontSize
    self.invalidated = false

    self.inlineView = MessageInlineNSView(messages: messages, theme: theme,
                                          background: background, invalidated: false)
    super.init(frame: .zero)

    wantsLayer = true
    translatesAutoresizingMaskIntoConstraints = false

    inlineView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(inlineView)

    NSLayoutConstraint.activate([
      inlineView.topAnchor.constraint(equalTo: topAnchor),
      inlineView.trailingAnchor.constraint(equalTo: trailingAnchor),
      inlineView.heightAnchor.constraint(equalToConstant: geometry.lineHeight),
      inlineView.widthAnchor.constraint(lessThanOrEqualToConstant: geometry.lineWidth),
      inlineView.widthAnchor.constraint(greaterThanOrEqualToConstant: MessageGeometry.minimumInlineWidth),
    ])

    let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
    addGestureRecognizer(clickGesture)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  @objc private func handleClick(_ sender: NSClickGestureRecognizer) {
    isExpanded.toggle()
  }

  private func showPopup() {
    let popup = MessagePopupNSView(messages: messages, theme: theme, invalidated: invalidated)
    popup.translatesAutoresizingMaskIntoConstraints = false
    addSubview(popup)

    NSLayoutConstraint.activate([
      popup.topAnchor.constraint(equalTo: topAnchor, constant: geometry.popupOffset),
      popup.leadingAnchor.constraint(equalTo: leadingAnchor),
      popup.widthAnchor.constraint(lessThanOrEqualToConstant: geometry.popupWidth),
    ])

    popupView = popup
  }

  private func updateLayout() {
    for constraint in inlineView.constraints {
      if constraint.firstAttribute == .height { constraint.constant = geometry.lineHeight }
      if constraint.firstAttribute == .width && constraint.relation == .lessThanOrEqual {
        constraint.constant = geometry.lineWidth
      }
    }
    if isExpanded {
      popupView?.removeFromSuperview()
      popupView = nil
      showPopup()
    }
  }
}
