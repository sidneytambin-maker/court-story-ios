import XCTest
@testable import TennisTracker

final class CourtSportTests: XCTestCase {
    func testCatalogueHasTenSportsAndCustomButNoFictionalExample() {
        XCTAssertEqual(CourtSport.allCases.count, 11)
        XCTAssertEqual(Set(CourtSport.allCases.map(\.id)).count, 11)
        XCTAssertFalse(CourtSport.allCases.contains { $0.rawValue == "Goalball" || $0.rawValue == "Football" })
        XCTAssertTrue(CourtSportSelection(sport: .custom, customName: "Goalball").isValid)
        XCTAssertFalse(CourtSportSelection(sport: .custom, customName: " Custom ").isValid)
        XCTAssertFalse(CourtSportSelection(sport: .custom, customName: "tennis").isValid)
    }

    func testEverySportHasSpecificFocusesAndValidDefaultRules() {
        for sport in CourtSport.allCases {
            XCTAssertGreaterThanOrEqual(sport.focuses.count, 10, sport.rawValue)
            XCTAssertEqual(Set(sport.focuses).count, sport.focuses.count)
            XCTAssertFalse(sport.surfaces.isEmpty)
            XCTAssertNil(CourtScoringRules.standard(for: sport).validationMessage, sport.rawValue)
            XCTAssertNil(CourtScoringRules.standard(for: sport, doubles: true).validationMessage, sport.rawValue)
        }
        XCTAssertTrue(CourtSport.pickleball.focuses.contains("Dinking"))
        XCTAssertFalse(CourtSport.tableTennis.surfaces.contains("Clay"))
    }

    func testNewProfilesDoNotDefaultToBlindTennis() {
        let person = PlayerProfile()
        XCTAssertEqual(person.playerMode, .standardTennis)
        XCTAssertEqual(person.court.selected.access.preferences, [.sighted])
        XCTAssertEqual(person.court.selected.access.allowedBounces(for: .tennis), 1)
    }

    func testAccessPreferencesAreSportSpecificAndSupportExplicitOverrides() {
        var access = CourtAccessSettings()
        XCTAssertEqual(access.allowedBounces(for: .tennis), 1)
        access.preferences = [.visuallyImpaired]; access.classification = "B1"
        XCTAssertEqual(access.allowedBounces(for: .tennis), 3)
        XCTAssertNil(access.allowedBounces(for: .badminton))
        XCTAssertNil(access.allowedBounces(for: .beachTennis))
        XCTAssertNil(access.allowedBounces(for: .tableTennis))
        XCTAssertEqual(access.summary, "Visually impaired")
        access.preferences.insert(.wheelchair)
        XCTAssertNil(access.allowedBounces(for: .tennis))
        access.bounceOverride = 5
        XCTAssertEqual(access.allowedBounces(for: .tennis), 5)
        XCTAssertNil(access.allowedBounces(for: .badminton))
        XCTAssertNil(access.validationMessage)
        access.bounceOverride = -1
        XCTAssertNotNil(access.validationMessage)
    }

    func testSportSwitchRetainsIndependentPreferencesAndRole() {
        var profile = CourtProfile()
        var tennis = profile.selected
        tennis.role = .coach; tennis.primaryGoal = "Serve accuracy"
        XCTAssertTrue(profile.update(tennis))
        XCTAssertTrue(profile.select(CourtSportSelection(sport: .badminton)))
        XCTAssertEqual(profile.selected.role, .player)
        XCTAssertEqual(profile.selected.rules.target, 21)
        XCTAssertTrue(profile.selected.primaryGoal.isEmpty)
        XCTAssertTrue(profile.select(.tennis))
        XCTAssertEqual(profile.selected, tennis)
        XCTAssertEqual(profile.sports.count, 2)
    }

    func testRecordCapturesAthleteRulesRatherThanCoachRules() throws {
        var coach = PlayerProfile(); coach.name = "Demo Coach"
        var athlete = PlayerProfile(); athlete.name = "Demo Athlete"
        var profile = CourtProfile(); profile.coachOwnerID = coach.id
        profile.sports[0].access.preferences = [.visuallyImpaired]
        profile.sports[0].access.classification = "B1"
        athlete.court = profile
        let record = CourtActivity(player: athlete, coachID: coach.id)
        XCTAssertEqual(record.access?.allowedBounces(for: .tennis), 3)
        XCTAssertEqual(coach.court.selected.access.allowedBounces(for: .tennis), 1)
        athlete.court.sports[0].access.bounceOverride = 6
        XCTAssertEqual(record.access?.allowedBounces(for: .tennis), 3)
        XCTAssertEqual(try JSONDecoder().decode(CourtActivity.self, from: JSONEncoder().encode(record)), record)
        XCTAssertNil(CourtActivity(player: coach, coachID: coach.id).enteredByCoachID)
    }

