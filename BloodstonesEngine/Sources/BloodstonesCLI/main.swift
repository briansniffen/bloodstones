import BloodstonesEngine
import Foundation

// A text-mode player for Mission 1, for trying the rules before the app exists.
//   swift run bloodstones [--seed N] [--data DIR]

let help = """
Commands:
  <n>              do action n from the list
  <n> pay a,b      do action n, paying with these tile IDs instead
  m <from> <to>    moves between two regions (the summary shows where you can go)
  l [words…]       list actions; words filter them (e.g. "l build", "l village")
  r <region>       a region: terrain, neighbours, pieces
  s                status
  u                undo
  save <file>      save the game as JSON;  load <file>  load one
  h                this help;  q  quit
"""

// MARK: - Setup

var args = Array(CommandLine.arguments.dropFirst())
@MainActor func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

/// The repo's `data/`, found by walking up from the current directory.
@MainActor func findData() -> URL? {
    if let d = option("--data") { return URL(fileURLWithPath: d) }
    var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    while dir.path != "/" {
        let candidate = dir.appendingPathComponent("data")
        if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("factions.json").path) {
            return candidate
        }
        dir.deleteLastPathComponent()
    }
    return nil
}

guard let data = findData() else {
    print("Can't find data/factions.json; run inside the repo or pass --data DIR")
    exit(1)
}
let map = try MapGraph(contentsOf: data.appendingPathComponent("maps/\(Mission1DragonHunt.mapId).json"))
let catalog = try FactionCatalog(contentsOf: data.appendingPathComponent("factions.json"))
let engine = Mission1DragonHunt.engine(map: map, catalog: catalog)
let you = FactionID.horseLords
let d = Describer(engine: engine, you: you)

let seed = option("--seed").flatMap(UInt64.init) ?? UInt64(Date().timeIntervalSince1970) % 100_000
var state = Mission1DragonHunt.initialState(catalog: catalog, seed: seed)
var history: [GameState] = []

// MARK: - Display

@MainActor func pieces(in r: RegionID, _ s: GameState) -> String {
    var parts: [String] = []
    for f in FactionID.allCases {
        let us = s.units(in: r).filter { $0.faction == f }
        let vs = s.villages(in: r).filter { $0.faction == f }
        guard !us.isEmpty || !vs.isEmpty else { continue }
        var p = "\(d.name(f)): " + us.map(d.unit).joined(separator: ", ")
        if !vs.isEmpty { p += (us.isEmpty ? "" : ", ") + "\(vs.count) village\(vs.count > 1 ? "s" : "")" }
        parts.append(p)
    }
    return parts.isEmpty ? "empty" : parts.joined(separator: " | ")
}

@MainActor func showRegion(_ r: RegionID, _ s: GameState) {
    guard map.regions[r] != nil else { print("No region \(r)"); return }
    let off = !engine.script.isEnterable(r, in: s) ? " (off limits)" : ""
    print("\(d.region(r))\(off): \(pieces(in: r, s))")
    print("  neighbours: " + map.neighbors(of: r).map { n in
        let mark = engine.script.isEnterable(n, in: s) ? "" : "×"
        return "\(n)\(map.terrain(of: n).rawValue.prefix(1))\(mark)"
    }.joined(separator: " "))
}

