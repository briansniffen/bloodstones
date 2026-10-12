import Foundation
import Testing
@testable import BloodstonesEngine

// Hand-built Mission 1 positions. Tests edit the state directly (they have
// internal access) to set up the situation under test.

extension GameState {
    func ids(_ f: FactionID, _ type: UnitType, in region: RegionID) -> [Int] {
        units.filter { $0.faction == f && $0.type == type && $0.region == region }.map(\.id)
    }

    mutating func moveUnit(_ id: Int, to region: RegionID) {
        units[units.firstIndex { $0.id == id }!].region = region
    }

    /// Takes a tile of `unit` from the faction's bag and builds it, for setup.
    /// Falls back to the hand if the bag has none left.
    @discardableResult
    mutating func add(_ unit: UnitType, for f: FactionID, at region: RegionID) -> Int {
        if !factions[f]!.bag.contains(where: { $0.unit == unit }),
           let i = factions[f]!.hand.firstIndex(where: { $0.unit == unit }) {
            factions[f]!.bag.append(factions[f]!.hand.remove(at: i))
        }
        return setUp(unit, for: f, at: region).id
    }

    /// Clears a region of every unit and village (tiles go back to the bag).
    mutating func clear(_ region: RegionID) {
        for u in units where u.region == region {
            _ = removeUnit(u.id)
            if let t = u.tile { factions[u.faction]!.bag.append(t) }
        }
        for v in villages where v.region == region {
            villages.remove(at: villages.firstIndex(of: v)!)
            factions[v.faction]!.villageSupply += 1
        }
    }

    /// Replaces a faction's hand with specific tiles from its bag.
    mutating func setHand(_ f: FactionID, _ types: [UnitType]) {
        factions[f]!.bag += factions[f]!.hand
        factions[f]!.hand = []
        for t in types { factions[f]!.hand.append(factions[f]!.takeFromBag(t)!) }
    }
}

struct Fixture {
    let engine: Engine
    var s: GameState
    init(seed: UInt64 = 1) throws {
        engine = try mission1Engine()
        s = Mission1DragonHunt.initialState(catalog: engine.catalog, seed: seed)
    }

    mutating func apply(_ a: Action) throws { s = try engine.apply(a, to: s) }
    mutating func toMain() throws { if s.phase == .capture { try apply(.endPhase) } }

    /// Ends the player's turn with only `unit` in the Dragon Rider bag, so
    /// that's the tile they draw.
    mutating func dragonTurn(draw unit: UnitType) throws {
        let tile = s.factions[.dragonRiders]!.takeFromBag(unit)!
        let rest = s.factions[.dragonRiders]!.bag
        s.factions[.dragonRiders]!.bag = [tile]
        let turn = s.turnNumber
        while s.turnNumber == turn && s.outcome == nil && s.battle == nil { try apply(.endPhase) }
        s.factions[.dragonRiders]!.bag += rest
    }
}

@Suite struct MovementTests {
    @Test func stackCostsWithLeader() throws {
        var fx = try Fixture()
        try fx.toMain()
        let all = fx.s.units(of: .horseLords).filter { $0.region == 61 && $0.type != .citadel }.map(\.id)
        // Leader, cavalry, sword, shield into forest 53: the leader carries
        // one, so three pay 2 pips each.
        #expect(try fx.engine.legCost(MoveLeg(units: all, to: 53), by: .horseLords, in: fx.s) == 6)
    }

