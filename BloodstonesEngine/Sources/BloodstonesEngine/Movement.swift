/// How a unit gets around.
enum MoveClass { case land, sea, air, immobile }

extension Engine {
    // MARK: - Unit rules

    func spec(of u: MapUnit) -> TileSpec? {
        u.type == .citadel ? nil : catalog[u.faction].spec(for: u.type)
    }

    func mayRemainInDesert(_ u: MapUnit) -> Bool {
        u.type == .dragon || u.type == .undead || spec(of: u)?.mayRemainInDesert == true
    }

    func moveClass(_ u: MapUnit) -> MoveClass {
        switch u.type {
        case .citadel, .castle: .immobile
        case .ship: .sea
        case .dragon: .air
        default: .land
        }
    }

    /// Whether `u` may end a move, withdrawal or retreat in `region`.
    func canStay(_ u: MapUnit, in region: RegionID) -> Bool {
        let t = map.terrain(of: region)
        switch moveClass(u) {
        case .sea: return t == .sea
        case .air: return true
        case .immobile: return false
        case .land:
            if t == .sea { return false }
            if t == .mountains { return u.faction == .hillFolk || u.type == .undead }
            return true
        }
    }

    /// Pips for a land unit to enter terrain (faction card), nil if it can't.
    func landCost(_ f: FactionID, into t: Terrain) -> Int? {
        switch t {
        case .plains, .desert: 1
        case .forest: 2
        case .hills: f == .hillFolk ? 2 : 3
        case .mountains: f == .hillFolk ? 3 : nil
        case .sea: nil
        }
    }

    func hasOwnShip(_ f: FactionID, in region: RegionID, _ s: GameState) -> Bool {
        s.units.contains { $0.region == region && $0.faction == f && $0.type == .ship }
    }

    // MARK: - Paths

    /// Cheapest pip cost per unit of class `cls` from `origin` to every region
    /// it could stop in. Units may enter regions holding enemy units but not
    /// leave them; land units cross sea for free along their own ships.
    func moveCosts(_ cls: MoveClass, for f: FactionID, from origin: RegionID,
                   in s: GameState) -> [RegionID: Int] {
        map.cheapestCosts(from: origin) { from, to in
            if from != origin && s.hasEnemyUnits(of: f, in: from) { return nil }
            guard script.isEnterable(to, in: s) else { return nil }
            let t = map.terrain(of: to)
            switch cls {
            case .land:
                if t == .sea { return hasOwnShip(f, in: to, s) && !s.hasEnemyUnits(of: f, in: to) ? 0 : nil }
                return landCost(f, into: t)
            case .sea: return t == .sea ? 1 : nil
            case .air: return 1
            case .immobile: return nil
            }
        }
    }

    /// The pip cost of moving one group of units together, or a reason it
    /// can't be done.
    public func legCost(_ leg: MoveLeg, by f: FactionID, in s: GameState) throws -> Int {
        let units = try leg.units.map { id -> MapUnit in
            guard let u = s.unit(id), u.faction == f else { throw EngineError("unit \(id) is not yours") }
            return u
        }
        guard let first = units.first else { throw EngineError("a move needs at least one unit") }
        let origin = first.region
        let cls = moveClass(first)
        guard units.allSatisfy({ $0.region == origin }) else { throw EngineError("units in a group must start together") }
        guard units.allSatisfy({ moveClass($0) == cls }) else { throw EngineError("ships, dragons and land units move separately") }
        guard cls != .immobile else { throw EngineError("castles and citadels cannot move") }
        guard leg.to != origin else { throw EngineError("units must move somewhere") }
        guard !s.hasEnemyUnits(of: f, in: origin) else { throw EngineError("units cannot leave a region with enemy units") }
        guard units.allSatisfy({ canStay($0, in: leg.to) }) else { throw EngineError("those units cannot stop in \(leg.to)") }
        guard let perUnit = moveCosts(cls, for: f, from: origin, in: s)[leg.to] else {
            throw EngineError("no route to \(leg.to)")
        }
        // Each leader carries one other unit for free, so a stack of two
        // leaders and one more unit pays for one.
        let leaders = units.filter { $0.type == .leader }.count
        let payers = cls == .land ? max(1, units.count - leaders) : units.count
        return perUnit * payers
    }

