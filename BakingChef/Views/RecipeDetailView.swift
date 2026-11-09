import SwiftUI

struct RecipeDetailView: View {
    @Environment(AppModel.self) private var model
    let recipe: Recipe
    @State private var multiplier = 1.0

    var body: some View {
        TimelineView(.everyMinute) { context in
            let start = context.date
            List {
                if let summary = recipe.summary {
                    Section { Text(summary).font(.callout).foregroundStyle(.secondary) }
                }

                Section {
                    Stepper(value: $multiplier, in: 0.5...5, step: 0.5) {
                        HStack {
                            Label("Menge", systemImage: "scalemass")
                            Spacer()
                            Text(Format.multiplier(multiplier))
                                .font(.title3.bold())
                                .monospacedDigit()
                        }
                    }
                }

                Section(recipe.isScheduled ? "Zeitplan bei Start jetzt" : "Zutaten") {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { i, step in
                        RecipeStepRow(step: step, multiplier: multiplier,
                                      time: recipe.isScheduled ? startTime(of: i, from: start) : nil)
                    }
                    if recipe.isScheduled {
                        HStack {
                            Label("Fertig", systemImage: "flag.checkered")
                                .font(.headline)
                            Spacer()
                            Text(Format.dayTime(start.addingTimeInterval(TimeInterval(recipe.totalMinutes * 60)),
                                                relativeTo: start))
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .navigationTitle(recipe.name)
        .safeAreaInset(edge: .bottom) {
            if recipe.isScheduled {
                Button {
                    model.start(recipe, multiplier: multiplier)
                } label: {
                    Label("Jetzt starten", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
        }
    }

    private func startTime(of index: Int, from start: Date) -> Date {
        let minutes = recipe.steps.prefix(index).reduce(0) { $0 + $1.waitMinutes }
        return start.addingTimeInterval(TimeInterval(minutes * 60))
    }
}

private struct RecipeStepRow: View {
    let step: RecipeStep
    let multiplier: Double
    let time: Date?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(step.title).font(.body.weight(.medium))
                IngredientList(ingredients: step.ingredients, multiplier: multiplier)
                if step.waitMinutes > 0 {
                    Label("danach \(Format.duration(minutes: step.waitMinutes))", systemImage: "hourglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let time {
                Text(Format.dayTime(time)).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct IngredientList: View {
    let ingredients: [Ingredient]
    let multiplier: Double

    var body: some View {
        if !ingredients.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(ingredients, id: \.self) { ingredient in
                    HStack(spacing: 6) {
                        Text(ingredient.amountText(multiplier: multiplier))
                            .monospacedDigit()
                            .bold()
                        Text(ingredient.name)
                    }
                }
            }
            .font(.subheadline)
        }
    }
}
