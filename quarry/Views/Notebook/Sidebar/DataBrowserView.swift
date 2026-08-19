import SwiftUI

private enum DataBrowserTab: String, CaseIterable {
    case recommended = "Recommended"
    case warehouse = "Warehouse"
    case models = "Models"
}

struct DataBrowserView: View {
    let dataController: NotebookDataController

    @State private var selectedTab: DataBrowserTab = .recommended
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabPicker
            searchBar
            connectionList
            Spacer()
            addConnectionButton
        }
        .padding(.top, 50)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack {
            Text("Data Browser")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var tabPicker: some View {
        Picker("", selection: $selectedTab) {
            ForEach(DataBrowserTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
            TextField("Search...", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(8)
        .background(.quinary)
        .clipShape(.rect(cornerRadius: 8))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var connectionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(filteredConnections, id: \.persistentModelID) { connection in
                    connectionRow(connection)
                }

                if filteredConnections.isEmpty {
                    Text("No connections found")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private var filteredConnections: [Connection] {
        if searchText.isEmpty {
            return dataController.connections
        }
        return dataController.connections.filter {
            $0.name.localizedStandardContains(searchText)
        }
    }

    private func connectionRow(_ connection: Connection) -> some View {
        HStack(spacing: 8) {
            Image(connection.databaseType.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                    .font(.subheadline)
                    .lineLimit(1)
                if let env = connection.environment {
                    Text(env.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .clipShape(.rect(cornerRadius: 6))
    }

    private var addConnectionButton: some View {
        Button {
        } label: {
            HStack {
                Image(systemName: "plus")
                Text("Add Connection")
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding()
    }
}
