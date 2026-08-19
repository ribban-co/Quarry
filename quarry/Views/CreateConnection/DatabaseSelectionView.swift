//
//  DatabaseSelectionView.swift
//  Quarry
//
//  Created by Fauzaan on 5/30/25.
//

import Foundation
import SwiftUI

struct DatabaseSelectionView: View {
    @Binding var selectedDatabaseType: DatabaseType?

    @Environment(\.dismiss) var dismiss
    @AppStorage("containerSyncEnabled") private var containerSyncEnabled = true

    var groupedDatabaseTypes: [(DatabaseCategory, [DatabaseType])] {
        let visible = DatabaseType.allCases.filter { $0 != .supabase }
        let grouped = Dictionary(grouping: visible) { $0.category }
        return DatabaseCategory.allCases.compactMap { category in
            guard let databaseTypes = grouped[category], !databaseTypes.isEmpty else { return nil }
            return (category, databaseTypes)
        }
    }

    var body: some View {
        contentWithFloatingHeader {
            Form {
                Section {
                    VStack(spacing: 6) {
                        HeaderAppIcon()
                            .padding(.bottom, 12)

                        Text("Connect Your Database")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Connect to your databases to browse tables, run queries, and use notebooks. Connection details stay on this Mac.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 16)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                }

                ForEach(groupedDatabaseTypes, id: \.0) { category, databaseTypes in
                    Section(category.rawValue) {
                        ForEach(databaseTypes, id: \.self) { databaseType in
                            DatabaseTypeRow(databaseType: databaseType) {
                                selectedDatabaseType = databaseType
                            }
                        }
                    }

                    if category == .platforms {
                        DockerDiscoverySection(isEnabled: $containerSyncEnabled)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func contentWithFloatingHeader<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(macOS 26.0, *) {
            content()
                .safeAreaBar(edge: .top, spacing: 0) {
                    floatingHeader
                }
                .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        } else {
            content()
                .safeAreaInset(edge: .top, spacing: 0) {
                    floatingHeader
                }
        }
    }

    private var floatingHeader: some View {
        HStack {
            Spacer()
            SheetChromeButton(systemImage: "xmark") {
                dismiss()
            }
        }
        .padding(.top, 12)
        .padding(.trailing, 12)
    }
}

private struct DockerDiscoverySection: View {
    @Binding var isEnabled: Bool

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image("docker")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Docker")
                        .foregroundStyle(.primary)

                    Text("When enabled, Quarry detects databases running in your local Docker containers and adds automatically.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)

            Toggle("Docker", isOn: $isEnabled)
        }
    }
}

private struct HeaderAppIcon: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.primaryButton.opacity(0.85),
                        Color.primaryButton
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 52, height: 52)
            .overlay(
                Image(systemName: "app.connected.to.app.below.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .shadow(color: Color.primaryButton.opacity(0.25), radius: 8, y: 3)
    }
}

private struct DatabaseTypeRow: View {
    let databaseType: DatabaseType
    let onTap: () -> Void

    private var isDisabled: Bool { databaseType.status == .comingSoon }

    var body: some View {
        HStack(spacing: 12) {
            Image(databaseType.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundStyle(databaseType.accentColor)

            Text(databaseType.displayName)
                .foregroundStyle(isDisabled ? .secondary : .primary)

            Spacer()

            statusBadge

            if !isDisabled {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            guard !isDisabled else { return }
            onTap()
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch databaseType.status {
        case .beta:
            Text("Beta")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.brand)
        case .comingSoon:
            Text("Soon")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }
}