    @Test func shipPassage() throws {
        var fx = try Fixture()
        try fx.toMain()
        let cav = fx.s.ids(.horseLords, .cavalry, in: 61)
        // 61 → (ship on 62) → 63 plains: pay only for entering 63.
        #expect(try fx.engine.legCost(MoveLeg(units: cav, to: 63), by: .horseLords, in: fx.s) == 1)
        // Without the ship there is no way across.
        fx.s.clear(62)
        #expect(throws: EngineError.self) {
            try fx.engine.legCost(MoveLeg(units: cav, to: 63), by: .horseLords, in: fx.s)
        }
    }

    @Test func cannotEnterHillFolkOrTheNorth() throws {
        var fx = try Fixture()
        try fx.toMain()
        let off = Mission1DragonHunt.outOfPlay.union(Mission1DragonHunt.hillFolkRegions)
        for case .move(let legs, _) in fx.engine.legalActions(in: fx.s) {
            #expect(!off.contains(legs[0].to))
        }
        let cav = fx.s.ids(.horseLords, .cavalry, in: 61)[0]
        fx.s.moveUnit(cav, to: 37)   // next to Hill Folk castles on 29 and 30
        #expect(throws: EngineError.self) {
            try fx.engine.legCost(MoveLeg(units: [cav], to: 29), by: .horseLords, in: fx.s)
        }
    }

    @Test func enemiesStopMovement() throws {
        var fx = try Fixture()
        try fx.toMain()
        let cav = fx.s.ids(.horseLords, .cavalry, in: 61)[0]
        fx.s.moveUnit(cav, to: 51)
        // 51 holds only a Dragon Rider village: villages don't stop movement…
        #expect(fx.engine.moveCosts(.land, for: .horseLords, from: 51, in: fx.s)[42] != nil)
        // …but units do: the army on 67 can be entered, not left.
        fx.s.moveUnit(cav, to: 59)
        #expect(fx.engine.moveCosts(.land, for: .horseLords, from: 59, in: fx.s)[67] != nil)
        fx.s.moveUnit(cav, to: 67)
        #expect(throws: EngineError.self) {
            try fx.engine.legCost(MoveLeg(units: [cav], to: 56), by: .horseLords, in: fx.s)
        }
    }

    @Test func overpaymentIsRejected() throws {
        var fx = try Fixture()
        try fx.toMain()
        fx.s.setHand(.horseLords, [.blank, .blank, .swords])     // 5, 5, 4 pips
        let cav = fx.s.ids(.horseLords, .cavalry, in: 61)
        let hand = fx.s.factions[.horseLords]!.hand.map(\.id)
        // Cavalry to 53 costs 2: one 5-pip tile is enough, two is a waste.
        #expect(throws: EngineError.self) {
            try fx.apply(.move(legs: [MoveLeg(units: cav, to: 53)], payWith: [hand[0], hand[1]]))
        }
        try fx.apply(.move(legs: [MoveLeg(units: cav, to: 53)], payWith: [hand[0]]))
        #expect(fx.s.unit(cav[0])!.region == 53)
    }
}

@Suite struct VillageTests {
    @Test func firstVillageGoesNextToTheCitadel() throws {
        var fx = try Fixture()
        // 61's only land neighbour is 53, but the ship on 62 is chained to
        // the citadel, so its coasts 54 and 63 count too (72 is desert).
        #expect(fx.engine.villageSites(for: .horseLords, in: fx.s) == [53, 54, 63])
        // A unit on 53 extends the chain to 53's neighbours.
        fx.s.moveUnit(fx.s.ids(.horseLords, .cavalry, in: 61)[0], to: 53)
        #expect(fx.engine.villageSites(for: .horseLords, in: fx.s) == [44, 45, 53, 54, 63])
        // Without the ship, only 53.
        fx.s.moveUnit(fx.s.ids(.horseLords, .cavalry, in: 53)[0], to: 61)
        fx.s.clear(62)
        #expect(fx.engine.villageSites(for: .horseLords, in: fx.s) == [53])
    }

    @Test func oneTilePerPhase() throws {
        var fx = try Fixture()
        fx.s.setHand(.horseLords, [.swords, .shield])        // 4 and 3 pips
        let hand = fx.s.factions[.horseLords]!.hand.map(\.id)
        try fx.apply(.endPhase)
        try fx.apply(.endPhase)                                // to construct
        try fx.apply(.constructVillage(region: 53, payWith: hand[0]))
        #expect(fx.s.pipBudget == 3)
        #expect(throws: EngineError.self) { try fx.apply(.constructVillage(region: 45, payWith: hand[1])) }
        try fx.apply(.constructVillage(region: 45, payWith: nil))   // adjacent to the new one
        #expect(fx.s.villages.filter { $0.faction == .horseLords }.count == 2)
    }

    @Test func captureEnemyVillage() throws {
        var fx = try Fixture()
        fx.s.moveUnit(fx.s.ids(.horseLords, .cavalry, in: 61)[0], to: 51)
        fx.s.setHand(.horseLords, [.skirmishers])             // 2 pips
        let tile = fx.s.factions[.horseLords]!.hand[0].id
        try fx.apply(.captureVillage(region: 51, payWith: tile))
        #expect(fx.s.villages(in: 51).isEmpty)
        #expect(fx.s.factions[.horseLords]!.capturedVillages == 1)
    }
}

@Suite struct DragonRiderTurnTests {
    /// Ends the player's turn with the Dragon Rider bag stacked.
    func dragonTurn(_ fx: inout Fixture, draw unit: UnitType) throws { try fx.dragonTurn(draw: unit) }