    func move(legs: [MoveLeg], payWith pay: [Int], by f: FactionID, in s: inout GameState) throws {
        guard !legs.isEmpty else { throw EngineError("nothing to move") }
        let all = legs.flatMap(\.units)
        guard Set(all).count == all.count else { throw EngineError("a unit can only move once per action") }
        let cost = try legs.reduce(0) { try $0 + legCost($1, by: f, in: s) }
        try checkPipPayment(pay, covers: cost, by: f, in: s)
        for leg in legs {
            let from = s.unit(leg.units[0])!.region
            for id in leg.units {
                s.units[s.units.firstIndex { $0.id == id }!].region = leg.to
            }
            s.events.append(.moved(f, units: leg.units, from: from, to: leg.to))
        }
        discard(pay, from: f, in: &s)
    }

    /// Pips from hand tiles must cover `cost`, with no tile wasted outright.
    func checkPipPayment(_ pay: [Int], covers cost: Int, by f: FactionID, in s: GameState) throws {
        guard Set(pay).count == pay.count else { throw EngineError("a tile can only be spent once") }
        let tiles = try pay.map { id -> Tile in
            guard let t = handTile(id, of: f, in: s) else { throw EngineError("tile \(id) is not in hand") }
            return t
        }
        let total = tiles.reduce(0) { $0 + $1.pips }
        guard total >= cost else { throw EngineError("\(total) pips do not cover \(cost)") }
        if let smallest = tiles.map(\.pips).min(), total - smallest >= cost {
            throw EngineError("a tile is not needed to pay \(cost)")
        }
    }

    /// The cheapest way to pay `cost` pips: least waste, then fewest tiles,
    /// then lowest tile IDs. Nil if the hand can't cover it.
    public func cheapestPayment(_ cost: Int, from hand: [Tile]) -> [Int]? {
        let tiles = hand.sorted { $0.id < $1.id }
        var best: (key: [Int], ids: [Int])?
        for mask in 1..<(1 << tiles.count) {
            let pick = tiles.indices.filter { mask & (1 << $0) != 0 }.map { tiles[$0] }
            let total = pick.reduce(0) { $0 + $1.pips }
            guard total >= cost, total - pick.map(\.pips).min()! < cost else { continue }
            let key = [total, pick.count] + pick.map(\.id)
            if best == nil || key.lexicographicallyPrecedes(best!.key) { best = (key, pick.map(\.id)) }
        }
        return best?.ids
    }

    // MARK: - Building

    func build(tile id: Int, at region: RegionID, payWith pay: [Int], by f: FactionID,
               in s: inout GameState) throws {
        guard let tile = handTile(id, of: f, in: s) else { throw EngineError("tile \(id) is not in hand") }
        guard let cost = tile.buildCost else { throw EngineError("a \(tile.unit) tile cannot be built") }
        guard script.isEnterable(region, in: s) else { throw EngineError("\(region) is out of play") }
        guard buildSites(for: tile, by: f, in: s).contains(region) else {
            throw EngineError("cannot build a \(tile.unit) in \(region)")
        }
        guard pay.count == cost, !pay.contains(id), Set(pay).count == pay.count,
              pay.allSatisfy({ handTile($0, of: f, in: s) != nil }) else {
            throw EngineError("building a \(tile.unit) costs \(cost) other tiles from hand")
        }
        s.factions[f]!.hand.removeAll { $0.id == id }
        discard(pay, from: f, in: &s)
        s.place(tile, at: region)
        s.events.append(.built(f, tile.unit, region))
    }

    /// Where `tile` could be built: with a village or the citadel, or for
    /// ships in a sea next to one.
    func buildSites(for tile: Tile, by f: FactionID, in s: GameState) -> [RegionID] {
        let bases = Set(s.villages.filter { $0.faction == f }.map(\.region))
            .union(s.units(of: f).filter { $0.type == .citadel }.map(\.region))
        let sites: Set<RegionID> = tile.unit == .ship
            ? Set(bases.flatMap { map.neighbors(of: $0) }.filter { map.terrain(of: $0) == .sea })
            : bases
        return sites.filter { script.isEnterable($0, in: s) }.sorted()
    }
}
