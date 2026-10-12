import BloodstonesEngine
import Foundation
import Observation

/// The map, faction cards and Mission 1 rules, loaded from a `data/` folder.
public struct GameData: Sendable {
    public let engine: Engine

    public init(engine: Engine) { self.engine = engine }

    public static func load(from data: URL) throws -> GameData {
        let map = try MapGraph(contentsOf: data.appendingPathComponent("maps/\(Mission1DragonHunt.mapId).json"))
        let catalog = try FactionCatalog(contentsOf: data.appendingPathComponent("factions.json"))
        return GameData(engine: Mission1DragonHunt.engine(map: map, catalog: catalog))
    }

    public func newGame(seed: UInt64) -> GameState {
        Mission1DragonHunt.initialState(catalog: engine.catalog, seed: seed)
    }
}

/// How a region is marked on the map for the current choice.
public enum Highlight: Equatable, Sendable {
    case selected
    case move(cost: Int)
    case buildSite
    case village(cost: Int)
    case capture(cost: Int)
    case battle
    case withdraw
    case retreat
}

public struct LogLine: Identifiable, Equatable, Sendable {
    public let id: Int
    public let text: String
}

/// Turns taps into engine actions. Holds the game, undo history and the
/// player's half-made choices (selected units, tile to build, payment).
@MainActor @Observable
public final class GameModel {
    public let engine: Engine
    public let you = FactionID.horseLords
    public let describer: Describer
    public private(set) var state: GameState
    public private(set) var history: [GameState] = []
    public private(set) var legal: [Action] = []
    public private(set) var log: [LogLine] = []

    /// Units picked to move together (all in one region).
    public var selectedUnits: Set<Int> = []
    /// A hand tile the player wants to build.
    public var buildTile: Int?
    /// Hand tiles the player picked to pay with, or to substitute in battle.
    public var payment: [Int] = []
    /// The last thing that went wrong, for the panel to show.
    public var message: String?
    /// Called after every action, so the app can save.
    public var onChange: ((GameState) -> Void)?
    /// Region outlines for drawing and tapping, built once.
    @ObservationIgnored let shapes: MapShapes

    public init(engine: Engine, state: GameState) {
        self.engine = engine
        shapes = MapShapes(engine.map)
        self.state = state
        describer = Describer(engine: engine, you: .horseLords)
        legal = engine.legalActions(in: state)
    }

    public var map: MapGraph { engine.map }
    public var hand: [Tile] { state.factions[you]!.hand.sorted { ($0.unit.rawValue, $0.id) < ($1.unit.rawValue, $1.id) } }
    public var isOver: Bool { state.outcome != nil }
    public var canUndo: Bool { !history.isEmpty }

    // MARK: - Doing things

    public func perform(_ action: Action) {
        do {
            let before = state
            let after = try engine.apply(action, to: state)
            history.append(before)
            state = after
            legal = engine.legalActions(in: after)
            // The neutral Hill Folk never act, so their turns aren't news.
            for e in after.events where e != .turnStarted(.hillFolk) {
                if let text = describer.event(e, in: after, before: before) {
                    log.append(LogLine(id: log.count, text: text))
                }
            }
            clearChoices()
            message = nil
            onChange?(after)
        } catch {
            message = "\(error)"
        }
    }

    public func undo() {
        guard let prev = history.popLast() else { return }
        state = prev
        legal = engine.legalActions(in: prev)
        log.append(LogLine(id: log.count, text: "(undo)"))
        clearChoices()
        onChange?(prev)
    }

    public func clearChoices() {
        selectedUnits = []
        buildTile = nil
        payment = []
    }

    /// The phase's "done" action, if it's available now.
    public var endPhaseAvailable: Bool { legal.contains(.endPhase) }

    // MARK: - Hand

    public func toggleTile(_ id: Int) {
        if let i = payment.firstIndex(of: id) { payment.remove(at: i) } else { payment.append(id) }
        message = nil
    }

    public func toggleBuild(_ id: Int) {
        buildTile = buildTile == id ? nil : id
        selectedUnits = []
        payment.removeAll { $0 == id }
    }

