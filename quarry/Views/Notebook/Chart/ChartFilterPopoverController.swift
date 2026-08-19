import AppKit
import SwiftUI

final class ChartFilterPopoverController: NSViewController {

    private let columns: [DatabaseSchemaInfo]
    private let existingFilter: ChartFilterCondition?
    private let onApply: (ChartFilterCondition) -> Void

    init(
        columns: [DatabaseSchemaInfo],
        existingFilter: ChartFilterCondition? = nil,
        onApply: @escaping (ChartFilterCondition) -> Void
    ) {
        self.columns = columns
        self.existingFilter = existingFilter
        self.onApply = onApply
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let content = ChartFilterPopoverView(
            columns: columns,
            existingFilter: existingFilter,
            onApply: onApply
        )
        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        self.view = hosting
    }
}

private struct ChartFilterPopoverView: View {
    let columns: [DatabaseSchemaInfo]
    let existingFilter: ChartFilterCondition?
    let onApply: (ChartFilterCondition) -> Void

    @State private var selectedField: String
    @State private var selectedOperator: ChartFilterCondition.ChartFilterOperator
    @State private var value: String
    @FocusState private var isValueFocused: Bool

    init(
        columns: [DatabaseSchemaInfo],
        existingFilter: ChartFilterCondition?,
        onApply: @escaping (ChartFilterCondition) -> Void
    ) {
        self.columns = columns
        self.existingFilter = existingFilter
        self.onApply = onApply
        self._selectedField = State(initialValue: existingFilter?.field ?? columns.first?.columnName ?? "")
        self._selectedOperator = State(initialValue: existingFilter?.filterOperator ?? .equals)
        self._value = State(initialValue: existingFilter?.value ?? "")
    }

    private var canApply: Bool {
        guard !selectedField.isEmpty else { return false }
        if selectedOperator.needsValue {
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Menu {
                ForEach(columns, id: \.columnName) { col in
                    Button(col.columnName) {
                        selectedField = col.columnName
                    }
                }
            } label: {
                HStack {
                    Text(selectedField.isEmpty ? "Select field" : selectedField)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    Image(systemName: "chevron.compact.down")
                        .scaleEffect(CGSize(width: 0.7, height: 1.5))
                }
            }
            .menuStyle(.button)
            .buttonStyle(FilterDropdownStyle())

            Menu {
                ForEach(ChartFilterCondition.ChartFilterOperator.allCases, id: \.self) { op in
                    Button(op.displayName) {
                        selectedOperator = op
                    }
                }
            } label: {
                HStack {
                    Text(selectedOperator.displayName)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.compact.down")
                        .scaleEffect(CGSize(width: 0.7, height: 1.5))
                }
            }
            .menuStyle(.button)
            .buttonStyle(FilterDropdownStyle())

            if selectedOperator.needsValue {
                TextField("Enter a value...", text: $value)
                    .textFieldStyle(FilterTextFieldStyle())
                    .focused($isValueFocused)
                    .onSubmit {
                        applyFilter()
                    }
            }

            HStack {
                Spacer()
                Button("Apply") {
                    applyFilter()
                }
                .buttonStyle(FilterSubmitButtonStyle())
                .disabled(!canApply)
            }
        }
        .padding(16)
        .frame(width: 260)
        .onAppear {
            isValueFocused = true
        }
    }

    private func applyFilter() {
        guard canApply else { return }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let filter = ChartFilterCondition(
            id: existingFilter?.id ?? UUID(),
            field: selectedField,
            filterOperator: selectedOperator,
            value: trimmedValue
        )
        onApply(filter)
    }
}
