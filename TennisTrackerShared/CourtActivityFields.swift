import SwiftUI

struct CourtPlanFields: View {
    @Binding var plan: CourtSessionPlan
    var body: some View {
        TextField("Session objective", text: $plan.objective, axis: .vertical)
        TextField("Planned drills", text: $plan.drills, axis: .vertical)
        TextField("Equipment", text: $plan.equipment, axis: .vertical)
        TextField("Adaptations", text: $plan.adaptations, axis: .vertical)
        TextField("Success measures", text: $plan.successMeasure, axis: .vertical)
        TextField("Coach review", text: $plan.review, axis: .vertical)
    }
}

struct CourtSurfacePicker: View {
    let sport: CourtSport
    @Binding var selection: String
    private var options: [String] { sport.surfaces + (selection.isEmpty || sport.surfaces.contains(selection) ? [] : [selection]) }
    var body: some View {
        Picker("Surface", selection: $selection) {
            Text("Not recorded").tag("")
            ForEach(options, id: \.self) { Text($0).tag($0) }
        }.accessibilityIdentifier("courtSportSurface")
    }
}
