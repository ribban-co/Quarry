//
//  AppViewModel.swift
//  Quarry
//

import SwiftUI
import Observation

@MainActor @Observable
final class AppViewModel {

    private enum DefaultsKey {
        static let rightSidebarVisible = "rightSidebarVisible"
        static let rightSidebarWidth = "rightSidebarWidth"
    }

    // Persisted so the dock survives closing and reopening connection windows.
    // AppViewModel is created per window, so without this every new window
    // forgot the sidebar state.
    var isRightSidebarVisible = UserDefaults.standard.bool(forKey: DefaultsKey.rightSidebarVisible) {
        didSet {
            UserDefaults.standard.set(isRightSidebarVisible, forKey: DefaultsKey.rightSidebarVisible)
        }
    }

    var rightSidebarWidth: CGFloat = AppViewModel.storedRightSidebarWidth {
        didSet {
            UserDefaults.standard.set(rightSidebarWidth, forKey: DefaultsKey.rightSidebarWidth)
        }
    }

    private static var storedRightSidebarWidth: CGFloat {
        let stored = UserDefaults.standard.double(forKey: DefaultsKey.rightSidebarWidth)
        return stored > 0 ? stored : 350
    }
}
