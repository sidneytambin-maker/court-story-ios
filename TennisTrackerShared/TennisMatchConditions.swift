import Foundation

enum TennisNoiseLevel: String, Codable, CaseIterable, Identifiable {
    case notRecorded = "Not recorded", veryQuiet = "Very quiet", quiet = "Quiet"
    case moderate = "Moderate", loud = "Loud", veryLoud = "Very loud"
    var id: String { rawValue }
}

enum TennisCourtSetting: String, Codable, CaseIterable, Identifiable {
    case notRecorded = "Not recorded", indoors = "Indoors", outdoors = "Outdoors"
    var id: String { rawValue }
}

enum TennisWeather: String, Codable, CaseIterable, Identifiable {
    case sunny = "Sunny", cloudy = "Cloudy"
    case lightRain = "Light showers", rain = "Rain", windy = "Windy"
    case hot = "Hot", cold = "Cold", mixed = "Mixed conditions"
    case partlyCloudy = "Partly cloudy", overcast = "Overcast", mist = "Mist", fog = "Fog"
    case calm = "Calm", lightBreeze = "Light breeze", moderateBreeze = "Moderate breeze"
    case strongWind = "Strong wind", gusty = "Gusty wind"
    case drizzle = "Drizzle", heavyRain = "Heavy rain", intermittentRain = "Intermittent rain"
    case sleet = "Sleet", snow = "Snow", hail = "Hail", thunder = "Thunderstorms"
    case cool = "Cool", mild = "Mild", warm = "Warm", humid = "Humid", dry = "Dry", frost = "Frost"
    var id: String { rawValue }

    static var groups: [(title: String, values: [Self])] { [
        ("Sky", [.sunny, .partlyCloudy, .cloudy, .overcast, .mist, .fog]),
        ("Rain and snow", [.lightRain, .drizzle, .rain, .heavyRain, .intermittentRain, .sleet, .snow, .hail, .thunder]),
        ("Wind", [.calm, .lightBreeze, .moderateBreeze, .windy, .strongWind, .gusty]),
        ("Temperature and air", [.cold, .cool, .mild, .warm, .hot, .humid, .dry, .frost]),
        ("Variable conditions", [.mixed])
    ] }
}

struct TennisMatchEnvironment: Codable, Equatable {
    var noise: TennisNoiseLevel = .notRecorded
    var setting: TennisCourtSetting = .notRecorded
    var weather: [TennisWeather] = []
}

extension MatchRecord {
    var effectiveCourtSetting: TennisCourtSetting {
        environment.setting == .notRecorded && courtSurface == .indoor ? .indoors : environment.setting
    }

    var conditionsSummary: String {
        var parts: [String] = []
        if effectiveCourtSetting != .notRecorded { parts.append(effectiveCourtSetting.rawValue) }
        if courtSurface != .notSpecified && courtSurface != .indoor { parts.append("Court surface: " + courtSurface.rawValue) }
        if environment.noise != .notRecorded { parts.append("Sound: " + environment.noise.rawValue) }
        if effectiveCourtSetting == .outdoors && !environment.weather.isEmpty {
            parts.append("Weather: " + TennisActivityContext.names(environment.weather.map(\.rawValue)))
        }
        if !matchConditions.isBlank { parts.append(matchConditions) }
        return parts.isEmpty ? "" : parts.joined(separator: ". ") + "."
    }
}

enum TennisManualMatchEntry {
    static func maximumTeamSets(for format: MatchFormat) -> Int {
        format == .custom ? format.maximumSetsToEnter : format.setsNeededToWin
    }

    static func validationMessage(for match: MatchRecord) -> String? {
        if let error = TennisRecordedScore.validationMessage(for: match) { return error }
        guard !match.opponentName.isBlank else { return "Choose an opponent." }
        if match.matchType == .doubles && (match.partnerName.isBlank || match.opponent2Name.isBlank) {
            return "Choose your partner and both opponents."
        }
        let total = match.yourSetsWon + match.opponentSetsWon
        let limit = maximumTeamSets(for: match.matchFormat)
        if match.yourSetsWon < 0 || match.opponentSetsWon < 0 || match.yourSetsWon > limit || match.opponentSetsWon > limit {
            return "The sets won exceed the selected match format."
        }
        if total > match.matchFormat.maximumSetsToEnter { return "The set totals exceed the selected match format." }
        if total > 0 {
            if match.result == .win && match.yourSetsWon <= match.opponentSetsWon { return "For a win, your sets won must be higher." }
            if match.result == .loss && match.yourSetsWon >= match.opponentSetsWon { return "For a loss, your opponent's sets won must be higher." }
            if match.result == .draw && match.yourSetsWon != match.opponentSetsWon { return "For a draw, the set totals must be equal." }
        }
        return nil
    }
}
