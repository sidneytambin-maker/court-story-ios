import SwiftUI

struct TennisTrainingFocusPicker: View {
    @Binding var focus: String
    @Binding var additionalFocus: [String]
    var sport: CourtSport = .tennis
    @State private var showingChoices = false

    private var summary: String { TennisActivityContext.names(TennisTrainingFocus.selections(focus: focus, additional: additionalFocus).filter(TennisTrainingFocus.isSpecific)).fallback("No focus selected") }
    var body: some View {
        #if os(watchOS)
        Button { showingChoices = true } label: { label }
            .accessibilityLabel("Training focus").accessibilityValue(summary)
            .accessibilityIdentifier("trainingFocusPicker")
            .accessibilityHint("Choose one or more areas to practise.")
            .sheet(isPresented: $showingChoices) {
                NavigationStack {
                    TennisTrainingFocusChoices(focus: $focus, additionalFocus: $additionalFocus, sport: sport)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingChoices = false } } }
                }
            }
        #else
        NavigationLink { TennisTrainingFocusSelectionScreen(focus: $focus, additionalFocus: $additionalFocus, sport: sport) } label: { label }
            .accessibilityLabel("Training focus").accessibilityValue(summary)
            .accessibilityIdentifier("trainingFocusPicker")
            .accessibilityHint("Choose one or more areas to practise.")
        #endif
    }
    private var label: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Training focus")
            Text(summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TennisTrainingFocusSelectionScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var focus: String
    @Binding var additionalFocus: [String]
    var sport: CourtSport = .tennis
    var body: some View {
        TennisTrainingFocusChoices(focus: $focus, additionalFocus: $additionalFocus, sport: sport)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

struct TennisTrainingFocusChoices: View {
    @Binding var focus: String
    @Binding var additionalFocus: [String]
    var sport: CourtSport = .tennis
    @State private var customFocus = ""

    private var options: [String] { sport == .tennis ? TennisTrainingFocus.allCases.map(\.rawValue) : sport.focuses }

    private var selected: Binding<[String]> {
        Binding { TennisTrainingFocus.selections(focus: focus, additional: additionalFocus).filter(TennisTrainingFocus.isSpecific) } set: { values in
            focus = values.first ?? ""
            additionalFocus = Array(values.dropFirst())
        }
    }
    var body: some View {
        TennisChoiceList {
            Button("No focus selected") { selected.wrappedValue = [] }
                .accessibilityAddTraits(selected.wrappedValue.isEmpty ? .isSelected : [])
                .accessibilityIdentifier("trainingFocusOption.none")
            ForEach(options, id: \.self) { option in
                TennisSelectionRow(name: option, id: option, selectedIDs: selected)
                    .accessibilityIdentifier("trainingFocusOption." + option)
            }
            Section("Custom focus") {
                ForEach(selected.wrappedValue.filter { !options.contains($0) }, id: \.self) { value in
                    TennisSelectionRow(name: value, id: value, selectedIDs: selected)
                }
                TextField("Custom training focus", text: $customFocus)
                Button("Add Custom Focus") {
                    let value = customFocus.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !selected.wrappedValue.contains(value) { selected.wrappedValue.append(value) }
                    customFocus = ""
                }.disabled(customFocus.isBlank)
            }
        }.navigationTitle("Training Focus")
    }
}
