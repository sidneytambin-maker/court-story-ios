import SwiftUI

struct CourtSportChoiceFields: View {
    @Binding var selection: CourtSportSelection
    var body: some View {
        Picker("Sport", selection: $selection.sport) {
            ForEach(CourtSport.allCases) { Text($0.rawValue).tag($0) }
        }.accessibilityIdentifier("courtSportPicker")
        if selection.sport == .custom {
            TextField("Custom sport name", text: $selection.customName)
                .accessibilityIdentifier("customSportName")
        }
    }
}

struct CourtAccessFields: View {
    var sport: CourtSport
    @Binding var access: CourtAccessSettings

    var body: some View {
        Section {
            Text(access.summary).accessibilityIdentifier("accessPreferenceSummary")
            ForEach(CourtAccessPreference.allCases) { preference in
                Toggle(preference.rawValue, isOn: Binding(get: { access.preferences.contains(preference) }, set: { enabled in
                    if enabled {
                        if preference == .sighted { access.preferences = [.sighted] }
                        else { access.preferences.remove(.sighted); access.preferences.insert(preference) }
                    } else { access.preferences.remove(preference) }
                })).accessibilityIdentifier("accessPreference_" + preference.rawValue)
            }
            if access.preferences.contains(.custom) { TextField("Custom access preference", text: $access.customDescription) }
        } header: { Text("Optional access preferences") } footer: {
            Text("Choose what is useful to you. These preferences do not limit features or verify a diagnosis. Your preferences never change another player's rules.")
        }
        if access.preferences.contains(.visuallyImpaired) {
            Section("Classification") {
                if sport == .tennis {
                    Picker("Visual classification", selection: $access.classification) {
                        Text("Not specified").tag("")
                        ForEach(["B1", "B2", "B3", "B4", "B5"], id: \.self) { Text($0).tag($0) }
                    }
                } else { TextField("Sport classification, optional", text: $access.classification) }
            }
        }
        Section("Personal adjustments") {
            if sport.allowsBouncePreference {
                Picker("Bounce allowance", selection: $access.bounceOverride) {
                    Text("Use selected sport and classification").tag(Optional<Int>.none)
                    ForEach(0...20, id: \.self) { Text("\($0)").tag(Optional($0)) }
                }.accessibilityIdentifier("courtBouncePicker")
                Text(access.allowedBounces(for: sport).map { "This player's allowance: \($0) bounces." }
                    ?? "No allowance inferred. Record the agreed adjustment for this event.")
            }
            TextField("Communication preferences", text: $access.communication, axis: .vertical)
            TextField("Learning and clear-step preferences", text: $access.learningSupport, axis: .vertical)
            TextField("Agreed rule adaptations", text: $access.ruleAdaptations, axis: .vertical)
            TextField("Equipment adaptations", text: $access.equipmentAdaptations, axis: .vertical)
            Toggle("Prefer haptic cues", isOn: $access.preferHaptics)
            Toggle("Prefer text cues", isOn: $access.preferText)
        }
    }
}

struct CourtRuleFields: View {
    var sport: CourtSport
    @Binding var rules: CourtScoringRules
    var doubles = false

    var body: some View {
        Section("Scoring rules") {
            if sport != .custom {
                let choices = CourtOfficialFormat.choices(for: sport, doubles: doubles)
                let current = CourtOfficialFormat.matching(rules, sport: sport, doubles: doubles)
                Picker("Official format", selection: Binding(get: { current?.id ?? "saved" }, set: { id in
                    if let format = choices.first(where: { $0.id == id }) { rules = format.rules }
                })) {
                    if current == nil { Text("Previously saved format").tag("saved") }
                    ForEach(choices) { Text($0.title).tag($0.id) }
                }.accessibilityIdentifier("courtOfficialFormat")
                Text(rules.formatSummary).accessibilityIdentifier("courtRulesSummary")
                Text(rules.reference).font(.footnote)
            } else {
                Picker("Scoring system", selection: $rules.system) {
                    Text("Rally points").tag(CourtPointSystem.rally)
                    Text("Side-out points").tag(CourtPointSystem.sideOut)
                }.onChange(of: rules.system) { _, system in
                    rules.customOverride = true
                    rules.service = system == .sideOut ? .sideOut : .rallyWinner
                }
                TextField("Game target", value: $rules.target, format: .number)
                    .accessibilityIdentifier("courtPointsTarget")
                Picker("Win by", selection: $rules.winBy) {
                    ForEach(1...10, id: \.self) { Text("\($0) points").tag($0) }
                }
                Toggle("Use a point cap", isOn: Binding(get: { rules.cap != nil }, set: { rules.cap = $0 ? max(rules.target, 30) : nil }))
                if rules.cap != nil {
                    TextField("Point cap", value: Binding(get: { rules.cap ?? rules.target }, set: { rules.cap = $0 }), format: .number)
                }
                Picker("Service", selection: $rules.service) {
                    ForEach(CourtServiceRule.allCases.filter { rules.system == .sideOut ? $0 == .sideOut : $0 != .games }) {
                        Text($0.rawValue).tag($0)
                    }
                }
                Toggle("Two servers per side in doubles", isOn: $rules.doublesTwoServers)
                Picker("Rounds needed to win", selection: $rules.roundsToWin) {
                    ForEach(1...9, id: \.self) { Text("\($0)").tag($0) }
                }
            }
            if let error = rules.validationMessage { Text(error).foregroundStyle(.red) }
        }
    }
}

