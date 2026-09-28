import SwiftUI

enum TennisOrderedSelection {
    static func moved<Value: Equatable>(_ value: Value, in values: [Value], forward: Bool) -> Value {
        guard let index = values.firstIndex(of: value), !values.isEmpty else { return value }
        return values[min(values.count - 1, max(0, index + (forward ? 1 : -1)))]
    }
}

struct OrderedChoicePicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let values: [Value]
    let label: (Value) -> String

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(values, id: \.self) { value in Text(label(value)).tag(value) }
        }
        .accessibilityLabel(title)
        .accessibilityValue(label(selection))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: selection = TennisOrderedSelection.moved(selection, in: values, forward: true)
            case .decrement: selection = TennisOrderedSelection.moved(selection, in: values, forward: false)
            @unknown default: break
            }
        }
    }
}

struct TennisSelectionRow<Value: Hashable>: View {
    let name: String
    let id: Value
    @Binding var selectedIDs: [Value]

    private var selected: Bool { selectedIDs.contains(id) }

    var body: some View {
        Button {
            selectedIDs = selected ? selectedIDs.filter { $0 != id } : selectedIDs + [id]
        } label: {
            HStack {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .frame(minWidth: 22)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .accessibilityHidden(true)
                Text(name).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? "" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