@MainActor func showStatus(_ s: GameState) {
    let hl = s.factions[you]!
    let dr = s.factions[.dragonRiders]!
    print("")
    print("Turn \(s.turnNumber) · \(d.name(s.activeFaction)) · \(s.phase.rawValue)"
          + (s.pipBudget.map { " · \($0) pips left from this phase's tile" } ?? ""))
    print("Horse Lords: VP \(hl.victoryPoints) · regroups \(hl.regroups)/2 (2 loses) · bag \(hl.bag.count) · discard \(hl.discard.count) · villages left \(hl.villageSupply) · captured \(hl.capturedVillages)")
    print("Hand: " + hl.hand.sorted { $0.id < $1.id }.map { t in
        d.tile(t) + (t.buildCost.map { $0 == 0 ? " (free)" : " (build \($0))" } ?? " (no unit)")
    }.joined(separator: "  "))
    let mine = Dictionary(grouping: s.units(of: you), by: \.region)
    print("Your units:")
    for (r, us) in mine.sorted(by: { $0.key < $1.key }) {
        print("  \(d.region(r)): " + us.map(d.unit).joined(separator: ", "))
    }
    let villages = s.villages.filter { $0.faction == you }.map(\.region).sorted()
    print("Your villages: " + (villages.isEmpty ? "none" : villages.map(String.init).joined(separator: ", ")))

    print("Dragon Riders: bag \(dr.bag.count) (the clock) · hand \(dr.hand.count)"
          + (dr.hand.isEmpty ? "" : " [\(dr.hand.map { "\(d.name($0.unit)) \($0.pips)" }.joined(separator: ", "))]"))
    if case .dragonHunt(let m) = s.mission {
        for (n, ids) in m.armies.sorted(by: { $0.key < $1.key }) {
            let us = ids.compactMap { s.unit($0) }
            guard let here = us.first?.region else { print("  Army \(n): destroyed"); continue }
            let path = Mission1DragonHunt.route(n).path
            let next = path.firstIndex(of: here).flatMap { $0 + 1 < path.count ? path[$0 + 1] : nil }
            print("  Army \(n) in \(d.region(here))" + (next.map { " → next \($0)" } ?? " (off its path)")
                  + ": " + us.map { d.name($0.type) }.joined(separator: ", "))
        }
        let armyIDs = Set(m.armies.values.flatMap { $0 })
        let others = s.units(of: .dragonRiders).filter { !armyIDs.contains($0.id) }
        print("  Others: " + others.map { "\(d.unit($0)) in \($0.region)" }.joined(separator: ", "))
    }
    let drVillages = s.villages.filter { $0.faction == .dragonRiders }.map(\.region).sorted()
    print("  Villages: " + drVillages.map(String.init).joined(separator: ", "))

    if let b = s.battle { showBattle(b, s) }
}

@MainActor func showBattle(_ b: Battle, _ s: GameState) {
    print("BATTLE in \(d.region(b.region)), round \(b.round): \(d.name(b.attacker)) attacking \(d.name(b.defender))")
    for f in [b.attacker, b.defender] {
        print("  \(d.name(f)): " + engine.force(f, in: b, s).map(d.unit).joined(separator: ", "))
    }
    if let mine = b.drawn[you] {
        let total = engine.battleTotal(you, tiles: mine, in: b, s)
        print("  Your Battle tiles: \(mine) → total \(total) with modifiers (top three count)")
    }
    let foe = b.opponent(of: you)
    if b.drawn[foe] == nil { print("  \(d.name(foe)) draw after you decide") }
}

/// Lists the actions matching `filter` (all words), numbered by position
/// in the full list so numbers stay valid whatever the filter.
@MainActor func list(_ actions: [Action], filter: [String], _ s: GameState) {
    var shown = 0
    for (i, a) in actions.enumerated() {
        let text = d.action(a, in: s)
        guard filter.allSatisfy({ text.lowercased().contains($0.lowercased()) }) else { continue }
        print(String(format: "%4d  ", i) + text)
        shown += 1
    }
    if shown == 0 { print("  (no matching actions)") }
}

/// Short lists in full; long ones as everything but moves, plus a count
/// of moves from each region.
@MainActor func showActions(_ s: GameState) {
    let actions = engine.legalActions(in: s)
    if s.outcome != nil { print("Game over. 'u' to undo, 'q' to quit."); return }
    if actions.count <= 25 { list(actions, filter: [], s); return }
    for (i, a) in actions.enumerated() {
        if case .move = a { continue }
        print(String(format: "%4d  ", i) + d.action(a, in: s))
    }
    // Per origin: each destination and the cheapest cost for one unit.
    var reach: [RegionID: [RegionID: Int]] = [:]
    for case .move(let legs, _) in actions where legs[0].units.count == 1 {
        let from = s.unit(legs[0].units[0])!.region
        let cost = (try? engine.legCost(legs[0], by: you, in: s)) ?? 0
        reach[from, default: [:]][legs[0].to] = min(cost, reach[from]?[legs[0].to] ?? .max)
    }
    for (from, dests) in reach.sorted(by: { $0.key < $1.key }) {
        let byCost = dests.sorted { ($0.value, $0.key) < ($1.value, $1.key) }
            .map { "\($0.key):\($0.value)" }.joined(separator: " ")
        print("  Moves from \(from), destination:cost per unit — \(byCost)")
    }
    if let from = reach.keys.min() { print("  Type 'm \(from) <to>' for the unit choices.") }
}