    @Test func activationMovesTheArmyAlongItsPath() throws {
        var fx = try Fixture()
        let army1 = fx.s.ids(.dragonRiders, .swords, in: 50)
        try dragonTurn(&fx, draw: .castle)                     // castle → Army 1
        #expect(fx.s.events.contains(.armyActivated(army: 1, by: .castle)))
        #expect(fx.s.unit(army1[0])!.region == 49)             // 50 → 49
        #expect(fx.s.villages(in: 49).map(\.faction) == [.dragonRiders])
        #expect(fx.s.factions[.dragonRiders]!.hand.map(\.unit) == [.castle])   // kept in hand
    }

    @Test func emptyBagIsDefeat() throws {
        var fx = try Fixture()
        fx.s.factions[.dragonRiders]!.bag = []
        try fx.apply(.endPhase); try fx.apply(.endPhase); try fx.apply(.endPhase)
        #expect(fx.s.outcome == .defeat("The Dragon Riders cannot draw a tile"))
        #expect(fx.s.phase == .gameOver)
    }

    @Test func armyBuildsAShipThenCrosses() throws {
        var fx = try Fixture()
        for id in fx.s.units.filter({ $0.region == 50 && $0.faction == .dragonRiders }).map(\.id) {
            fx.s.moveUnit(id, to: 48)
        }
        let sword = fx.s.ids(.dragonRiders, .swords, in: 48)[0]
        fx.s.setHand(.dragonRiders, [.ship, .blank])
        try dragonTurn(&fx, draw: .skirmishers)               // Army 1, next step sea 36
        #expect(fx.s.ids(.dragonRiders, .ship, in: 36).count == 1)
        #expect(fx.s.unit(sword)!.region == 48)                // built instead of moving
        // Ship built; paid with the drawn skirmisher (2 pips), not the blank (5).
        #expect(fx.s.factions[.dragonRiders]!.hand.map(\.unit) == [.blank])

        try dragonTurn(&fx, draw: .castle)
        #expect(fx.s.unit(sword)!.region == 45)                // across 36 to 45
    }

    @Test func armyWithoutAShipWaits() throws {
        var fx = try Fixture()
        for id in fx.s.units.filter({ $0.region == 50 && $0.faction == .dragonRiders }).map(\.id) {
            fx.s.moveUnit(id, to: 48)
        }
        fx.s.setHand(.dragonRiders, [])
        try dragonTurn(&fx, draw: .castle)
        #expect(fx.s.events.contains(.armyWaits(army: 1, 48)))
    }

    @Test func dragonsBurnUndefendedVillages() throws {
        var fx = try Fixture()
        fx.s.placeVillage(.horseLords, at: 65)                 // next to the dragon on 66
        let dragon = fx.s.ids(.dragonRiders, .dragon, in: 66)[0]
        try dragonTurn(&fx, draw: .castle)
        #expect(fx.s.unit(dragon)!.region == 65)
        #expect(fx.s.villages(in: 65).count == 1)              // captured next turn, not now
        try dragonTurn(&fx, draw: .castle)
        #expect(fx.s.villages(in: 65).isEmpty)
        #expect(fx.s.factions[.dragonRiders]!.capturedVillages == 1)
    }

    @Test func defendedVillagesAreSafe() throws {
        var fx = try Fixture()
        fx.s.placeVillage(.horseLords, at: 65)
        fx.s.moveUnit(fx.s.ids(.horseLords, .cavalry, in: 61)[0], to: 65)
        let dragon = fx.s.ids(.dragonRiders, .dragon, in: 66)[0]
        try dragonTurn(&fx, draw: .castle)
        #expect(fx.s.unit(dragon)!.region == 66)
    }
}

@Suite struct BattleTests {
    @Test func dragonAtHomeWithdrawsToTheMountain() throws {
        var fx = try Fixture()
        try fx.toMain()
        let cav = fx.s.ids(.horseLords, .cavalry, in: 61)[0]
        fx.s.moveUnit(cav, to: 49)
        let dragon = fx.s.ids(.dragonRiders, .dragon, in: 49)[0]
        try fx.apply(.battle(region: 49))
        // Already home, so "towards home" is impossible: highest-numbered
        // option, which is mountain 58, where Horse Lords can't follow.
        #expect(fx.s.unit(dragon)!.region == 58)
        #expect(fx.s.battle == nil)
        #expect(fx.s.events.contains(.withdrew(.dragonRiders, from: 49, to: 58)))
    }

