import BloodstonesEngine
import Foundation
import Testing
@testable import BloodstonesUI

@MainActor func makeModel(seed: UInt64 = 7) throws -> GameModel {
    let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let data = try GameData.load(from: repo.appendingPathComponent("data"))
    return GameModel(engine: data.engine, state: data.newGame(seed: seed))
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
        #expect(m.state.units(in: 53).count == 4)
        #expect(m.selectedUnits.isEmpty)
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
        #expect(m.state.units(in: 62).filter { $0.type == .ship }.count == 2)
    }

    @Test func battleFlowFromTaps() throws {
        let m = try makeModel()
        m.perform(.endPhase)
        m.tap(61)
        for u in m.selectedUnits where m.state.unit(u)?.type != .cavalry { m.toggleUnit(u) }
        m.tap(52)                                              // into the skirmisher
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
        let budget = try #require(m.state.pipBudget)
        #expect(m.state.villages(in: 53).count == 1)
        // The smallest tile that covered 1 pip was used.
        #expect(budget == m.state.factions[.horseLords]!.discard[0].pips - 1)
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
