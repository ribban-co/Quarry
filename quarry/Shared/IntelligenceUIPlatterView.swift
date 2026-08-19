//
//  UIAI.swift
//  Quarry
//
//  Created by Fauzaan on 6/17/25.
//

//  IntelligenceUIPlatterView.swift
//
//  Created by Stephan Casas on 2/13/25.
//

import SwiftUI
import AppKit
import Combine

struct IntelligenceUIPlatterView: View {

  private var _cornerRadius: CGFloat? = nil

  private var _hasInteriorLight = true
  private var _hasExteriorLight = true

  private var _shimmerSubject: ShimmerSubject?

  private let contentView: () -> AnyView

  init<Content: View>(content: @escaping () -> Content = { EmptyView() }) {
    self.contentView = {.init(content())}
  }

  var body: some View {
    _IntelligenceUIPlatterView(
      _cornerRadius: self._cornerRadius,
      _hasInteriorLight: self._hasInteriorLight,
      _hasExteriorLight: self._hasExteriorLight,
      _shimmerSubject: self._shimmerSubject)
    .overlay(content: {
      self.contentView()
    })
  }

  // MARK: - Inner Private View

  struct _IntelligenceUIPlatterView: NSViewRepresentable {

    var _cornerRadius: CGFloat? = nil

    var _hasInteriorLight = true
    var _hasExteriorLight = true

    var _shimmerSubject: ShimmerSubject?

    // MARK: - View Factory

    func makeNSView(context: Context) -> some NSView {
      guard let platterViewClass = NSClassFromString(
        "_NSIntelligenceUIPlatterView"
      ) as? NSView.Type else {
        fatalError("Cannot load class _NSIntelligenceUIPlatterView")
      }

      let platterView = platterViewClass.init(frame: .zero)

      // Corner radius
      if let cornerRadius = _cornerRadius {
        platterView.setValue(cornerRadius, forKey: "cornerRadius")
      }

      // Fill light
      platterView.setValue(self._hasInteriorLight, forKey: "hasInteriorLight")

      // Exterior glow
      platterView.setValue(self._hasExteriorLight, forKey: "hasExteriorLight")

      // Wrapper wiew to retain shimmer subscription
      let repView = RepresentedView(frame: .zero)
      platterView.translatesAutoresizingMaskIntoConstraints = false
      repView.addSubview(platterView)

      NSLayoutConstraint.activate([
        platterView.leadingAnchor.constraint(equalTo: repView.leadingAnchor),
        platterView.trailingAnchor.constraint(equalTo: repView.trailingAnchor),
        platterView.topAnchor.constraint(equalTo: repView.topAnchor),
        platterView.bottomAnchor.constraint(equalTo: repView.bottomAnchor),
      ])

      // Subscribe to shimmer events
      if let subject = self._shimmerSubject {
        repView.subscribeShimmer(on: subject)
      }

      return repView
    }

    // MARK: - Represented Wrapper View

    class RepresentedView: NSView {

      var bag = Set<AnyCancellable>()

      func subscribeShimmer(on subject: ShimmerSubject) {
        subject.sink(receiveValue: { [unowned self] in
          self.subviews.first?.perform(NSSelectorFromString("shimmer"))
        }).store(in: &self.bag)
      }

    }

    // MARK: - Conformance

    func updateNSView(_ nsView: NSViewType, context: Context) { }

  }

  // MARK: - Declarative Setters

  /// The view's presentation is changed by modifying the visibility of its internal light feature.
  /// - Parameter option: A `Bool` value specifying the internal light visibility.
  func hasInteriorLight(_ option: Bool) -> Self {
    var copy = self
    copy._hasInteriorLight = option

    return copy
  }

  /// The view's presentation is changed by modifying the visibility of its external light/glow feature.
  /// - Parameter option: A `Bool` value specifying the external light/glow visibility.
  func hasExteriorLight(_ option: Bool) -> Self {
    var copy = self
    copy._hasExteriorLight = option

    return copy
  }

  /// The view draws its corners with the given radius value.
  /// - Parameter radius: The radius with which the view's corners should draw.
  func cornerRadius(_ radius: CGFloat) -> Self {
    var copy = self
    copy._cornerRadius = radius

    return copy
  }

  /// The view subscribes to invocations of an action wrapped by `@IntelligenceUIPlatterView.ShimmerAction` — animating a "shimmer" effect with each invocation.
  /// - Parameter action: The action to which the view should subscribe.
  func shimmerOn(_ action: ShimmerAction) -> Self {
    var copy = self
    copy._shimmerSubject = action._subject

    return copy
  }

  // MARK: - Actions Wrapper

  @propertyWrapper
  struct Action<T: ActionProtocol> {

    private var keypath: KeyPath<Self, T>

    init(_ action: WritableKeyPath<Self, T>) {
      self.keypath = action
    }

    var shimmer: ShimmerAction = .init()

    var wrappedValue: T {
      self[keyPath: self.keypath]
    }

  }

  protocol ActionProtocol { }

  // MARK: - Action: Shimmer

  typealias ShimmerSubject = PassthroughSubject<Void, Never>

  struct ShimmerAction: ActionProtocol {

    private var shimmerSubject = ShimmerSubject()

    func callAsFunction() {
      self.shimmerSubject.send()
    }

  }

}

// MARK: - Action Introspect

fileprivate extension IntelligenceUIPlatterView.ShimmerAction {

  var _subject: IntelligenceUIPlatterView.ShimmerSubject {
    self.shimmerSubject
  }

}

// MARK: - Previews

/// # Note
/// There's something wrong with the preview extent that causes the outer glow to clip. This doesn't happen at runtime.

nonisolated(unsafe) fileprivate let PreviewContent = { (_ action: @escaping () -> Void) in
  AnyView(RoundedRectangle(cornerRadius: 30)
    .foregroundStyle(.ultraThickMaterial)
    .padding(2)
    .overlay(content: {
      Button("Shimmer", action: action)
    }))
}

#Preview {

  @IntelligenceUIPlatterView.Action(\.shimmer) var shimmerAction

  IntelligenceUIPlatterView(content: {
    PreviewContent({ shimmerAction() })
  })
  .cornerRadius(30)
  .shimmerOn(shimmerAction)
  .padding()

}

#Preview {

  @IntelligenceUIPlatterView.Action(\.shimmer) var shimmerAction

  IntelligenceUIPlatterView(content: {
    PreviewContent({ shimmerAction() })
  })
  .cornerRadius(20)
  .hasInteriorLight(false)
  .shimmerOn(shimmerAction)
  .onTapGesture(perform: {
    shimmerAction()
  })
  .padding()

}

#Preview {

  @IntelligenceUIPlatterView.Action(\.shimmer) var shimmerAction

  IntelligenceUIPlatterView(content: {
    PreviewContent({ shimmerAction() })
  })
  .cornerRadius(30)
  .hasExteriorLight(false)
  .shimmerOn(shimmerAction)
  .onTapGesture(perform: {
    shimmerAction()
  })
  .padding()

}
