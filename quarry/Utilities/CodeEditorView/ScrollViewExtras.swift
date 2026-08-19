//
//  ScrollView.swift
//  
//
//  Created by Fauzaan on 27/11/2021.
//

import AppKit

// MARK: -
// MARK: AppKit version
extension NSScrollView {

  @MainActor
  var verticalScrollPosition: CGFloat {
    get { documentVisibleRect.origin.y }
    set {

      (documentView as? CodeView)?.textLayoutManager?.textViewportLayoutController.layoutViewport()

      let newOffset = max(0, min(newValue, (documentView?.bounds.height ?? 0) - contentSize.height))
      if abs(newOffset - documentVisibleRect.origin.y) > 0.0001 {
        contentView.scroll(to: CGPoint(x: documentVisibleRect.origin.x, y: newOffset))
      }

      // This is necessary as the floating subviews are otherwise *sometimes* not correctly re-positioned.
      reflectScrolledClipView(contentView)

    }
  }
}
