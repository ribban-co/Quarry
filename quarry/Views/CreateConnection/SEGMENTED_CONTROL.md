# Native Segmented Control (Xcode Inspector-style)

Ready-to-use `NSViewRepresentable` wrapper around `NSSegmentedControl` that gets the Tahoe Liquid Glass capsule treatment — separated pill segments with rounded shapes, matching Xcode's Quick Help inspector.

## When to bring this back

Use for things like:

- Switching between **Fields** / **URI** input modes in `CreateConnection`
- Tabbed filter states on a list
- View-mode switchers (grid / list / columns)

## Key details

- `segmentStyle = .separated` → distinct pills with visible gaps
- `borderShape = .capsule` (macOS 26+ only) → each segment becomes a capsule/pill shape
- `controlSize = .large` → matches Xcode's generous padding
- `setLabel(_, forSegment:)` for text; swap to `setImage(_, forSegment:)` for SF Symbol icons

## Component code

Drop this into `CreateConnection.swift` (or move to `Shared/`):

```swift
import AppKit
import SwiftUI

struct NativeSegmentedControl: NSViewRepresentable {
    struct Segment {
        let label: String
    }

    @Binding var selection: Int
    let segments: [Segment]

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentCount = segments.count
        control.segmentStyle = .separated
        if #available(macOS 26.0, *) {
            control.borderShape = .capsule
        }
        control.trackingMode = .selectOne
        control.controlSize = .large
        control.target = context.coordinator
        control.action = #selector(Coordinator.segmentChanged(_:))

        for (index, segment) in segments.enumerated() {
            control.setLabel(segment.label, forSegment: index)
        }

        control.selectedSegment = selection
        return control
    }

    func updateNSView(_ nsView: NSSegmentedControl, context: Context) {
        if nsView.selectedSegment != selection {
            nsView.selectedSegment = selection
        }
    }

    final class Coordinator: NSObject {
        var selection: Binding<Int>

        init(selection: Binding<Int>) {
            self.selection = selection
        }

        @objc func segmentChanged(_ sender: NSSegmentedControl) {
            selection.wrappedValue = sender.selectedSegment
        }
    }
}
```

## Usage example

```swift
@State private var inputMode: Int = 0

NativeSegmentedControl(
    selection: $inputMode,
    segments: [
        .init(label: "Fields"),
        .init(label: "URI"),
        .init(label: "Advanced")
    ]
)
.frame(height: 28)
.padding(.horizontal, 26)
```

## Icon variant

Swap `Segment.label` for `Segment.symbol` and use `setImage`:

```swift
struct Segment {
    let symbol: String
}

// In makeNSView:
let image = NSImage(
    systemSymbolName: segment.symbol,
    accessibilityDescription: nil
)
control.setImage(image, forSegment: index)
```

## Why NSSegmentedControl instead of SwiftUI Picker

SwiftUI's `Picker` with `.segmented` style renders as the tight traditional segmented control (segments flush inside a single rounded rect). It does **not** expose `.separated` style with `.capsule` border shape.

Public AppKit `NSSegmentedControl.BorderShape` enum (macOS 26+):

```swift
@available(macOS 26.0, *)
public enum BorderShape: Int, @unchecked Sendable {
    case automatic = 0
    case capsule = 1
    case roundedRectangle = 2
    case circle = 3
}
```

Combining `segmentStyle = .separated` with `borderShape = .capsule` is what gives Xcode's Quick Help inspector look and can only be achieved through the AppKit control.
