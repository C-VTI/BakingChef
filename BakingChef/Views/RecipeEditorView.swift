import SwiftUI

// MARK: - Draft

/// Editable copy of a recipe. Steps and ingredients get stable IDs so that lists can
/// move and delete rows safely while text fields are bound to them.
struct RecipeDraft {
    var id: String
    var name: LocalizedText
    var summary: LocalizedText?
    var steps: [StepDraft]

    struct StepDraft: Identifiable {
        let id = UUID()
        var step: RecipeStep
        var ingredients: [IngredientDraft]

        init(_ step: RecipeStep = RecipeStep(title: LocalizedText([:]))) {
            self.step = step
            ingredients = step.ingredients.map(IngredientDraft.init)
        }
    }

    struct IngredientDraft: Identifiable {
        let id = UUID()
        var ingredient: Ingredient
    }

    init(_ recipe: Recipe) {
        id = recipe.id
        name = recipe.nameText
        summary = recipe.summaryText
        steps = recipe.steps.map(StepDraft.init)
    }

    /// A new recipe with one empty step.
    init() {
        id = ""
        name = LocalizedText([:])
        summary = nil
        steps = [StepDraft()]
    }

    var recipe: Recipe {
        Recipe(id: id, name: name, summary: summary, steps: steps.map { draft in
            var step = draft.step
            step.ingredients = draft.ingredients.map(\.ingredient)
            return step
        })
    }

    /// Every text of the recipe (for the translation status).
    var allTexts: [LocalizedText] {
        var texts = [name] + [summary].compactMap { $0 }
        for draft in steps {
            texts.append(draft.step.titleText)
            texts += [draft.step.noteText, draft.step.reminder?.localizedText].compactMap { $0 }
            for item in draft.ingredients { texts += [item.ingredient.nameText, item.ingredient.unitText] }
        }
        return texts.filter { !$0.isEmpty }
    }

    /// The recipe to save: texts cleaned up (see `LocalizedText.normalized`).
    func normalizedRecipe(for languages: [String]) -> Recipe {
        func n(_ text: LocalizedText) -> LocalizedText { text.normalized(for: languages) }
        func n(_ text: LocalizedText?) -> LocalizedText? {
            text.map(n).flatMap { $0.isEmpty ? nil : $0 }
        }
        var recipe = self.recipe
        recipe.nameText = n(recipe.nameText)
        recipe.summaryText = n(recipe.summaryText)
        for i in recipe.steps.indices {
            recipe.steps[i].titleText = n(recipe.steps[i].titleText)
            recipe.steps[i].noteText = n(recipe.steps[i].noteText)
            if let reminder = recipe.steps[i].reminder {
                recipe.steps[i].reminder?.localizedText = n(reminder.localizedText)
            }
            for j in recipe.steps[i].ingredients.indices {
                recipe.steps[i].ingredients[j].nameText = n(recipe.steps[i].ingredients[j].nameText)
                let unit = n(recipe.steps[i].ingredients[j].unitText)
                recipe.steps[i].ingredients[j].unitText = unit.isEmpty ? "" : unit
            }
        }
        return recipe
    }

    /// Why the recipe cannot be saved yet (nil = ok).
    var problem: LocalizedStringKey? {
        if name.isEmpty { return "Please enter a name." }
        if steps.isEmpty { return "Add at least one step." }
        if steps.contains(where: { $0.step.titleText.isEmpty }) { return "Every step needs a title." }
        if steps.contains(where: { $0.step.reminder?.localizedText.isEmpty ?? false }) {
            return "Every reminder needs a text."
        }
        if steps.contains(where: { $0.ingredients.contains { $0.ingredient.nameText.isEmpty } }) {
            return "Every ingredient needs a name."
        }
        return nil
    }
}

// MARK: - Language

extension EnvironmentValues {
    /// Language whose texts the recipe editor shows and changes.
    @Entry var editLanguage: String = "en"
}

private func languageName(_ code: String) -> String {
    Locale.current.localizedString(forLanguageCode: code)?.localizedCapitalized ?? code
}

