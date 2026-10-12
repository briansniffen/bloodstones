import Foundation
import Testing
@testable import BloodstonesEngine

func mission1Engine() throws -> Engine {
    try Mission1DragonHunt.engine(map: loadMap(Mission1DragonHunt.mapId), catalog: loadCatalog())
}

/// Every tile is in exactly one place: bag, hand, discard, or on the map.
func checkTilesConserved(_ s: GameState, _ note: @autoclosure () -> String = "") {
    var ids: [Int] = []
    for (id, f) in s.factions {
        let onMap = s.units.compactMap(\.tile).filter { $0.faction == id }
        let all = f.bag + f.hand + f.discard + onMap
        #expect(all.count == 36, "\(id) has \(all.count) tiles \(note())")
        ids += all.map(\.id)
    }
    #expect(Set(ids).count == ids.count, "a tile is in two places \(note())")
}

@Suite struct PlaythroughTests {
    /// Random play: every listed action must apply, tiles are conserved,
    /// and the game must end (the Dragon Rider bag is a 21-turn clock).
    @Test(arguments: 1...40)
    func randomGamesFinish(seed: UInt64) throws {
        let engine = try mission1Engine()
        var s = Mission1DragonHunt.initialState(catalog: engine.catalog, seed: seed)
        var chooser = SeededGenerator(seed: seed &* 7919)
        var steps = 0
        while s.outcome == nil {
            let actions = engine.legalActions(in: s)
            try #require(!actions.isEmpty, "stuck in \(s.phase), battle \(String(describing: s.battle))")
            // Lean towards ending phases so games move along.
            let action = actions.contains(.endPhase) && chooser.index(below: 4) == 0
                ? .endPhase : actions[chooser.index(below: actions.count)]
            do {
                s = try engine.apply(action, to: s)
            } catch {
                Issue.record("seed \(seed) step \(steps): \(action) failed: \(error)")
                return
            }
            checkTilesConserved(s, "seed \(seed) step \(steps) after \(action)")
            let off = Mission1DragonHunt.outOfPlay.union(Mission1DragonHunt.hillFolkRegions)
            for u in s.units where u.faction != .hillFolk {
                #expect(!off.contains(u.region), "\(u) off limits, seed \(seed) step \(steps)")
                let t = engine.map.terrain(of: u.region)
                #expect(t != .sea || u.type == .ship || u.type == .dragon, "\(u) at sea, seed \(seed)")
                #expect(t != .mountains || u.type == .dragon, "\(u) in mountains, seed \(seed)")
            }
            steps += 1
            try #require(steps < 5000, "game did not finish")
        }
        #expect(s.phase == .gameOver)
        #expect(engine.legalActions(in: s).isEmpty)
    }

    @Test func replayIsExact() throws {
        let engine = try mission1Engine()
        func play(_ seed: UInt64) throws -> [GameState] {
            var s = Mission1DragonHunt.initialState(catalog: engine.catalog, seed: seed)
            var states = [s]
            for _ in 0..<60 where s.outcome == nil {
                let a = engine.legalActions(in: s)
                s = try engine.apply(a.contains(.endPhase) ? .endPhase : a[0], to: s)
                states.append(s)
            }
            return states
        }
        #expect(try play(99) == play(99))
    }

    /// Doing nothing loses to the clock (or sooner).
    @Test func passingEveryTurnLoses() throws {
        let engine = try mission1Engine()
        var s = Mission1DragonHunt.initialState(catalog: engine.catalog, seed: 5)
        while s.outcome == nil {
            let a = engine.legalActions(in: s)
            s = try engine.apply(a.contains(.endPhase) ? .endPhase : (a.contains(.stand) ? .stand
                : a.contains(.keepTiles) ? .keepTiles : a[0]), to: s)
        }
        guard case .defeat = s.outcome else { Issue.record("expected defeat, got \(String(describing: s.outcome))"); return }
    }
}
