import SwiftUI
import UniformTypeIdentifiers

struct RecipeListView: View {
    @Environment(AppModel.self) private var model
    @State private var showImporter = false
    @State private var showNewRecipe = false

    var body: some View {
        List {
            Section {
                ForEach(model.recipes) { recipe in
                    NavigationLink(value: recipe) {
                        RecipeRow(recipe: recipe, isEdited: model.isCustom(recipe) && model.isBundled(recipe))
                    }
                    .swipeActions {
                        if model.isCustom(recipe) {
                            Button(role: .destructive) {
                                model.deleteCustom(recipe)
                            } label: {
                                if model.isBundled(recipe) {
                                    Label("Reset", systemImage: "arrow.uturn.backward")
                                } else {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            } footer: {
                Text("Create recipes with “+” or import JSON files. Swipe to delete your own recipes or to reset edited built-in ones.")
            }
        }
        .navigationTitle("Recipes")
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button { showImporter = true } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                ShareLink(item: RecipeFile(recipes: model.recipes),
                          preview: SharePreview(Text("All recipes"))) {
                    Label("Export all", systemImage: "square.and.arrow.up")
                }
                .disabled(model.recipes.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showNewRecipe = true } label: {
                    Label("New recipe", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showNewRecipe) {
            RecipeEditorView(recipe: nil)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json],
                      allowsMultipleSelection: true) { model.importRecipes(from: $0) }
        .alert("Import failed",
               isPresented: Binding(get: { model.importError != nil },
                                    set: { if !$0 { model.importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.importError ?? "")
        }
    }
}

private struct RecipeRow: View {
    let recipe: Recipe
    let isEdited: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(recipe.name).font(.headline)
                if isEdited {
                    Text("edited")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Group {
                if recipe.isScheduled {
                    Label("\(recipe.steps.count) steps · \(Format.duration(minutes: recipe.totalMinutes))",
                          systemImage: "clock")
                } else {
                    Label("No schedule", systemImage: "list.bullet")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
