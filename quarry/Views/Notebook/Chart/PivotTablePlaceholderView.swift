import SwiftUI

struct PivotTablePlaceholderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tablecells")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("Pivot table coming soon")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
