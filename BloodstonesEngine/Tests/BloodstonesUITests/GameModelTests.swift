import BloodstonesEngine
import Foundation
import Testing
@testable import BloodstonesUI

let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

/// `withArt` uses the repo's art/ folder when it has been extracted.
@MainActor func makeModel(seed: UInt64 = 7, withArt: Bool = false) throws -> GameModel {
    let art = repo.appendingPathComponent("art")
    let data = try GameData.load(from: repo.appendingPathComponent("data"),
                                 art: withArt && FileManager.default.fileExists(atPath: art.path) ? art : nil)
    return GameModel(engine: data.engine, state: data.newGame(seed: seed), art: data.art)
}

@MainActor @Suite struct GameModelTests {
    @Test func tapSelectsLandUnitsThenMoves() throws {
        let m = try makeModel()
        m.perform(.endPhase)                                   // to main actions
        m.tap(61)
        let selected = m.selectedUnits.compactMap { m.state.unit($0)?.type }
        #expect(Set(selected) == [.cavalry, .shield, .leader, .swords])
        #expect(m.highlights()[61] == .selected)
        #expect(m.highlights()[53] == .move(cost: 6))          // three payers into forest
        m.tap(53)
        // Nothing spent yet: the move waits for the payment to be confirmed.
        #expect(m.state.units(in: 53).isEmpty)
        #expect(m.pending?.cost == 6)
        #expect(m.highlights()[53] == .target)
        #expect(m.paymentPips >= 6)
        m.confirmPending()
        #expect(m.state.units(in: 53).count == 4)
        #expect(m.selectedUnits.isEmpty)
        #expect(m.pending == nil)
        #expect(m.canUndo)
    }

    @Test func picksPaymentFromHand() throws {
        let m = try makeModel()
        m.perform(.endPhase)
        m.tap(61)
        for u in m.selectedUnits where m.state.unit(u)?.type != .cavalry { m.toggleUnit(u) }
        // Cavalry to 54 costs 1; pay with a specific 5-pip blank.
        let blank = try #require(m.hand.first { $0.unit == .blank })
        m.toggleTile(blank.id)
        m.tap(54)
        #expect(m.payment == [blank.id])                       // the player's pick is kept
        m.confirmPending()
        #expect(m.state.factions[.horseLords]!.discard.map(\.id) == [blank.id])
    }

    @Test func tappingTheSelectionAgainClearsIt() throws {
        let m = try makeModel()
        m.perform(.endPhase)
        m.tap(61)
        m.tap(61)
        #expect(m.selectedUnits.isEmpty)
    }

    @Test func buildModeHighlightsSitesAndBuilds() throws {
        let m = try makeModel()
        m.perform(.endPhase)
        let ship = try #require(m.hand.first { $0.unit == .ship })
        m.toggleBuild(ship.id)
        #expect(m.highlights() == [62: .buildSite])
        m.tap(62)
        #expect(m.pending?.cost == 1)
        #expect(m.payment.count == 1 && !m.payment.contains(ship.id))
        m.confirmPending()
        #expect(m.state.units(in: 62).filter { $0.type == .ship }.count == 2)
    }

    @Test func battleFlowFromTaps() throws {
        let m = try makeModel()
        m.perform(.endPhase)
        m.tap(61)
        for u in m.selectedUnits where m.state.unit(u)?.type != .cavalry { m.toggleUnit(u) }
        m.tap(52)                                              // into the skirmisher
        m.confirmPending()
        #expect(m.highlights()[52] == .battle)
        m.tap(52)                                              // fight
        #expect(m.battle != nil)
        #expect(m.yourBattleTotal != nil)
        m.perform(.keepTiles)
        #expect(m.battle == nil || m.battle?.step == .casualty || m.battle?.step == .retreat)
    }

    @Test func villagePhaseUsesOneTile() throws {
        let m = try makeModel()
        m.perform(.endPhase)
        m.perform(.endPhase)                                   // to construct
        #expect(m.highlights()[53] == .village(cost: 1))
        m.tap(53)
        m.confirmPending()
        let budget = try #require(m.state.pipBudget)
        #expect(m.state.villages(in: 53).count == 1)
        // The smallest tile that covered 1 pip was used.
        #expect(budget == m.state.factions[.horseLords]!.discard[0].pips - 1)
    }

    @Test func changingThePayment() throws {
        let m = try makeModel()
        m.perform(.endPhase)
        m.tap(61)
        for u in m.selectedUnits where m.state.unit(u)?.type != .cavalry { m.toggleUnit(u) }
        m.tap(53)                                              // forest: 2 pips
        let tiles = m.hand.sorted { $0.pips > $1.pips }
        m.payment = []
        #expect(m.pendingAction == nil)
        #expect(m.pendingProblem != nil)
        m.toggleTile(tiles[0].id)                              // a 5: enough
        #expect(m.pendingAction != nil)
        m.toggleTile(tiles[1].id)                              // and another 5: one is wasted
        #expect(m.pendingAction == nil)
        m.cancelPending()
        #expect(m.pending == nil && m.state.units(in: 53).isEmpty)
    }