/// Moves from one region to another, numbered as in the full list.
@MainActor func showMoves(from: RegionID, to: RegionID, _ s: GameState) {
    let actions = engine.legalActions(in: s)
    var shown = 0
    for (i, a) in actions.enumerated() {
        guard case .move(let legs, _) = a, legs[0].to == to, s.unit(legs[0].units[0])?.region == from else { continue }
        print(String(format: "%4d  ", i) + d.action(a, in: s))
        shown += 1
    }
    if shown == 0 { print("  No moves from \(from) to \(to).") }
}

@MainActor func play(_ a: Action) {
    do {
        let before = state
        let after = try engine.apply(a, to: state)
        history.append(before)
        state = after
        for e in after.events { if let line = d.event(e, in: after, before: before) { print(line) } }
        showStatus(state)
        showActions(state)
    } catch {
        print("Not allowed: \(error)")
    }
}

/// Swaps the payment in an action for the player's own choice of tiles.
@MainActor func withPayment(_ a: Action, _ ids: [Int]) -> Action? {
    switch a {
    case .move(let legs, _): .move(legs: legs, payWith: ids)
    case .build(let t, let r, _): .build(tile: t, region: r, payWith: ids)
    case .captureVillage(let r, _): ids.count == 1 ? .captureVillage(region: r, payWith: ids[0]) : nil
    case .constructVillage(let r, _): ids.count == 1 ? .constructVillage(region: r, payWith: ids[0]) : nil
    default: nil
    }
}

// MARK: - Loop

print("Bloodstones — Mission 1: Dragon Hunt (Horse Lords). Seed \(seed).")
print("Slay both dragons (on 49 and 66). You lose if the Dragon Riders run out of tiles,")
print("your citadel on 61 falls, or you reach 2 on the Regroup track. 'h' for help.")
showStatus(state)
showActions(state)

while true {
    print("> ", terminator: "")
    guard let line = readLine() else { break }
    let words = line.split(separator: " ").map(String.init)
    guard let cmd = words.first else { continue }
    switch cmd {
    case "q", "quit": exit(0)
    case "h", "help", "?": print(help)
    case "s": showStatus(state); showActions(state)
    case "m":
        let rs = words.dropFirst().compactMap { Int($0) }
        if rs.count == 2 { showMoves(from: rs[0], to: rs[1], state) } else { print("m <from> <to>") }
    case "l": list(engine.legalActions(in: state), filter: Array(words.dropFirst()), state)
    case "r":
        if let r = words.dropFirst().first.flatMap(Int.init) { showRegion(r, state) } else { print("r <region>") }
    case "u":
        if let prev = history.popLast() { state = prev; print("Undone."); showStatus(state); showActions(state) }
        else { print("Nothing to undo.") }
    case "save":
        guard words.count > 1 else { print("save <file>"); continue }
        do {
            try JSONEncoder().encode(state).write(to: URL(fileURLWithPath: words[1]))
            print("Saved to \(words[1]).")
        } catch { print("Save failed: \(error)") }
    case "load":
        guard words.count > 1 else { print("load <file>"); continue }
        do {
            let loaded = try JSONDecoder().decode(GameState.self, from: Data(contentsOf: URL(fileURLWithPath: words[1])))
            history.append(state)
            state = loaded
            showStatus(state); showActions(state)
        } catch { print("Load failed: \(error)") }
    default:
        guard let n = Int(cmd) else { print("Unknown command; 'h' for help."); continue }
        let actions = engine.legalActions(in: state)
        guard actions.indices.contains(n) else { print("No action \(n)."); continue }
        if words.count >= 3, words[1] == "pay" {
            let ids = words[2].split(separator: ",").compactMap { Int($0) }
            guard let a = withPayment(actions[n], ids) else { print("That action doesn't take a payment."); continue }
            play(a)
        } else {
            play(actions[n])
        }
    }
}
