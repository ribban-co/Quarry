//
//  TabsSettingsView.swift
//  Quarry
//

import SwiftUI

struct TabsSettingsView: View {
    @AppStorage("newTabBehavior") private var newTabBehavior = NewTabBehavior.sqlEditor.rawValue
    @AppStorage("openNewTabNextToCurrent") private var openNewTabNextToCurrent = true
    @AppStorage("showTabBarWithOneTab") private var showTabBarWithOneTab = false

    @AppStorage("rememberOpenTabs") private var rememberOpenTabs = true
    @AppStorage("restoreTabsOnReconnect") private var restoreTabsOnReconnect = true

    @AppStorage("showDatabaseIconInTab") private var showDatabaseIconInTab = true
    @AppStorage("showConnectionColorInTab") private var showConnectionColorInTab = true
    @AppStorage("maxTabTitleLength") private var maxTabTitleLength = 30

    var body: some View {
        Form {
            newTabBehaviorSection
            tabRestorationSection
            tabDisplaySection
        }
        .formStyle(.grouped)
    }

    private var newTabBehaviorSection: some View {
        Section("New Tab Behavior") {
            Picker("Cmd+T opens", selection: $newTabBehavior) {
                ForEach(NewTabBehavior.allCases, id: \.rawValue) { behavior in
                    Label(behavior.rawValue, systemImage: behavior.icon).tag(behavior.rawValue)
                }
            }

            Toggle("Open new tab next to current tab", isOn: $openNewTabNextToCurrent)
            Toggle("Show tab bar when only one tab is open", isOn: $showTabBarWithOneTab)
        }
    }

    private var tabRestorationSection: some View {
        Section("Tab Restoration") {
            Toggle("Remember open tabs per connection", isOn: $rememberOpenTabs)
            Toggle("Restore tabs when reopening connection", isOn: $restoreTabsOnReconnect)
        }
    }

    private var tabDisplaySection: some View {
        Section("Tab Display") {
            Toggle("Show database icon in tab", isOn: $showDatabaseIconInTab)
            Toggle("Show connection color indicator in tab", isOn: $showConnectionColorInTab)

            HStack {
                Text("Maximum tab title length")
                TextField("", value: $maxTabTitleLength, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                Text("characters")
            }
        }
    }
}

#Preview {
    TabsSettingsView()
        .frame(width: 500, height: 400)
}