    /// Surround the dragon on 66 so it can't withdraw, then fight until a
    /// seed gives the Horse Lords the win.
    @Test func surroundedDragonCanBeSlain() throws {
        var won = false
        for seed in UInt64(1)...30 where !won {
            var fx = try Fixture(seed: seed)
            fx.s.clear(49)                                     // only one dragon left
            fx.s.factions[.dragonRiders]!.bag.removeAll { $0.unit == .dragon }
            let blockers: [UnitType] = [.skirmishers, .skirmishers, .cavalry, .cavalry, .shield]
            for (r, type) in zip([65, 67, 68, 73, 74], blockers) {   // 66's neighbours
                fx.s.clear(r)
                fx.s.add(type, for: .horseLords, at: r)
            }
            for _ in 0..<4 { fx.s.add(.swords, for: .horseLords, at: 66) }
            fx.s.add(.leader, for: .horseLords, at: 66)
            try fx.toMain()
            try fx.apply(.battle(region: 66))
            #expect(fx.s.battle?.step == .substitute(.horseLords), "no withdrawal possible")
            try fx.apply(.keepTiles)
            if fx.s.outcome == .victory("Both dragons are slain") {
                won = true
                #expect(fx.s.ids(.dragonRiders, .dragon, in: 66).isEmpty)
            }
        }
        #expect(won)
    }

    @Test func dragonCannotWithdrawWhereItJustLeft() throws {
        var fx = try Fixture()
        try fx.toMain()
        let dragon = fx.s.ids(.dragonRiders, .dragon, in: 66)[0]
        // Leave it two ways out: 65 and 67.
        for (r, type) in zip([68, 73, 74], [UnitType.skirmishers, .shield, .swords]) {
            fx.s.clear(r); fx.s.add(type, for: .horseLords, at: r)
        }
        fx.s.clear(65); fx.s.clear(67)
        fx.s.add(.cavalry, for: .horseLords, at: 66)
        try fx.apply(.battle(region: 66))
        #expect(fx.s.unit(dragon)!.region == 67)   // from home: highest option
        // Chase it to 67 and leave 66 empty again: 66 is still closed to it,
        // because it withdrew from there this turn.
        fx.s.moveUnit(fx.s.ids(.horseLords, .cavalry, in: 66)[0], to: 67)
        #expect(fx.s.units(in: 66).isEmpty)
        let options = fx.engine.withdrawOptions(
            Battle(region: 67, attacker: .horseLords, defender: .dragonRiders, step: .withdraw,
                   unitsAtStart: [:]), fx.s)
        #expect(!options.contains(66))
    }

    /// Army 2 reaches the citadel on 61, now undefended: keep fighting
    /// seeds until the Dragon Riders win and the game is lost.
    @Test func capturedCitadelIsDefeat() throws {
        var lost = false
        for seed in UInt64(1)...30 where !lost {
            var fx = try Fixture(seed: seed)
            for u in fx.s.units(in: 61) where u.type != .citadel {
                _ = fx.s.removeUnit(u.id)
                fx.s.factions[.horseLords]!.bag.append(u.tile!)
            }
            for id in fx.s.units.filter({ $0.region == 67 && $0.faction == .dragonRiders }).map(\.id) {
                fx.s.moveUnit(id, to: 53)                      // the step before 61
            }
            try fx.dragonTurn(draw: .siegeEngine)             // Army 2 attacks 61
            #expect(fx.s.battle?.attacker == .dragonRiders)
            while fx.s.battle != nil, fx.s.outcome == nil { try fx.apply(.keepTiles) }
            if fx.s.outcome == .defeat("Your citadel was captured") {
                lost = true
                #expect(fx.s.factions[.dragonRiders]!.capturedCitadels == 1)
            }
        }
        #expect(lost)
    }

    @Test func npcSubstitutesOnlyToWin() throws {
        let fx = try Fixture()
        var s = fx.s
        s.setHand(.dragonRiders, [.leader])                   // a 5
        let b = Battle(region: 52, attacker: .horseLords, defender: .dragonRiders,
                       step: .substitute(.dragonRiders), drawn: [.horseLords: [5, 4, 2], .dragonRiders: [3, 3, 2]],
                       unitsAtStart: [:])
        // 52 holds only the skirmisher (+1 in forest): 3+3+2+1 = 9 vs 11.
        // With the 5 for the 2: 3+3+5+1 = 12 beats 11.
        let sub = fx.engine.script.substitution(b, for: .dragonRiders, in: s, engine: fx.engine)
        #expect(sub?.replacing == 2)
        // Hopeless: 13 can't be reached, so no substitution.
        let b2 = Battle(region: 52, attacker: .horseLords, defender: .dragonRiders,
                        step: .substitute(.dragonRiders), drawn: [.horseLords: [5, 5, 5], .dragonRiders: [2, 2, 2]],
                        unitsAtStart: [:])
        #expect(fx.engine.script.substitution(b2, for: .dragonRiders, in: s, engine: fx.engine) == nil)
    }
}
