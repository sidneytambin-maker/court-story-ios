import SwiftUI

struct TennisMatchConditionsFields: View {
    @Binding var match: MatchRecord

    var body: some View {
        Picker("Court surface", selection: Binding(get: { match.courtSurface == .indoor ? .notSpecified : match.courtSurface }, set: { value in
            if match.courtSurface == .indoor && match.environment.setting == .notRecorded { match.environment.setting = .indoors }
            match.courtSurface = value
        })) {
            ForEach(CourtSurface.allCases.filter { $0 != .indoor }) { Text($0.rawValue).tag($0) }
        }.accessibilityIdentifier("matchCourtSurface")
        Picker("Indoor or outdoor", selection: Binding(get: { match.effectiveCourtSetting }, set: { value in
            match.environment.setting = value
            if match.courtSurface == .indoor { match.courtSurface = .notSpecified }
        })) {
            ForEach(TennisCourtSetting.allCases) { Text($0.rawValue).tag($0) }
        }.accessibilityIdentifier("matchCourtSetting")
        Picker("Sound level", selection: $match.environment.noise) {
            ForEach(TennisNoiseLevel.allCases) { Text($0.rawValue).tag($0) }
        }.accessibilityIdentifier("matchSoundLevel")
        if match.effectiveCourtSetting == .outdoors {
            NavigationLink("Weather") { TennisWeatherChoices(selected: $match.environment.weather) }
                .accessibilityIdentifier("matchWeather")
                .accessibilityValue(TennisActivityContext.names(match.environment.weather.map(\.rawValue)).fallback("Not recorded"))
                .accessibilityHint("Choose all conditions that applied.")
        }
        TextField("Other conditions", text: $match.matchConditions)
            .accessibilityIdentifier("matchOtherConditions")
    }
}

private struct TennisWeatherChoices: View {
    @Binding var selected: [TennisWeather]
    var body: some View {
        TennisChoiceList {
            Button("Not recorded") { selected = [] }
                .accessibilityAddTraits(selected.isEmpty ? .isSelected : [])
            ForEach(TennisWeather.groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.values) { weather in
                        TennisSelectionRow(name: weather.rawValue, id: weather, selectedIDs: $selected)
                    }
                }
            }
        }.navigationTitle("Weather")
    }
}
