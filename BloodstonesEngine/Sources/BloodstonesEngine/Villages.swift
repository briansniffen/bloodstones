extension Engine {
    /// Pips to capture or construct a village; nil where villages can't be.
    func villageCost(_ region: RegionID) -> Int? {
        switch map.terrain(of: region) {
        case .plains, .forest: 1
        case .hills: 2
        case .mountains, .desert, .sea: nil
        }
    }

    /// Spends pips from the phase's one tile, naming it the first time.
    func spendFromPhaseTile(_ cost: Int, payWith pay: Int?, by f: FactionID, in s: inout GameState) throws {
        if let pay {
            guard s.pipBudget == nil else { throw EngineError("only one tile may be spent this phase") }
            guard let tile = handTile(pay, of: f, in: s) else { throw EngineError("tile \(pay) is not in hand") }
            s.pipBudget = tile.pips
            discard([pay], from: f, in: &s)
        }
        guard let budget = s.pipBudget else { throw EngineError("name a tile to pay with") }
        guard budget >= cost else { throw EngineError("\(budget) pips left; this costs \(cost)") }
        s.pipBudget = budget - cost
    }

    // MARK: - Capture

    /// Enemy villages `f` could capture in its capture phase.
    func capturableVillages(by f: FactionID, in s: GameState) -> [Village] {
        let occupied = Set(s.units(of: f).map(\.region))
        return s.villages.filter { $0.faction != f && occupied.contains($0.region) }
    }

    func captureVillage(at region: RegionID, payWith pay: Int?, by f: FactionID, in s: inout GameState) throws {
        guard let village = capturableVillages(by: f, in: s).first(where: { $0.region == region }) else {
            throw EngineError("no enemy village to capture in \(region)")
        }
        try spendFromPhaseTile(villageCost(region)!, payWith: pay, by: f, in: &s)
        takeVillage(village, by: f, in: &s)
    }

    func takeVillage(_ v: Village, by f: FactionID, in s: inout GameState) {
        s.villages.remove(at: s.villages.firstIndex(of: v)!)
        s.factions[f]!.capturedVillages += 1
        s.events.append(.villageCaptured(by: f, from: v.faction, v.region))
    }

    // MARK: - Construct

    /// Regions where `f` may place a village now, under the standard rules.
    func villageSites(for f: FactionID, in s: GameState) -> [RegionID] {
        guard s.factions[f]!.villageSupply > 0 else { return [] }
        let own = s.villages.filter { $0.faction == f }
        let citadels = Set(s.units(of: f).filter { $0.type == .citadel }.map(\.region))
        var anchors = Set(own.map(\.region)).union(citadels)
        // Units (ships included) chained back to a village or the citadel.
        var frontier = Array(anchors)
        let unitRegions = Set(s.units(of: f).map(\.region))
        while let r = frontier.popLast() {
            for n in map.neighbors(of: r) where unitRegions.contains(n) && !anchors.contains(n) {
                anchors.insert(n)
                frontier.append(n)
            }
        }
        return map.regionIDs.filter { r in
            guard villageCost(r) != nil, script.isEnterable(r, in: s), !citadels.contains(r) else { return false }
            // Empty, or holding only this faction's own pieces.
            guard !s.units.contains(where: { $0.region == r && $0.faction != f }),
                  !s.villages.contains(where: { $0.region == r && $0.faction != f }) else { return false }
            switch own.filter({ $0.region == r }).count {
            case 0: return map.neighbors(of: r).contains { anchors.contains($0) }
            case 1: return map.terrain(of: r) == .plains   // up to two in plains
            default: return false
            }
        }
    }

    func constructVillage(at region: RegionID, payWith pay: Int?, by f: FactionID, in s: inout GameState) throws {
        guard villageSites(for: f, in: s).contains(region) else {
            throw EngineError("cannot place a village in \(region)")
        }
        try spendFromPhaseTile(villageCost(region)!, payWith: pay, by: f, in: &s)
        s.placeVillage(f, at: region)
        s.events.append(.villageBuilt(f, region))
    }
}
