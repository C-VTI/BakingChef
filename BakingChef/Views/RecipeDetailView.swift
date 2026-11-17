import SwiftUI

struct RecipeDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private let initial: Recipe
    @State private var multiplier = 1.0
    @State private var showEditor = false

    init(recipe: Recipe) { initial = recipe }

    /// Always the latest saved version (the recipe can be edited while this view is open).
    private var recipe: Recipe { model.recipe(id: initial.id) ?? initial }

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
                            Label("Quantity", systemImage: "scalemass")
                            Spacer()
                            Text(Format.multiplier(multiplier))
                                .font(.title3.bold())
                                .monospacedDigit()
                        }
                    }
                }

                Section(recipe.isScheduled ? "Schedule if started now" : "Ingredients") {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { i, step in
                        RecipeStepRow(step: step, multiplier: multiplier,
                                      time: recipe.isScheduled ? startTime(of: i, from: start) : nil)
                    }
                    if recipe.isScheduled {
                        HStack {
                            Label("Ready", systemImage: "flag.checkered")
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
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ShareLink(item: RecipeFile(recipes: [recipe]), preview: SharePreview(recipe.name)) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                Button("Edit") { showEditor = true }
            }
        }
        .sheet(isPresented: $showEditor, onDismiss: {
            // The recipe was deleted in the editor.
            if model.recipe(id: initial.id) == nil { dismiss() }
        }) {
            RecipeEditorView(recipe: recipe)
        }
        .safeAreaInset(edge: .bottom) {
            if recipe.isScheduled {
                Button {
                    model.start(recipe, multiplier: multiplier)
                } label: {
                    Label("Start now", systemImage: "play.fill")
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
        start.addingTimeInterval(TimeInterval(recipe.offsetMinutes(of: index) * 60))
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
                HStack(spacing: 12) {
                    if step.workMinutes > 0 {
                        Label("approx. \(Format.duration(minutes: step.workMinutes))", systemImage: "hands.sparkles")
                    }
                    if step.waitMinutes > 0 {
                        Label("then \(Format.duration(minutes: step.waitMinutes))", systemImage: "hourglass")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
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
