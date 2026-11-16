import SwiftUI
import UniformTypeIdentifiers

struct RecipeListView: View {
    @Environment(AppModel.self) private var model
    @State private var showImporter = false

    var body: some View {
        List {
            Section {
                ForEach(model.recipes) { recipe in
                    NavigationLink(value: recipe) { RecipeRow(recipe: recipe) }
                        .deleteDisabled(!model.isImported(recipe))
                }
                .onDelete { offsets in
                    for i in offsets { model.deleteImported(model.recipes[i]) }
                }
            } footer: {
                Text("Add your own recipes as JSON files via “Import”. Imported recipes can be deleted by swiping.")
            }
        }
        .navigationTitle("Recipes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showImporter = true } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
            }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recipe.name).font(.headline)
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
