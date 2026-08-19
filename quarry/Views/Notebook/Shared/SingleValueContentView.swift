import SwiftUI

struct SingleValueContentView: View {
    var viewModel: SingleValueBlockViewModel
    var title: String

    var body: some View {
        VStack(spacing: 4) {
            if viewModel.isLoadingSingleValue {
                ProgressView()
                    .controlSize(.small)
            } else if let error = viewModel.singleValueError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if let value = viewModel.singleValueResult {
                Text(value.abbreviatedString)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())

                let subtitle = viewModel.config?.label ?? title
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}
