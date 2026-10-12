extension Engine {
    /// Each side's bag of Battle tiles.
    static let battleTileValues = [2, 2, 3, 3, 4, 4, 5, 5]

    func force(_ f: FactionID, in b: Battle, _ s: GameState) -> [MapUnit] {
        s.units.filter { $0.region == b.region && $0.faction == f }
    }

    // MARK: - Starting

    func startBattle(at region: RegionID, attacker: FactionID, in s: inout GameState) {
        let here = s.units.filter { $0.region == region }
        let defender = s.turnOrder.first { f in f != attacker && here.contains { $0.faction == f } }!
        let count = { (f: FactionID) in here.filter { $0.faction == f }.count }
        s.battle = Battle(region: region, attacker: attacker, defender: defender, step: .withdraw,
                          unitsAtStart: [attacker: count(attacker), defender: count(defender)])
        s.events.append(.battleStarted(region, attacker: attacker, defender: defender))
        if withdrawOptions(s.battle!, s).isEmpty { beginRound(&s) }
    }

    /// Where the defender could withdraw to before the battle, if allowed.
    func withdrawOptions(_ b: Battle, _ s: GameState) -> [RegionID] {
        let def = force(b.defender, in: b, s), att = force(b.attacker, in: b, s)
        if def.contains(where: { $0.type == .castle || $0.type == .citadel }) { return [] }
        if att.contains(where: { $0.type == .dragon }) { return [] }
        let cavalry = { (u: [MapUnit]) in u.filter { $0.type == .cavalry }.count }
        guard def.contains(where: { $0.type == .dragon }) || cavalry(def) >= cavalry(att) else { return [] }
        return fallbackDestinations(for: b.defender, from: b.region, units: def, s)
    }

    /// Where a beaten or withdrawing force may go: an adjacent region, or
    /// one reached along a chain of its own ships in uncontested seas, that
    /// is empty or holds some of its own pieces, that it hasn't already
    /// left this turn, and where at least one of the units can stay.
    func fallbackDestinations(for f: FactionID, from region: RegionID, units: [MapUnit],
                              _ s: GameState) -> [RegionID] {
        var seas = Set<RegionID>()
        var frontier = [region]
        while let r = frontier.popLast() {
            for n in map.neighbors(of: r) where !seas.contains(n) && map.terrain(of: n) == .sea
                && hasOwnShip(f, in: n, s) && !s.hasEnemyUnits(of: f, in: n) {
                seas.insert(n)
                frontier.append(n)
            }
        }
        let candidates = Set(map.neighbors(of: region)).union(seas.flatMap { map.neighbors(of: $0) })
        let left = Set(s.withdrewFrom[f] ?? [])
        return candidates.filter { c in
            guard c != region, script.isEnterable(c, in: s), !left.contains(c) else { return false }
            let own = s.units.contains { $0.region == c && $0.faction == f }
                || s.villages.contains { $0.region == c && $0.faction == f }
            let empty = !s.units.contains { $0.region == c } && !s.villages.contains { $0.region == c }
            return (own || empty) && units.contains { canStay($0, in: c) }
        }.sorted()
    }

    /// Moves a force out of the battle; units that can't stay there are lost.
    func fallBack(_ f: FactionID, to dest: RegionID, retreating: Bool, in s: inout GameState) {
        let b = s.battle!
        for u in force(f, in: b, s) {
            if canStay(u, in: dest) {
                s.units[s.units.firstIndex { $0.id == u.id }!].region = dest
            } else {
                eliminate(u.id, captor: nil, in: &s)
            }
        }
        s.withdrewFrom[f, default: []].append(b.region)
        s.events.append(retreating ? .retreated(f, from: b.region, to: dest) : .withdrew(f, from: b.region, to: dest))
        s.battle = nil
    }

    // MARK: - Rounds

    /// In a solo game the human always draws and decides first; otherwise
    /// the attacker substitutes first.
    func substitutionOrder(_ b: Battle, _ s: GameState) -> [FactionID] {
        s.humans.contains(b.defender) && !s.humans.contains(b.attacker)
            ? [b.defender, b.attacker] : [b.attacker, b.defender]
    }

    func beginRound(_ s: inout GameState) {
        var b = s.battle!
        b.drawn = [:]
        b.substituted = []
        let order = substitutionOrder(b, s)
        b.step = .substitute(order[0])
        s.battle = b
        drawBattleTiles(order[0], in: &s)
        // Between two people both hands are drawn at once (the attacker sees
        // the backs of the defender's tiles); a script draws only after the
        // human has decided.
        if s.humans.contains(order[0]) && s.humans.contains(order[1]) { drawBattleTiles(order[1], in: &s) }
    }

    func drawBattleTiles(_ f: FactionID, in s: inout GameState) {
        let b = s.battle!
        let mine = force(f, in: b, s), theirs = force(b.opponent(of: f), in: b, s)
        let giant = mine.contains { spec(of: $0)?.alwaysDrawFourInBattle == true }
        let n = mine.count > theirs.count || giant ? 4 : 3
        var pool = Self.battleTileValues
        var drawn: [Int] = []
        for _ in 0..<n { drawn.append(pool.remove(at: s.rng.index(below: pool.count))) }
        s.battle!.drawn[f] = drawn.sorted(by: >)
        s.events.append(.battleTiles(f, s.battle!.drawn[f]!))
    }

    /// Records a substitution choice (or none) and moves the battle on.
    func substitute(_ f: FactionID, tile: Int?, replacing index: Int, in s: inout GameState) {
        if let tile {
            let t = handTile(tile, of: f, in: s)!
            discard([tile], from: f, in: &s)
            s.battle!.drawn[f]![index] = t.pips
            s.battle!.drawn[f]!.sort(by: >)
            s.events.append(.substituted(f, pips: t.pips))
        }
        s.battle!.substituted.insert(f)
        let other = s.battle!.opponent(of: f)
        if s.battle!.substituted.contains(other) {
            resolveRound(&s)
        } else {
            if s.battle!.drawn[other] == nil { drawBattleTiles(other, in: &s) }
            s.battle!.step = .substitute(other)
        }
    }

    /// Top three tiles plus every unit's modifier.
    func battleTotal(_ f: FactionID, tiles: [Int], in b: Battle, _ s: GameState) -> Int {
        tiles.sorted(by: >).prefix(3).reduce(0, +) + modifiers(f, in: b, s)
    }

    func modifiers(_ f: FactionID, in b: Battle, _ s: GameState) -> Int {
        let terrain = map.terrain(of: b.region)
        let foeFortified = force(b.opponent(of: f), in: b, s).contains { $0.type == .castle || $0.type == .citadel }
        var total = f == .corsairs && terrain == .sea ? 1 : 0
        for u in force(f, in: b, s) {
            let (bonus, when): (Int, BonusCondition?) = u.type == .citadel
                ? (catalog[f].citadel?.battleBonus ?? 0, catalog[f].citadel?.bonusWhen)
                : (spec(of: u)?.battleBonus ?? 0, spec(of: u)?.bonusWhen)
            let applies = switch when {
            case .always: true
            case .attacking: f == b.attacker
            case .defending: f == b.defender
            case .inForest: terrain == .forest
            case .inPlains: terrain == .plains
            case .vsCastleOrCitadel: foeFortified
            case nil: false
            }
            if applies { total += bonus }
        }
        return total
    }

    /// Whether `f` wins the round outright with these tiles against `against`.
    func wins(_ f: FactionID, tiles: [Int], against: [Int], in b: Battle, _ s: GameState) -> Bool {
        let mine = battleTotal(f, tiles: tiles, in: b, s)
        let theirs = battleTotal(b.opponent(of: f), tiles: against, in: b, s)
        if mine != theirs { return mine > theirs }
        return f == b.defender && defenderWinsTies(b, s)
    }

    func defenderWinsTies(_ b: Battle, _ s: GameState) -> Bool {
        force(b.defender, in: b, s).contains { spec(of: $0)?.winsTiesDefending == true }
    }

    func resolveRound(_ s: inout GameState) {
        let b = s.battle!
        let a = battleTotal(b.attacker, tiles: b.drawn[b.attacker]!, in: b, s)
        let d = battleTotal(b.defender, tiles: b.drawn[b.defender]!, in: b, s)
        s.events.append(.battleRound(attacker: a, defender: d))
        if a == d && !defenderWinsTies(b, s) {
            // Re-fight from the draw; the defender can't withdraw now.
            s.battle!.round += 1
            beginRound(&s)
            return
        }
        finishBattle(winner: a > d ? b.attacker : b.defender, in: &s)
    }

    func finishBattle(winner: FactionID, in s: inout GameState) {
        let b = s.battle!
        let loser = b.opponent(of: winner)
        let vp = b.unitsAtStart[loser]!
        s.factions[winner]!.victoryPoints += vp
        s.events.append(.battleWon(winner, b.region, victoryPoints: vp))
        s.battle!.loser = loser
        // Dragons in a winning attack are spent.
        if winner == b.attacker {
            for u in force(winner, in: b, s) where u.type == .dragon { eliminate(u.id, captor: nil, in: &s) }
        }
        // Castles and citadels can't retreat: they fall, and count as the casualty.
        let forts = force(loser, in: b, s).filter { $0.type == .castle || $0.type == .citadel }
        if forts.isEmpty {
            s.battle!.step = .casualty
        } else {
            for u in forts { eliminate(u.id, captor: winner, in: &s) }
            beginRetreat(&s)
        }
    }

    func beginRetreat(_ s: inout GameState) {
        let b = s.battle!
        let loser = b.loser!
        let remaining = force(loser, in: b, s)
        if remaining.isEmpty { s.battle = nil; return }
        if fallbackDestinations(for: loser, from: b.region, units: remaining, s).isEmpty {
            for u in remaining { eliminate(u.id, captor: nil, in: &s) }
            s.battle = nil
            return
        }
        s.battle!.step = .retreat
    }

    // MARK: - Decisions

    func applyBattleDecision(_ action: Action, by f: FactionID, to s: inout GameState) throws {
        let b = s.battle!
        switch (b.step, action) {
        case (.withdraw, .withdraw(let dest)):
            guard withdrawOptions(b, s).contains(dest) else { throw EngineError("cannot withdraw to \(dest)") }
            fallBack(f, to: dest, retreating: false, in: &s)
        case (.withdraw, .stand):
            beginRound(&s)
        case (.substitute, .substitute(let tile, let index)):
            guard handTile(tile, of: f, in: s) != nil else { throw EngineError("tile \(tile) is not in hand") }
            guard b.drawn[f]!.indices.contains(index) else { throw EngineError("no battle tile \(index)") }
            substitute(f, tile: tile, replacing: index, in: &s)
        case (.substitute, .keepTiles):
            substitute(f, tile: nil, replacing: 0, in: &s)
        case (.casualty, .eliminate(let id)):
            guard force(f, in: b, s).contains(where: { $0.id == id }) else { throw EngineError("unit \(id) is not in the battle") }
            eliminate(id, captor: nil, in: &s)
            beginRetreat(&s)
        case (.retreat, .retreat(let dest)):
            guard fallbackDestinations(for: f, from: b.region, units: force(f, in: b, s), s).contains(dest) else {
                throw EngineError("cannot retreat to \(dest)")
            }
            fallBack(f, to: dest, retreating: true, in: &s)
        default:
            throw EngineError("the battle is waiting for a different decision")
        }
    }

    func scriptBattleDecision(_ s: inout GameState) {
        let b = s.battle!
        let f = b.decider
        switch b.step {
        case .withdraw:
            if let dest = script.withdrawal(b, options: withdrawOptions(b, s), in: s, engine: self) {
                fallBack(f, to: dest, retreating: false, in: &s)
            } else {
                beginRound(&s)
            }
        case .substitute:
            let choice = script.substitution(b, for: f, in: s, engine: self)
            substitute(f, tile: choice?.tile, replacing: choice?.replacing ?? 0, in: &s)
        case .casualty:
            eliminate(script.casualty(b, choices: force(f, in: b, s), in: s), captor: nil, in: &s)
            beginRetreat(&s)
        case .retreat:
            let options = fallbackDestinations(for: f, from: b.region, units: force(f, in: b, s), s)
            fallBack(f, to: script.retreat(b, options: options, in: s, engine: self), retreating: true, in: &s)
        }
    }
}
