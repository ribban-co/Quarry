//
//  Bundle+Version.swift
//  Quarry
//

import Foundation

extension Bundle {
    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
}