    @Test func villageTilePickReplaces() throws {
        let m = try makeModel()
        m.perform(.endPhase)
        m.perform(.endPhase)
        m.tap(53)
        let a = m.hand[0].id, b = m.hand[1].id
        m.toggleTile(a)
        m.toggleTile(b)
        #expect(m.payment == [b])                              // one tile pays for the phase
        m.confirmPending()
        // The next village draws on the leftover pips with no confirmation.
        if let r = m.highlights().first(where: { if case .village = $0.value { true } else { false } })?.key,
           (m.state.pipBudget ?? 0) >= m.engine.villageCostPublic(r) {
            let before = m.state.villages.count
            m.tap(r)
            #expect(m.state.villages.count == before + 1)
            #expect(m.pending == nil)
        }
    }

    @Test func undoRestores() throws {
        let m = try makeModel()
        let start = m.state
        m.perform(.endPhase)
        m.undo()
        #expect(m.state == start)
        #expect(!m.canUndo)
    }

    @Test func savesAfterEveryAction() throws {
        let m = try makeModel()
        var saved = 0
        m.onChange = { _ in saved += 1 }
        m.perform(.endPhase)
        m.perform(.endPhase)
        #expect(saved == 2)
    }
}

@MainActor @Suite struct StackTests {
    @Test func armiesGetTokens() throws {
        let m = try makeModel()
        let tokens = m.armyStacks.map { "\($0.faction.rawValue):\($0.token!)" }
        #expect(tokens == ["dragonRiders:1", "dragonRiders:2", "dragonRiders:3", "horseLords:A"])
        let a = try #require(m.armyStacks.last)
        #expect(a.region == 61 && !a.units.contains { $0.type == .citadel })
        // The citadel stays on the map as its own piece.
        #expect(m.stacks.contains { $0.region == 61 && $0.token == nil && $0.units.map(\.type) == [.citadel] })
    }

    @Test func letterFollowsTheArmy() throws {
        let m = try makeModel()
        m.perform(.endPhase)
        m.tap(61)
        m.tap(53)
        m.confirmPending()
        let a = try #require(m.armyStacks.first { $0.faction == .horseLords })
        #expect(a.token == "A" && a.region == 53)
    }

    @Test func lettersStickWhenAnotherArmyForms() throws {
        // Dragon Rider units with the mission's armies dissolved, so they
        // group like anyone else's.
        var s = try makeModel().state
        guard case .dragonHunt(var mission) = s.mission else { Issue.record("not Mission 1"); return }
        mission.armies = [:]
        s.mission = .dragonHunt(mission)
        let ids = s.units(of: .dragonRiders).filter { ![.dragon, .citadel].contains($0.type) }.prefix(6).map(\.id)
        for (i, id) in ids.enumerated() {
            s.units[s.units.firstIndex { $0.id == id }!].region = i < 3 ? 70 : 10
        }
        let prev: [FactionID: [String: Set<Int>]] = [.dragonRiders: ["A": Set(ids.prefix(3))]]
        // A new army forms in a lower-numbered region; the old one keeps "A".
        let made = GameModel.makeStacks(s, previous: prev)
        let tokens = Dictionary(uniqueKeysWithValues: made.stacks
            .filter { $0.faction == .dragonRiders && $0.token != nil && [10, 70].contains($0.region) }
            .map { ($0.region, $0.token!) })
        #expect(tokens[70] == "A" && tokens[10] != "A")
        #expect(made.letters[.dragonRiders]?["A"] == Set(ids.prefix(3)))
    }
}

@MainActor @Suite struct HitTests {
    /// Pressing any drawn piece means its own region, even where the piece
    /// spills over a border.
    @Test(arguments: [false, true]) func piecesHitTheirOwnRegion(withArt: Bool) throws {
        let m = try makeModel(withArt: withArt)
        for _ in 0..<6 where m.endPhaseAvailable { m.perform(.endPhase) }
        let view = MapView(model: m)
        let fit = MapFit(map: m.art?.map?.bounds ?? CGRect(origin: .zero, size: m.shapes.size),
                         in: CGSize(width: 834, height: 834))
        let regions = Set(m.stacks.map(\.region)).union(m.state.villages.map(\.region))
        var spilled = 0
        for r in regions {
            for (_, rect) in view.layout(region: r, fit: fit) {
                let p = CGPoint(x: rect.midX, y: rect.midY)
                // Skip spots where two regions' pieces overlap.
                let others = regions.filter { $0 != r && view.layout(region: $0, fit: fit).contains { $0.rect.contains(p) } }
                guard others.isEmpty else { continue }
                #expect(view.target(at: p, fit: fit) == r, "piece of \(r) at \(p)")
                if m.shapes.region(at: fit.toMap(p)) != r { spilled += 1 }
            }
        }
        // On the board art, some pieces really do lie over a neighbour.
        if m.art != nil { #expect(spilled > 0) }
    }
}
