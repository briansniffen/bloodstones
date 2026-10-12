extension Engine {
    /// Every legal action for the human due to act, with one canonical
    /// payment each (least waste, then fewest tiles, then lowest IDs).
    /// `apply` accepts any valid payment, not only the one listed here.
    /// Moves are listed one group at a time; `apply` also takes several
    /// groups paid for together.
    public func legalActions(in s: GameState) -> [Action] {
        guard let f = humanToAct(in: s) else { return [] }
        if let b = s.battle { return battleActions(b, for: f, s) }
        let hand = s.factions[f]!.hand
        switch s.phase {
        case .capture:
            var actions: [Action] = [.endPhase]
            for r in Set(capturableVillages(by: f, in: s).map(\.region)).sorted() {
                actions += phaseTilePayments(villageCost(r)!, hand: hand, s).map { .captureVillage(region: r, payWith: $0) }
            }
            return actions
        case .construct:
            var actions: [Action] = [.endPhase]
            for r in villageSites(for: f, in: s) {
                actions += phaseTilePayments(villageCost(r)!, hand: hand, s).map { .constructVillage(region: r, payWith: $0) }
            }
            return actions
        case .main:
            var actions: [Action] = []
            for r in s.contestedRegions(for: f) { actions.append(.battle(region: r)) }
            if actions.isEmpty { actions.append(.endPhase) }
            actions += buildActions(for: f, s)
            actions += moveActions(for: f, s)
            return actions
        case .nonPlayer, .gameOver:
            return []
        }
    }

    /// Ways to pay in the capture/construct phase: from the tile already
    /// spent, or by naming any hand tile that covers the cost.
    private func phaseTilePayments(_ cost: Int, hand: [Tile], _ s: GameState) -> [Int?] {
        if let budget = s.pipBudget { return budget >= cost ? [nil] : [] }
        return hand.filter { $0.pips >= cost }.sorted { $0.id < $1.id }.map(\.id)
    }

    private func buildActions(for f: FactionID, _ s: GameState) -> [Action] {
        var actions: [Action] = []
        let hand = s.factions[f]!.hand.sorted { $0.id < $1.id }
        // One action per kind of tile: two Swords in hand build the same unit.
        var seen = Set<UnitType>()
        for tile in hand where tile.buildCost != nil && seen.insert(tile.unit).inserted {
            let others = hand.filter { $0.id != tile.id }.sorted { ($0.pips, $0.id) < ($1.pips, $1.id) }
            guard others.count >= tile.buildCost! else { continue }
            let pay = others.prefix(tile.buildCost!).map(\.id)
            for r in buildSites(for: tile, by: f, in: s) {
                actions.append(.build(tile: tile.id, region: r, payWith: pay))
            }
        }
        return actions
    }

    /// Single-group moves: for each region, each combination of unit types
    /// (units of one type are interchangeable), each reachable destination.
    private func moveActions(for f: FactionID, _ s: GameState) -> [Action] {
        var actions: [Action] = []
        let hand = s.factions[f]!.hand
        let byRegion = Dictionary(grouping: s.units(of: f).filter { moveClass($0) != .immobile }, by: \.region)
        for (origin, units) in byRegion.sorted(by: { $0.key < $1.key }) where !s.hasEnemyUnits(of: f, in: origin) {
            let byClass = Dictionary(grouping: units) { "\(moveClass($0))" }
            for (_, group) in byClass.sorted(by: { $0.key < $1.key }) {
                let cls = moveClass(group[0])
                let costs = moveCosts(cls, for: f, from: origin, in: s)
                for pick in typeCombinations(group) {
                    for (dest, _) in costs.sorted(by: { $0.key < $1.key }) where dest != origin {
                        let leg = MoveLeg(units: pick, to: dest)
                        guard let cost = try? legCost(leg, by: f, in: s),
                              let pay = cheapestPayment(cost, from: hand) else { continue }
                        actions.append(.move(legs: [leg], payWith: pay))
                    }
                }
            }
        }
        return actions
    }

    /// Every non-empty selection of units, treating units of one type as
    /// interchangeable (lowest IDs first).
    private func typeCombinations(_ units: [MapUnit]) -> [[Int]] {
        let byType = Dictionary(grouping: units.sorted { $0.id < $1.id }, by: \.type)
            .sorted { $0.key.rawValue < $1.key.rawValue }
        var result: [[Int]] = [[]]
        for (_, same) in byType {
            result = result.flatMap { prefix in (0...same.count).map { prefix + same.prefix($0).map(\.id) } }
        }
        return result.filter { !$0.isEmpty }
    }

    private func battleActions(_ b: Battle, for f: FactionID, _ s: GameState) -> [Action] {
        switch b.step {
        case .withdraw:
            return [.stand] + withdrawOptions(b, s).map { .withdraw(to: $0) }
        case .substitute:
            // Replacing the lowest Battle tile is always best.
            // (Tiles are kept highest first, so that's the last index.)
            let lowest = b.drawn[f]!.indices.max()!
            let subs = s.factions[f]!.hand.sorted { $0.id < $1.id }
                .map { Action.substitute(tile: $0.id, replacing: lowest) }
            return [.keepTiles] + subs
        case .casualty:
            return force(f, in: b, s).map { .eliminate(unit: $0.id) }
        case .retreat:
            return fallbackDestinations(for: f, from: b.region, units: force(f, in: b, s), s).map { .retreat(to: $0) }
        }
    }
}
