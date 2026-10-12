import BloodstonesUI
import SwiftData
import SwiftUI

@main
struct BloodstonesApp: App {
    /// The map and faction data, bundled from the repo's `data/` folder.
    private let data: Result<GameData, Error> = Result {
        guard let url = Bundle.main.url(forResource: "data", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try GameData.load(from: url)
    }

    var body: some Scene {
        WindowGroup {
            switch data {
            case .success(let data):
                LibraryView(data: data)
            case .failure(let error):
                Text("Couldn't load the game data: \(error.localizedDescription)").padding()
            }
        }
        .modelContainer(for: SavedGame.self)
    }
}
