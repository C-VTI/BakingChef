import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// One or more recipes as a JSON file for the share sheet ("Save to Files", AirDrop, …).
/// The file can be imported again (also on another device).
struct RecipeFile: Transferable {
    let recipes: [Recipe]

    /// File name without extension: the recipe ID, or "BakingChef-Recipes" for several.
    var fileName: String {
        recipes.count == 1 ? recipes[0].id : "BakingChef-Recipes"
    }

    func data() throws -> Data {
        recipes.count == 1 ? try RecipeParser.encode(recipes[0]) : try RecipeParser.encode(recipes)
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { file in
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("Export-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(file.fileName).appendingPathExtension("json")
            try file.data().write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