private struct LanguagePicker: View {
    let languages: [String]
    @Binding var selection: String

    var body: some View {
        Picker("Language", selection: $selection) {
            ForEach(languages, id: \.self) { Text(languageName($0)).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}

/// Text field for one language of a `LocalizedText`.
/// Without its own text in this language the field is empty and shows the text the app
/// currently uses instead (another language) as gray placeholder, marked orange.
private struct LocalizedTextField: View {
    let label: LocalizedStringKey
    @Binding var text: LocalizedText
    var axis: Axis = .horizontal
    @Environment(\.editLanguage) private var language

    var body: some View {
        let translated = text.isTranslated(to: language)
        HStack(alignment: .firstTextBaseline) {
            TextField(label,
                      text: Binding(get: { translated ? text.text(for: language) : "" },
                                    set: { text.setText($0, for: language) }),
                      prompt: translated || text.isEmpty ? nil : Text(text.text(for: language)),
                      axis: axis)
            if !translated && !text.isEmpty {
                Image(systemName: "character.bubble")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(Text("Not translated"))
            }
        }
    }
}

private extension Binding where Value == LocalizedText? {
    /// An optional text as non-optional binding: empty in every language → nil.
    var orEmpty: Binding<LocalizedText> {
        Binding<LocalizedText>(
            get: { wrappedValue ?? LocalizedText([:]) },
            set: { wrappedValue = $0.isEmpty ? nil : $0 })
    }
}

// MARK: - Recipe editor

/// Creates a new recipe (`recipe == nil`) or edits an existing one.
struct RecipeEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let original: Recipe?
    private let initial: Recipe
    /// English and German, plus any other language already used in the recipe.
    private let languages: [String]
    @State private var draft: RecipeDraft
    @State private var language: String
    @State private var editMode: EditMode = .inactive
    @State private var confirmDiscard = false
    @State private var confirmDelete = false
    @State private var saveError: String?

    init(recipe: Recipe?) {
        original = recipe
        let draft = recipe.map(RecipeDraft.init) ?? RecipeDraft()
        initial = draft.recipe
        let used = draft.allTexts.reduce(into: Set<String>()) { $0.formUnion($1.languages) }
        let languages = LocalizedText.editorLanguages
            + used.subtracting(LocalizedText.editorLanguages).sorted()
        self.languages = languages
        let current = LocalizedText.currentLanguage
        _language = State(initialValue: languages.contains(current) ? current : languages[0])
        _draft = State(initialValue: draft)
    }

    private var hasChanges: Bool { draft.recipe != initial }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LanguagePicker(languages: languages, selection: $language)
                } footer: {
                    languageFooter
                }

                Section {
                    LocalizedTextField(label: "Name", text: $draft.name)
                        .font(.headline)
                    LocalizedTextField(label: "Description (optional)", text: $draft.summary.orEmpty,
                                       axis: .vertical)
                        .lineLimit(2...6)
                }

                stepsSection

                if let problem = draft.problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                if let original, model.isCustom(original) {
                    Section {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            if model.isBundled(original) {
                                Label("Reset to original", systemImage: "arrow.uturn.backward")
                            } else {
                                Label("Delete recipe", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .environment(\.editLanguage, language)
            .navigationTitle(original == nil ? Text("New recipe") : Text("Edit recipe"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { confirmDiscard = true } else { dismiss() }
                    }
                    .confirmationDialog("Discard changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                        Button("Discard", role: .destructive) { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .bold()
                        .disabled(draft.problem != nil)
                }
            }
            .confirmationDialog(deleteTitle, isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(deleteButton, role: .destructive) {
                    if let original { model.deleteCustom(original) }
                    dismiss()
                }
            }
            .alert("Saving failed", isPresented: Binding(get: { saveError != nil },
                                                          set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
            .interactiveDismissDisabled(hasChanges)
        }
    }

    @ViewBuilder private var languageFooter: some View {
        let missing = draft.allTexts.filter { !$0.isTranslated(to: language) }.count
        VStack(alignment: .leading, spacing: 4) {
            if missing > 0 {
                Label("\(missing) texts not translated into \(languageName(language))",
                      systemImage: "character.bubble")
                    .foregroundStyle(.orange)
            }
            Text("Texts are edited per language. Amounts, times and the order of the steps apply to all languages.")
        }
    }

    private var stepsSection: some View {
        Section {
            ForEach($draft.steps) { $step in
                NavigationLink {
                    StepEditorView(step: $step, number: number(of: step),
                                   languages: languages, language: $language)
                } label: {
                    StepSummaryRow(step: step, number: number(of: step))
                }
            }
            .onDelete { draft.steps.remove(atOffsets: $0) }
            .onMove { draft.steps.move(fromOffsets: $0, toOffset: $1) }

            Button {
                draft.steps.append(RecipeDraft.StepDraft())
            } label: {
                Label("Add step", systemImage: "plus")
            }
        } header: {
            HStack {
                Text("Steps")
                Spacer()
                if draft.steps.count > 1 {
                    Button(editMode.isEditing ? "reorder.done" : "Reorder") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .font(.subheadline)
                    .textCase(nil)
                }
            }
        } footer: {
            Text("Swipe left to delete a step.")
        }
    }

    private func number(of step: RecipeDraft.StepDraft) -> Int {
        (draft.steps.firstIndex { $0.id == step.id } ?? 0) + 1
    }

    private var deleteTitle: Text {
        original.map(model.isBundled) == true
            ? Text("Reset recipe to the original? Your changes will be lost.")
            : Text("Delete recipe?")
    }

    private var deleteButton: LocalizedStringKey {
        original.map(model.isBundled) == true ? "Reset" : "Delete"
    }

    private func save() {
        do {
            try model.save(draft.normalizedRecipe(for: languages), isNew: original == nil)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct StepSummaryRow: View {
    let step: RecipeDraft.StepDraft
    let number: Int
    @Environment(\.editLanguage) private var language

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                let title = step.step.titleText
                if title.isEmpty {
                    Text("Untitled step").foregroundStyle(.secondary)
                } else {
                    Text(title.text(for: language))
                        .foregroundStyle(title.isTranslated(to: language) ? .primary : .secondary)
                }
                if !details.isEmpty {
                    Text(details).font(.caption).foregroundStyle(.secondary)
                }
            }
            if untranslated {
                Spacer()
                Image(systemName: "character.bubble")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(Text("Not translated"))
            }
        }
    }

    /// Some text of this step is missing in the selected language.
    private var untranslated: Bool {
        let s = step.step
        let texts = [s.titleText, s.noteText, s.reminder?.localizedText].compactMap { $0 }
            + step.ingredients.flatMap { [$0.ingredient.nameText, $0.ingredient.unitText] }
        return texts.contains { !$0.isEmpty && !$0.isTranslated(to: language) }
    }

    private var details: String {
        var parts: [String] = []
        let s = step.step
        if s.workMinutes > 0 { parts.append(String(localized: "approx. \(Format.duration(minutes: s.workMinutes))")) }
        if s.waitMinutes > 0 { parts.append(String(localized: "then \(Format.duration(minutes: s.waitMinutes))")) }
        if !step.ingredients.isEmpty { parts.append(String(localized: "\(step.ingredients.count) ingredients")) }
        if s.reminder != nil { parts.append("🔔") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Step editor

private struct StepEditorView: View {
    @Binding var step: RecipeDraft.StepDraft
    let number: Int
    let languages: [String]
    @Binding var language: String

    var body: some View {
        Form {
            Section {
                LanguagePicker(languages: languages, selection: $language)
            }

            Section {
                LocalizedTextField(label: "Title", text: $step.step.titleText)
                    .font(.headline)
                LocalizedTextField(label: "Note (optional)", text: $step.step.noteText.orEmpty, axis: .vertical)
                    .lineLimit(1...5)
            } footer: {
                Text("The note appears in the notification when the step has no ingredients.")
            }

            Section {
                DurationRow(title: "Work time", minutes: $step.step.workMinutes)
                DurationRow(title: "Waiting time", minutes: $step.step.waitMinutes)
            } footer: {
                Text("The waiting time starts when the step is checked off. The work time is only used for the forecast. Without any waiting time the recipe has no schedule.")
            }

            Section("Ingredients") {
                ForEach($step.ingredients) { $item in
                    IngredientEditorRow(ingredient: $item.ingredient)
                }
                .onDelete { step.ingredients.remove(atOffsets: $0) }
                .onMove { step.ingredients.move(fromOffsets: $0, toOffset: $1) }

                Button {
                    step.ingredients.append(.init(ingredient: Ingredient(name: LocalizedText([:]), amount: 0)))
                } label: {
                    Label("Add ingredient", systemImage: "plus")
                }
            }

            Section {
                Toggle("Reminder before this step", isOn: reminderEnabled)
                if step.step.reminder != nil {
                    LocalizedTextField(label: "Reminder text", text: reminderText)
                    DurationRow(title: "Before the step", minutes: reminderMinutes)
                }
            } footer: {
                Text("An extra notification, e.g. to preheat the oven.")
            }
        }
        .environment(\.editLanguage, language)
        .navigationTitle(Text("Step \(number)"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var reminderEnabled: Binding<Bool> {
        Binding(get: { step.step.reminder != nil },
                set: { step.step.reminder = $0 ? StepReminder(minutesBefore: 30, text: LocalizedText([:])) : nil })
    }

    private var reminderText: Binding<LocalizedText> {
        Binding(get: { step.step.reminder?.localizedText ?? LocalizedText([:]) },
                set: { step.step.reminder?.localizedText = $0 })
    }

    private var reminderMinutes: Binding<Int> {
        Binding(get: { step.step.reminder?.minutesBefore ?? 0 },
                set: { step.step.reminder?.minutesBefore = $0 })
    }
}

private struct IngredientEditorRow: View {
    @Binding var ingredient: Ingredient

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LocalizedTextField(label: "Ingredient", text: $ingredient.nameText)
            HStack(spacing: 8) {
                NumberField(placeholder: "Amount", value: amount)
                    .frame(maxWidth: 90)
                Text(verbatim: "–").foregroundStyle(.secondary)
                NumberField(placeholder: "max", value: $ingredient.amountMax)
                    .frame(maxWidth: 90)
                LocalizedTextField(label: "Unit", text: $ingredient.unitText)
                    .frame(maxWidth: 80)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 4)
    }

    private var amount: Binding<Double?> {
        Binding(get: { ingredient.amount }, set: { ingredient.amount = $0 ?? 0 })
    }
}

/// Decimal input that updates the value while typing (accepts "," and ".").
private struct NumberField: View {
    let placeholder: LocalizedStringKey
    @Binding var value: Double?
    @State private var text = ""

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.decimalPad)
            .monospacedDigit()
            .onAppear { text = value.map(Format.amount) ?? "" }
            .onChange(of: text) { _, newText in
                let trimmed = newText.trimmingCharacters(in: .whitespaces)
                value = trimmed.isEmpty ? nil : Double(trimmed.replacingOccurrences(of: ",", with: "."))
            }
    }
}

/// Hours + minutes as two menus, e.g. "1 h" "30 min".
private struct DurationRow: View {
    let title: LocalizedStringKey
    @Binding var minutes: Int

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 0) {
                Picker(selection: hours) {
                    ForEach(0..<48, id: \.self) { Text("\($0) h").tag($0) }
                } label: { EmptyView() }
                Picker(selection: mins) {
                    ForEach(minuteOptions, id: \.self) { Text("\($0) min").tag($0) }
                } label: { EmptyView() }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private var hours: Binding<Int> {
        Binding(get: { minutes / 60 }, set: { minutes = $0 * 60 + minutes % 60 })
    }

    private var mins: Binding<Int> {
        Binding(get: { minutes % 60 }, set: { minutes = (minutes / 60) * 60 + $0 })
    }

    /// 5-minute steps, plus the current value if it is in between.
    private var minuteOptions: [Int] {
        Array(Set(stride(from: 0, to: 60, by: 5)).union([minutes % 60])).sorted()
    }
}