    func testLegacyMigrationPreservesAllIDsScoresAndOriginalTennisPreferences() throws {
        var data = AppData(); data.dataVersion = 11
        var person = PlayerProfile(); person.name = "Legacy Demo"; person.playerMode = .blindTennis
        person.sightLevel = .b1; person.bounceAllowance = 3
        data.players = [person]; data.selectedPlayerID = person.id; data.onboardingCompleted = true
        var match = MatchRecord(playerID: person.id); match.setScores = "6-4"; match.yourSetsWon = 1
        data.matches = [match]
        let original = data
        data.migrateCourtProfiles()
        XCTAssertEqual(data.dataVersion, 12)
        XCTAssertEqual(data.matches, original.matches)
        XCTAssertEqual(data.players[0].id, original.players[0].id)
        XCTAssertEqual(data.libraryID, original.libraryID)
        XCTAssertTrue(data.onboardingCompleted)
        XCTAssertEqual(data.court.deviceOwnerPlayerID, person.id)
        XCTAssertEqual(data.players[0].court.selected.access.allowedBounces(for: .tennis), 3)
        let once = data
        data.migrateCourtProfiles()
        XCTAssertEqual(data, once)
        XCTAssertEqual(try TennisBackup.decode(JSONEncoder.tennisTracker.encode(data)), data)
    }

    func testModeGatesAreConsistentAndDoNotMutateData() {
        for feature in [CourtFeature.observations, .media, .measuredDrills, .advancedStatistics, .coachExport] {
            XCTAssertFalse(feature.isAvailable(in: .basic))
        }
        XCTAssertTrue(CourtFeature.observations.isAvailable(in: .standard))
        XCTAssertFalse(CourtFeature.measuredDrills.isAvailable(in: .standard))
        XCTAssertTrue(CourtFeature.allCases.allSatisfy { $0.isAvailable(in: .power) })
    }

    func testMeasuredDrillsRejectInvalidDenominatorsAndKeepComparisonConditions() {
        let athlete = UUID(), coach = UUID()
        var drill = CourtMeasuredDrill(athleteID: athlete, coachID: coach, sport: .tennis)
        drill.name = "Target serves"
        XCTAssertNotNil(drill.validationMessage)
        drill.totalAttempts = 10; drill.successfulAttempts = 11
        XCTAssertNotNil(drill.validationMessage)
        drill.successfulAttempts = 7
        XCTAssertEqual(drill.proportion, 0.7)
        var changed = drill; changed.conditions = "Windy"
        XCTAssertFalse(drill.isComparable(to: changed))
        XCTAssertTrue(drill.isComparable(to: drill))
        drill.measurement = .infinity; drill.unit = "metres"
        XCTAssertNotNil(drill.validationMessage)
    }

    func testObservationBecomesLinkedPracticeWithoutChangingSource() {
        var observation = CourtObservation(athleteID: UUID(), coachID: UUID(), sport: .tennis)
        observation.happened = "Returns landed short"; observation.nextAction = "Aim beyond the service line"
        observation.focus = "Returning"
        let plan = observation.practicePlan(on: Date(timeIntervalSince1970: 1800000100))
        XCTAssertEqual(plan.playerID, observation.athleteID)
        XCTAssertEqual(plan.court.enteredByCoachID, observation.coachID)
        XCTAssertEqual(plan.court.plan?.sourceObservationID, observation.id)
        XCTAssertEqual(plan.court.plan?.objective, observation.nextAction)
        XCTAssertNil(plan.actualStart)
        XCTAssertNil(plan.actualFinish)
    }
}

@MainActor
final class CourtAttributionStoreTests: XCTestCase {
    func testCoachAthleteSelectionSportFilteringAndArchiveSurviveRelaunch() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: path) }
        let store = TennisStore(storeURL: path)
        var coach = PlayerProfile(); coach.name = "Demo Coach"; coach.court = CourtProfile()
        coach.court.sports[0].role = .coach
        XCTAssertTrue(store.completeOnboarding(player: coach, settings: AppSettings()))
        var athlete = PlayerProfile(); athlete.name = "Demo Athlete"; athlete.court = CourtProfile()
        athlete.court.coachOwnerID = coach.id
        athlete.court.sports[0].access.preferences = [.visuallyImpaired]
        athlete.court.sports[0].access.classification = "B1"
        XCTAssertTrue(store.saveCourtProfile(athlete))
        XCTAssertTrue(store.selectCourtAthlete(athlete.id))
        let draft = try XCTUnwrap(store.makeDefaultMatch())
        XCTAssertEqual(draft.playerID, athlete.id)
        XCTAssertEqual(draft.court.enteredByCoachID, coach.id)
        XCTAssertEqual(draft.allowedBounces, 3)
        XCTAssertFalse(store.data.court.mayMeasurePersonalWorkout(playerID: athlete.id))
        XCTAssertTrue(store.data.court.mayMeasurePersonalWorkout(playerID: coach.id))
        store.upsertMatch(draft)
        XCTAssertEqual(store.selectedMatches.count, 1)
        XCTAssertTrue(store.selectCourtSport(CourtSportSelection(sport: .badminton)))
        XCTAssertTrue(store.selectedMatches.isEmpty)
        XCTAssertEqual(store.data.matches.count, 1)
        XCTAssertTrue(store.archiveCourtPlayer(athlete.id, archived: true))
        XCTAssertTrue(store.roster.isEmpty)
        XCTAssertEqual(TennisStore(storeURL: path).data.matches[0], store.data.matches[0])
        XCTAssertNotNil(TennisStore(storeURL: path).data.players.first { $0.id == athlete.id }?.court.archivedAt)
        XCTAssertTrue(store.archiveCourtPlayer(athlete.id, archived: false))
        XCTAssertTrue(store.selectCourtSport(.tennis))
        XCTAssertEqual(store.roster.map(\.id), [athlete.id])
    }
}