    public func canBuild(_ tile: Tile) -> Bool {
        state.phase == .main && state.battle == nil
            && legal.contains { if case .build(let t, _, _) = $0 { unitType(ofTile: t) == tile.unit } else { false } }
    }

    public var paymentPips: Int {
        payment.compactMap { id in hand.first { $0.id == id }?.pips }.reduce(0, +)
    }

    private func unitType(ofTile id: Int) -> UnitType? { hand.first { $0.id == id }?.unit }

    // MARK: - Units

    /// The region the selected units are in.
    public var selectedRegion: RegionID? { selectedUnits.first.flatMap { state.unit($0)?.region } }

    public func isMobile(_ u: MapUnit) -> Bool { u.type != .castle && u.type != .citadel }

    /// Units of yours the player could pick in a region.
    public func pickable(in region: RegionID) -> [MapUnit] {
        state.units(in: region).filter { $0.faction == you && isMobile($0) }.sorted { $0.id < $1.id }
    }

    public func toggleUnit(_ id: Int) {
        if selectedUnits.contains(id) { selectedUnits.remove(id) } else {
            // Keep the selection in one region.
            if let r = state.unit(id)?.region, r != selectedRegion { selectedUnits = [] }
            selectedUnits.insert(id)
        }
        buildTile = nil
    }

    /// Pip cost for the selected units to reach each region.
    public var moveCosts: [RegionID: Int] {
        guard state.phase == .main, state.battle == nil, !selectedUnits.isEmpty else { return [:] }
        let ids = selectedUnits.sorted()
        var costs: [RegionID: Int] = [:]
        for r in map.regionIDs {
            if let c = try? engine.legCost(MoveLeg(units: ids, to: r), by: you, in: state) { costs[r] = c }
        }
        return costs
    }

    // MARK: - Map

    public func highlights() -> [RegionID: Highlight] {
        var h: [RegionID: Highlight] = [:]
        if let b = state.battle {
            h[b.region] = .battle
            for case .withdraw(let r) in legal { h[r] = .withdraw }
            for case .retreat(let r) in legal { h[r] = .retreat }
            return h
        }
        switch state.phase {
        case .capture:
            for case .captureVillage(let r, _) in legal { h[r] = .capture(cost: engine.villageCostPublic(r)) }
        case .construct:
            for case .constructVillage(let r, _) in legal { h[r] = .village(cost: engine.villageCostPublic(r)) }
        case .main:
            for case .battle(let r) in legal { h[r] = .battle }
            if let t = buildTile, let type = unitType(ofTile: t) {
                for case .build(let tile, let r, _) in legal where unitType(ofTile: tile) == type { h[r] = .buildSite }
            } else {
                for (r, c) in moveCosts { h[r] = .move(cost: c) }
                if let r = selectedRegion { h[r] = .selected }
            }
        default: break
        }
        return h
    }

    /// What a tap on a region means right now.
    public func tap(_ r: RegionID) {
        message = nil
        if state.battle != nil {
            if legal.contains(.withdraw(to: r)) { perform(.withdraw(to: r)) }
            else if legal.contains(.retreat(to: r)) { perform(.retreat(to: r)) }
            return
        }
        switch state.phase {
        case .capture:
            if let a = villageAction(at: r, capture: true) { perform(a) }
        case .construct:
            if let a = villageAction(at: r, capture: false) { perform(a) }
        case .main:
            tapInMain(r)
        default:
            break
        }
    }

