/// The rules. Holds the fixed inputs (map, faction cards, mission script);
/// every game step is a pure function from one `GameState` to the next.
public struct Engine: Sendable {
    public let map: MapGraph
    public let catalog: FactionCatalog
    public let script: any MissionScript

    public init(map: MapGraph, catalog: FactionCatalog, script: any MissionScript) {
        self.map = map
        self.catalog = catalog
        self.script = script
    }

    /// Applies a human action, then runs non-player turns and non-player
    /// battle decisions until a human must act again or the game ends.
    public func apply(_ action: Action, to state: GameState) throws -> GameState {
        var s = state
        s.events = []
        guard s.outcome == nil else { throw EngineError("the game is over") }
        guard let actor = humanToAct(in: s) else { throw EngineError("no human is due to act") }
        if s.battle != nil {
            try applyBattleDecision(action, by: actor, to: &s)
        } else {
            try applyTurnAction(action, by: actor, to: &s)
        }
        advance(&s)
        return s
    }

    /// The human whose input the game is waiting for, if any.
    public func humanToAct(in s: GameState) -> FactionID? {
        guard s.outcome == nil else { return nil }
        if let b = s.battle { return s.humans.contains(b.decider) ? b.decider : nil }
        return s.phase == .nonPlayer || !s.humans.contains(s.activeFaction) ? nil : s.activeFaction
    }

    /// Runs everything that needs no human: non-player battle decisions and
    /// non-player turns. Stops when a human must act or the game is over.
    func advance(_ s: inout GameState) {
        while true {
            if s.outcome == nil, let o = script.outcome(s) {
                s.outcome = o
                s.events.append(.gameOver(o))
            }
            if s.outcome != nil { s.phase = .gameOver; s.battle = nil; return }
            if let b = s.battle {
                if s.humans.contains(b.decider) { return }
                scriptBattleDecision(&s)
                continue
            }
            guard s.phase == .nonPlayer else { return }
            if script.step(&s, engine: self) {
                endTurn(&s)
            }
        }
    }

    // MARK: - Turn flow

    private func applyTurnAction(_ action: Action, by f: FactionID, to s: inout GameState) throws {
        switch (s.phase, action) {
        case (.capture, .endPhase):
            s.phase = .main
            s.pipBudget = nil
        case (.capture, .captureVillage(let r, let pay)):
            try captureVillage(at: r, payWith: pay, by: f, in: &s)
        case (.main, .build(let tile, let r, let pay)):
            try build(tile: tile, at: r, payWith: pay, by: f, in: &s)
        case (.main, .move(let legs, let pay)):
            try move(legs: legs, payWith: pay, by: f, in: &s)
        case (.main, .battle(let r)):
            guard s.units(of: f).contains(where: { $0.region == r }), s.hasEnemyUnits(of: f, in: r) else {
                throw EngineError("no battle to fight in \(r)")
            }
            startBattle(at: r, attacker: f, in: &s)
        case (.main, .endPhase):
            let contested = s.contestedRegions(for: f)
            guard contested.isEmpty else { throw EngineError("battles still to fight in \(contested)") }
            s.phase = .construct
            s.pipBudget = nil
        case (.construct, .constructVillage(let r, let pay)):
            try constructVillage(at: r, payWith: pay, by: f, in: &s)
        case (.construct, .endPhase):
            removeUnitsInDesert(of: f, in: &s)
            refillHand(of: f, in: &s)
            endTurn(&s)
        default:
            throw EngineError("\(action) is not allowed in the \(s.phase) phase")
        }
    }

    /// Passes play to the next faction in turn order.
    func endTurn(_ s: inout GameState) {
        s.activeIndex = (s.activeIndex + 1) % s.turnOrder.count
        if s.activeIndex == 0 { s.turnNumber += 1 }
        s.withdrewFrom = [:]
        s.pipBudget = nil
        let f = s.activeFaction
        s.phase = s.humans.contains(f) ? .capture : .nonPlayer
        s.events.append(.turnStarted(f))
    }

    // MARK: - Tiles

    /// Draws back up to hand size, regrouping when the bag runs dry.
    func refillHand(of f: FactionID, in s: inout GameState) {
        var drawn = 0
        while s.factions[f]!.hand.count < s.factions[f]!.handSize {
            if s.factions[f]!.bag.isEmpty {
                guard script.regroups(f), !s.factions[f]!.discard.isEmpty else { break }
                regroup(f, in: &s)
            }
            s.draw(1, for: f)
            drawn += 1
        }
        if drawn > 0 { s.events.append(.drew(f, count: drawn)) }
    }

    /// Discards go back in the bag, and the faction scores its villages.
    func regroup(_ f: FactionID, in s: inout GameState) {
        s.factions[f]!.bag = s.factions[f]!.discard.sorted { $0.id < $1.id }
        s.factions[f]!.discard = []
        s.factions[f]!.regroups += 1
        let villages = s.villages.filter { $0.faction == f }.count
        // Scoring stops once the game-end number of regroups is reached
        // (three with two players, otherwise two).
        let limit = s.turnOrder.count == 2 ? 3 : 2
        let scored = s.factions[f]!.regroups <= limit ? villages : 0
        s.factions[f]!.victoryPoints += scored
        s.events.append(.regrouped(f, regroups: s.factions[f]!.regroups, villagesScored: scored))
    }

    /// Takes tiles out of a hand and puts them on the discard pile.
    func discard(_ ids: [Int], from f: FactionID, in s: inout GameState) {
        for id in ids {
            let i = s.factions[f]!.hand.firstIndex { $0.id == id }!
            s.factions[f]!.discard.append(s.factions[f]!.hand.remove(at: i))
        }
    }

    func handTile(_ id: Int, of f: FactionID, in s: GameState) -> Tile? {
        s.factions[f]!.hand.first { $0.id == id }
    }

    // MARK: - Units

    /// Removes a unit from the map. Its tile goes to the owner's discard
    /// pile; a citadel goes to `captor`, if any.
    func eliminate(_ id: Int, captor: FactionID?, in s: inout GameState) {
        let u = s.removeUnit(id)
        if let tile = u.tile { s.factions[u.faction]!.discard.append(tile) }
        if u.type == .citadel, let captor { s.factions[captor]!.capturedCitadels += 1 }
        s.events.append(.eliminated(u.faction, u.type, u.region))
    }

    /// End of turn: units that cannot remain in desert are lost.
    func removeUnitsInDesert(of f: FactionID, in s: inout GameState) {
        for u in s.units(of: f) where map.terrain(of: u.region) == .desert && !mayRemainInDesert(u) {
            eliminate(u.id, captor: nil, in: &s)
        }
    }
}
