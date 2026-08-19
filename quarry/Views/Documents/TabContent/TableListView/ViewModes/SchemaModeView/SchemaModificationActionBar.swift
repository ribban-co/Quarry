//
//  SchemaModificationActionBar.swift
//  Quarry
//
//  Action bar for schema modification mode with save/cancel/undo buttons
//

import SwiftUI

struct SchemaModificationActionBar: View {
    let columnCount: Int
    let hasModifications: Bool
    let modificationCount: Int
    let canUndo: Bool
    let onRefresh: () -> Void
    let onUndo: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            // Column count label
            Text("\(columnCount) Column\(columnCount == 1 ? "" : "s")")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()

            // Refresh button
            Button(action: onRefresh) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                    Text("Refresh")
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(colorScheme == .dark ? Color(.white).opacity(0.06) : Color(.gray).opacity(0.1))
            )
            .help("Refresh schema from database")

            if hasModifications {
                // Undo button (only visible when modifications exist)
                Button(action: onUndo) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 11))
                        Text("Undo")
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .disabled(!canUndo)
                .opacity(canUndo ? 1.0 : 0.5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colorScheme == .dark ? Color(.white).opacity(0.06) : Color(.gray).opacity(0.1))
                )
                .help("Undo last modification")

                // Cancel button
                Button(action: onCancel) {
                    HStack(spacing: 4) {
                        Text("Cancel")
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colorScheme == .dark ? Color(.white).opacity(0.06) : Color(.gray).opacity(0.1))
                )
                .help("Cancel all pending modifications")

                // Save changes button
                Button(action: onSave) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                        Text("Save Changes (\(modificationCount))")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor)
                )
                .help("Save \(modificationCount) pending modification\(modificationCount == 1 ? "" : "s")")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(colorScheme == .dark ? Color(.windowBackgroundColor) : Color(.controlBackgroundColor))
        )
        .overlay(
            Rectangle()
                .fill(Color(.separatorColor))
                .frame(height: 1),
            alignment: .top
        )
    }
}