    private func tapInMain(_ r: RegionID) {
        if let t = buildTile {
            guard let type = unitType(ofTile: t), let cost = hand.first(where: { $0.id == t })?.buildCost,
                  legal.contains(where: { if case .build(let tile, let site, _) = $0 { site == r && unitType(ofTile: tile) == type } else { false } })
            else { buildTile = nil; return }
            let chosen = payment.filter { $0 != t }
            let pay = chosen.count == cost ? chosen
                : hand.filter { $0.id != t }.sorted { ($0.pips, $0.id) < ($1.pips, $1.id) }.prefix(cost).map(\.id)
            perform(.build(tile: t, region: r, payWith: pay))
            return
        }
        if !selectedUnits.isEmpty, r != selectedRegion, let cost = moveCosts[r] {
            let leg = MoveLeg(units: selectedUnits.sorted(), to: r)
            let pay = paymentCovers(cost) ? payment : engine.cheapestPayment(cost, from: state.factions[you]!.hand)
            guard let pay else { message = "Your hand can't pay \(cost) pips."; return }
            perform(.move(legs: [leg], payWith: pay))
            return
        }
        if legal.contains(.battle(region: r)) && selectedRegion != r {
            perform(.battle(region: r))
            return
        }
        let mine = pickable(in: r)
        if mine.isEmpty || selectedRegion == r {
            selectedUnits = []
        } else {
            // Default to everything that moves on land; ships if that's all there is.
            let land = mine.filter { $0.type != .ship && $0.type != .dragon }
            selectedUnits = Set((land.isEmpty ? mine : land).map(\.id))
        }
    }

    /// The player's picked tiles, if they pay `cost` with nothing spare.
    private func paymentCovers(_ cost: Int) -> Bool {
        guard !payment.isEmpty else { return false }
        let pips = payment.compactMap { id in hand.first { $0.id == id }?.pips }
        return pips.reduce(0, +) >= cost && pips.reduce(0, +) - pips.min()! < cost
    }

    /// Capture or construct at `r`: from the phase's remaining pips, the one
    /// tile the player picked, or else the smallest tile that covers it.
    private func villageAction(at r: RegionID, capture: Bool) -> Action? {
        let options = legal.filter {
            switch $0 {
            case .captureVillage(let x, _): capture && x == r
            case .constructVillage(let x, _): !capture && x == r
            default: false
            }
        }
        func make(_ pay: Int?) -> Action { capture ? .captureVillage(region: r, payWith: pay) : .constructVillage(region: r, payWith: pay) }
        if options.contains(make(nil)) { return make(nil) }
        if payment.count == 1, options.contains(make(payment[0])) { return make(payment[0]) }
        let byPips = options.compactMap { a -> (Int, Int)? in
            switch a {
            case .captureVillage(_, let p?), .constructVillage(_, let p?):
                hand.first { $0.id == p }.map { ($0.pips, $0.id) }
            default: nil
            }
        }.sorted { $0 < $1 }
        return byPips.first.map { make($0.1) }
    }

    // MARK: - Battle

    public var battle: Battle? { state.battle }

    public var yourBattleTotal: Int? {
        guard let b = state.battle, let tiles = b.drawn[you] else { return nil }
        return engine.battleTotal(you, tiles: tiles, in: b, state)
    }

    /// Substitute the single tile the player picked for their lowest Battle tile.
    public var substitution: Action? {
        guard let b = state.battle, case .substitute(let f) = b.step, f == you,
              payment.count == 1, let drawn = b.drawn[you] else { return nil }
        let a = Action.substitute(tile: payment[0], replacing: drawn.indices.max()!)
        return legal.contains(a) ? a : nil
    }

    // MARK: - Dragon Riders

    public struct ArmyInfo: Identifiable, Sendable {
        public let id: Int
        public let region: RegionID?
        public let next: RegionID?
        public let units: [UnitType]
    }

    public var armies: [ArmyInfo] {
        guard case .dragonHunt(let m) = state.mission else { return [] }
        return m.armies.sorted { $0.key < $1.key }.map { n, ids in
            let us = ids.compactMap { state.unit($0) }
            let here = us.first?.region
            let path = Mission1DragonHunt.route(n).path
            let next = here.flatMap { h in path.firstIndex(of: h).flatMap { $0 + 1 < path.count ? path[$0 + 1] : nil } }
            return ArmyInfo(id: n, region: here, next: next, units: us.map(\.type))
        }
    }

    public var dragons: [MapUnit] { state.units(of: .dragonRiders).filter { $0.type == .dragon } }
}

extension Engine {
    /// Pips to capture or build a village in a region (0 where impossible).
    public func villageCostPublic(_ r: RegionID) -> Int {
        switch map.terrain(of: r) {
        case .plains, .forest: 1
        case .hills: 2
        default: 0
        }
    }
}