struct CourtCoachCredentialsFields: View {
    @Binding var credentials: CourtCoachCredentials
    var body: some View {
        Section("Optional coaching profile") {
            TextField("Coaching level", text: $credentials.level)
            TextField("Qualifications", text: $credentials.qualifications, axis: .vertical)
            TextField("Experience", text: $credentials.experience, axis: .vertical)
            TextField("Audience", text: $credentials.audience)
            TextField("Specialisms", text: $credentials.specialisms)
            TextField("Coaching focus", text: $credentials.focus)
            TextField("Session goals", text: $credentials.sessionGoals, axis: .vertical)
            TextField("Organisation", text: $credentials.organisation)
            Toggle("Track qualification renewal", isOn: Binding(get: { credentials.renewalDate != nil }, set: { credentials.renewalDate = $0 ? Date() : nil }))
            if credentials.renewalDate != nil {
                #if os(watchOS)
                WatchDateField(title: "Renewal date", date: Binding(get: { credentials.renewalDate ?? Date() }, set: { credentials.renewalDate = $0 }))
                #else
                DatePicker("Renewal date", selection: Binding(get: { credentials.renewalDate ?? Date() }, set: { credentials.renewalDate = $0 }), displayedComponents: .date)
                #endif
            }
            TextField("Safeguarding training notes", text: $credentials.safeguardingNotes, axis: .vertical)
            Text("Private, self-reported information. Court Story does not verify qualifications.").font(.footnote)
        }
    }
}

struct CourtSetupDraft: Codable, Equatable {
    var step = 0
    var role: CourtRole = .player
    var sport = CourtSportSelection.tennis
    var player = PlayerProfile()
    var settings = AppSettings()
    var access = CourtAccessSettings()
    var coaching = CourtCoachCredentials()

    func completedPlayer() -> PlayerProfile {
        var person = player
        if person.name.isBlank { person.name = person.preferredName }
        var preferences = CourtSportPreferences(sport: sport, role: role)
        preferences.access = access
        var profile = CourtProfile()
        profile.sports = [preferences]; profile.selectedSportID = sport.id; profile.coaching = coaching
        person.court = profile
        person.playerMode = access.preferences.contains(.visuallyImpaired) ? .blindTennis : .standardTennis
        person.sightLevel = SightLevel.allCases.first { $0.label == access.classification } ?? .fullySighted
        person.bCategory = access.classification
        person.bounceAllowance = access.bounceOverride
        person.trackingMode = settings.trackingMode
        return person
    }

    static func restore(_ device: String) -> CourtSetupDraft {
        guard let bytes = UserDefaults.standard.data(forKey: "court.setupDraft." + device),
              let draft = try? JSONDecoder.tennisTracker.decode(Self.self, from: bytes), (0...3).contains(draft.step) else { return Self() }
        return draft
    }
    func persist(_ device: String) {
        guard let bytes = try? JSONEncoder.tennisTracker.encode(self) else { return }
        UserDefaults.standard.set(bytes, forKey: "court.setupDraft." + device)
    }
    static func clear(_ device: String) { UserDefaults.standard.removeObject(forKey: "court.setupDraft." + device) }
}
