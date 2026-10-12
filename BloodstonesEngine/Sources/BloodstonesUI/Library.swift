import BloodstonesEngine
import Foundation
import SwiftData
import SwiftUI

/// A game in progress or finished. The whole `GameState` is stored as JSON
/// and rewritten after every action.
@Model
public final class SavedGame {
    public var id: UUID
    public var created: Date
    public var updated: Date
    public var mission: Int
    public var seed: Int
    public var turn: Int
    public var outcome: String?
    public var stateData: Data

    public init(mission: Int, seed: UInt64, state: GameState) {
        id = UUID()
        created = .now
        updated = .now
        self.mission = mission
        self.seed = Int(truncatingIfNeeded: seed)
        turn = state.turnNumber
        stateData = (try? JSONEncoder().encode(state)) ?? Data()
    }

    func store(_ state: GameState) {
        stateData = (try? JSONEncoder().encode(state)) ?? stateData
        updated = .now
        turn = state.turnNumber
        outcome = state.outcome.map {
            switch $0 {
            case .victory(let why): "Won: \(why)"
            case .defeat(let why): "Lost: \(why)"
            }
        }
    }

    var state: GameState? { try? JSONDecoder().decode(GameState.self, from: stateData) }
}

/// The first screen: saved games and a button for a new one.
public struct LibraryView: View {
    let data: GameData
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedGame.updated, order: .reverse) private var games: [SavedGame]
    @State private var open: SavedGame?

    public init(data: GameData) { self.data = data }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        let seed = UInt64.random(in: 1...999_999)
                        let game = SavedGame(mission: 1, seed: seed, state: data.newGame(seed: seed))
                        context.insert(game)
                        open = game
                    } label: {
                        Label("New game: Mission 1, Dragon Hunt", systemImage: "plus.circle.fill")
                    }
                }
                Section("Games") {
                    ForEach(games) { game in
                        Button { open = game } label: { row(game) }
                    }
                    .onDelete { offsets in
                        for i in offsets { context.delete(games[i]) }
                    }
                }
            }
            .navigationTitle("Bloodstones")
            .navigationDestination(item: $open) { game in
                PlayView(data: data, game: game)
            }
            #if DEBUG
            // For screenshots: `-startSeed N` opens a new game with that seed.
            .task {
                let args = ProcessInfo.processInfo.arguments
                if open == nil, let i = args.firstIndex(of: "-startSeed"), i + 1 < args.count,
                   let seed = UInt64(args[i + 1]) {
                    let game = SavedGame(mission: 1, seed: seed, state: data.newGame(seed: seed))
                    context.insert(game)
                    open = game
                }
            }
            #endif
        }
    }

    private func row(_ game: SavedGame) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Mission \(game.mission) · Dragon Hunt").font(.headline)
            Text("Turn \(game.turn) · seed \(game.seed) · \(game.updated.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
            if let o = game.outcome { Text(o).font(.caption).foregroundStyle(o.hasPrefix("Won") ? .green : .red) }
        }
    }
}

/// One saved game being played; saves after every action.
struct PlayView: View {
    let data: GameData
    let game: SavedGame
    @State private var model: GameModel?

    var body: some View {
        Group {
            if let model {
                GameScreen(model: model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Dragon Hunt · seed \(game.seed)")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            guard model == nil, let state = game.state else { return }
            let m = GameModel(engine: data.engine, state: state)
            m.onChange = { [game] s in game.store(s) }
            model = m
        }
    }
}
