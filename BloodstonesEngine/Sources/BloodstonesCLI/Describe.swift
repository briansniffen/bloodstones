import BloodstonesEngine

/// Plain-text descriptions of game pieces, actions and events.
struct Describer {
    let engine: Engine
    let you: FactionID

    func name(_ t: UnitType) -> String {
        switch t {
        case .siegeEngine: "Siege Engine"
        default: t.rawValue.prefix(1).uppercased() + t.rawValue.dropFirst()
        }
    }

    func name(_ f: FactionID) -> String { engine.catalog[f].name }

    func region(_ r: RegionID) -> String { "\(r) \(engine.map.terrain(of: r).rawValue)" }

    func unit(_ u: MapUnit) -> String { "\(name(u.type))#\(u.id)" }

    func tile(_ t: Tile) -> String { "[\(t.id)] \(name(t.unit)) \(t.pips)" }

    func tiles(_ ids: [Int], in s: GameState) -> String {
        let hand = s.factions[you]!.hand
        let parts = ids.map { id in hand.first { $0.id == id }.map(tile) ?? "[\(id)]" }
        let pips = ids.compactMap { id in hand.first { $0.id == id }?.pips }.reduce(0, +)
        return parts.joined(separator: " + ") + (ids.count > 1 ? " (\(pips) pips)" : "")
    }

    /// Looks units up in `s`, then in `before` (for units since eliminated).
    func units(_ ids: [Int], in s: GameState, before: GameState? = nil) -> String {
        ids.map { id in (s.unit(id) ?? before?.unit(id)).map(unit) ?? "#\(id)" }.joined(separator: ", ")
    }

    func action(_ a: Action, in s: GameState) -> String {
        switch a {
        case .endPhase:
            switch s.phase {
            case .capture: return "End capture phase → main actions"
            case .main: return "End main actions → construct villages"
            case .construct: return "End turn (desert check, draw back to \(s.factions[you]!.handSize))"
            default: return "End phase"
            }
        case .captureVillage(let r, let pay):
            return "Capture village in \(region(r)) — " + (pay.map { "pay \(tiles([$0], in: s))" } ?? "from \(s.pipBudget ?? 0) pips left")
        case .constructVillage(let r, let pay):
            return "Build village in \(region(r)) — " + (pay.map { "pay \(tiles([$0], in: s))" } ?? "from \(s.pipBudget ?? 0) pips left")
        case .build(let t, let r, let pay):
            let tileName = s.factions[you]!.hand.first { $0.id == t }.map { name($0.unit) } ?? "#\(t)"
            return "Build \(tileName) [\(t)] in \(region(r))" + (pay.isEmpty ? " (free)" : " — discard \(tiles(pay, in: s))")
        case .move(let legs, let pay):
            let cost = legs.reduce(0) { $0 + ((try? engine.legCost($1, by: you, in: s)) ?? 0) }
            let what = legs.map { leg in
                let from = s.unit(leg.units[0])?.region ?? 0
                return "\(units(leg.units, in: s)): \(from) → \(region(leg.to))"
            }.joined(separator: "; ")
            return "Move \(what) — cost \(cost), pay \(tiles(pay, in: s))"
        case .battle(let r):
            let foes = s.units(in: r).filter { $0.faction != you }
            return "Fight in \(region(r)) against \(foes.map(unit).joined(separator: ", "))"
        case .withdraw(let r): return "Withdraw to \(region(r))"
        case .stand: return "Stand and fight"
        case .substitute(let t, let i):
            let drawn = s.battle?.drawn[you]?[i] ?? 0
            return "Substitute \(tiles([t], in: s)) for your \(drawn)"
        case .keepTiles: return "Keep your Battle tiles"
        case .eliminate(let id): return "Lose \(s.unit(id).map(unit) ?? "#\(id)")"
        case .retreat(let r): return "Retreat to \(region(r))"
        }
    }

    func event(_ e: Event, in s: GameState, before: GameState) -> String? {
        switch e {
        case .turnStarted(let f): return "— \(name(f)) turn —"
        case .drew(let f, let n): return "\(name(f)) drew \(n) tile\(n == 1 ? "" : "s")"
        case .regrouped(let f, let n, let v): return "\(name(f)) REGROUPED (\(n) so far), scoring \(v) VP"
        case .built(let f, let t, let r): return "\(name(f)) built \(name(t)) in \(region(r))"
        case .moved(let f, let ids, let from, let to):
            return "\(name(f)) moved \(units(ids, in: s, before: before)) \(from) → \(region(to))"
        case .villageBuilt(let f, let r): return "\(name(f)) built a village in \(region(r))"
        case .villageCaptured(let by, let from, let r): return "\(name(by)) captured a \(name(from)) village in \(region(r))"
        case .battleStarted(let r, let a, let d): return "BATTLE in \(region(r)): \(name(a)) attack \(name(d))"
        case .battleTiles(let f, let v): return "  \(name(f)) drew Battle tiles \(v)"
        case .substituted(let f, let p): return "  \(name(f)) substituted a \(p)"
        case .battleRound(let a, let d): return "  Totals: attacker \(a), defender \(d)" + (a == d ? " (tie)" : "")
        case .battleWon(let f, let r, let vp): return "  \(name(f)) win in \(r) (+\(vp) VP)"
        case .withdrew(let f, let from, let to): return "  \(name(f)) withdrew \(from) → \(region(to))"
        case .retreated(let f, let from, let to): return "  \(name(f)) retreated \(from) → \(region(to))"
        case .eliminated(let f, let t, let r): return "  \(name(f)) lost \(name(t)) in \(r)"
        case .armyActivated(let n, let t): return "Dragon Riders drew \(name(t)): Army \(n) activates"
        case .armyWaits(let n, let r): return "Army \(n) waits in \(r)"
        case .gameOver(let o):
            switch o {
            case .victory(let why): return "*** VICTORY: \(why) ***"
            case .defeat(let why): return "*** DEFEAT: \(why) ***"
            }
        }
    }
}
