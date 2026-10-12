import Foundation
import Testing
@testable import BloodstonesEngine

func loadCatalog() throws -> FactionCatalog {
    try FactionCatalog(contentsOf: repoRoot.appendingPathComponent("data/factions.json"))
}

@Suite struct FactionCatalogTests {
    @Test func everyBagHas36Tiles() throws {
        let catalog = try loadCatalog()
        #expect(catalog.factions.count == 6)
        for id in FactionID.allCases {
            #expect(catalog.bag(for: id, firstID: 1).count == 36, "\(id)")
        }
    }

    @Test func rulebookMovementExample() throws {
        // "The Dragon Riders expends a castle and cavalry tile to pay for
        // this movement [six pips]. The left-over pip is lost."
        let dr = try loadCatalog()[.dragonRiders]
        #expect(dr.spec(for: .castle)!.pips + dr.spec(for: .cavalry)!.pips == 7)
    }
}

@Suite struct SeededGeneratorTests {
    @Test func sameSeedSameSequence() {
        var a = SeededGenerator(seed: 42), b = SeededGenerator(seed: 42)
        #expect((0..<100).map { _ in a.index(below: 36) } == (0..<100).map { _ in b.index(below: 36) })
    }

    @Test func survivesCodableRoundTrip() throws {
        var a = SeededGenerator(seed: 7)
        _ = a.next()
        var b = try JSONDecoder().decode(SeededGenerator.self, from: JSONEncoder().encode(a))
        #expect(a.next() == b.next())
    }

    @Test func indexStaysInRange() {
        var g = SeededGenerator(seed: 1)
        let seen = Set((0..<1000).map { _ in g.index(below: 6) })
        #expect(seen == Set(0..<6))
    }
}

@Suite struct Mission1SetupTests {
    let catalog: FactionCatalog
    let state: GameState
    init() throws {
        catalog = try loadCatalog()
        state = Mission1DragonHunt.initialState(catalog: catalog, seed: 2026)
    }

    @Test func horseLords() {
        let hl = state.factions[.horseLords]!
        #expect(hl.hand.count == 7)
        #expect(hl.bag.count == 36 - 5 - 7)
        #expect(state.units(in: 61).map(\.type).sorted { $0.rawValue < $1.rawValue }
                == [.cavalry, .citadel, .leader, .shield, .swords])
        #expect(state.units(in: 62).map(\.type) == [.ship])
    }

    @Test func dragonRiders() {
        let dr = state.factions[.dragonRiders]!
        #expect(dr.hand.isEmpty)
        #expect(dr.bag.count == 21)
        // The bag splits evenly across the three army triggers.
        let triggers = Dictionary(grouping: dr.bag) { Mission1DragonHunt.army(activatedBy: $0.unit) }
        #expect(triggers.mapValues(\.count) == [1: 7, 2: 7, 3: 7])
        #expect(state.units(in: 60).map(\.type) == [.citadel])
        #expect(Set(state.units(of: .dragonRiders).filter { $0.type == .dragon }.map(\.region)) == [49, 66])
        #expect(Set(state.villages.map(\.region)) == [50, 51, 52, 59, 67, 68, 69])
        #expect(dr.villageSupply == 13)
    }

    @Test func armiesStartOnTheirPaths() {
        guard case .dragonHunt(let m) = state.mission else { Issue.record("no mission state"); return }
        for route in Mission1DragonHunt.armyRoutes {
            let ids = m.armies[route.number]!
            let units = state.units.filter { ids.contains($0.id) }
            #expect(units.count == 4)
            #expect(units.allSatisfy { $0.region == route.start })
        }
    }

    @Test func hillFolkHoldTheLine() {
        let hf = state.units(of: .hillFolk)
        #expect(Set(hf.map(\.region)) == Mission1DragonHunt.hillFolkRegions)
    }

    @Test func everyTileIsSomewhere() {
        for (id, f) in state.factions {
            let onMap = state.units(of: id).filter { $0.tile != nil }.count
            #expect(f.bag.count + f.hand.count + f.discard.count + onMap == 36, "\(id)")
        }
        let ids = state.factions.values.flatMap { $0.bag + $0.hand }.map(\.id)
            + state.units.compactMap(\.tile?.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func seedDeterminesHand() {
        let again = Mission1DragonHunt.initialState(catalog: catalog, seed: 2026)
        #expect(again == state)
        let other = Mission1DragonHunt.initialState(catalog: catalog, seed: 2027)
        #expect(other.factions[.horseLords]!.hand != state.factions[.horseLords]!.hand)
    }

    @Test func stateRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(GameState.self, from: data) == state)
    }
}
