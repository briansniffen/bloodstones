/// Mission 1, "Dragon Hunt" (Horse Lords / Tyrant's Lament).
/// For now this holds only the printed map facts; the Dragon Rider turn
/// logic will live here behind the mission protocol.
public enum Mission1DragonHunt {
    public static let mapId = "tyrants_lament"

    /// Dragon Rider armies: where each starts and the fixed path it follows,
    /// as printed on the mission's Armies page.
    public struct ArmyRoute: Sendable {
        public let number: Int
        public let start: RegionID
        public let path: [RegionID]
    }

    public static let armyRoutes: [ArmyRoute] = [
        ArmyRoute(number: 1, start: 50, path: [51, 50, 49, 48, 36, 45, 53, 61]),
        ArmyRoute(number: 2, start: 67, path: [59, 67, 56, 55, 46, 53, 61]),
        ArmyRoute(number: 3, start: 68, path: [69, 68, 66, 65, 64, 63, 62, 61]),
    ]

    /// North of the Hill Folk line: out of the game (Brian, 12 Oct 2026).
    public static let outOfPlay: Set<RegionID> = Set(1...25).union([31, 32, 33])

    /// Hill Folk units may not be attacked, so their regions cannot be entered.
    public static let hillFolkRegions: Set<RegionID> = [26, 34, 27, 29, 30, 39, 41]

    public static let playerCitadel: RegionID = 61
    public static let dragonStarts: [RegionID] = [49, 66]

    /// Which Dragon Rider units make up each army. Dragons and the lone
    /// skirmisher on 52 belong to no army.
    public struct State: Codable, Sendable, Equatable {
        public var armies: [Int: [Int]]   // army number → unit IDs
        /// Each dragon's starting region, for withdrawing "towards" it.
        public var dragonHomes: [Int: RegionID] = [:]
        /// Where the Dragon Rider turn has got to; nil between turns.
        public var step: TurnStep?
        public var activeArmy: Int?
        /// Set when the Dragon Riders had to draw from an empty bag.
        public var outOfTiles = false
    }

    public enum TurnStep: String, Codable, Sendable {
        case capture, contested, draw, move, dragons, village, desert
    }

    /// Which army a drawn Dragon Rider tile activates.
    public static func army(activatedBy unit: UnitType) -> Int {
        switch unit {
        case .castle, .skirmishers: 1
        case .ship, .siegeEngine: 2
        default: 3
        }
    }

    /// The printed setup. The player skips normal setup and starts with 7
    /// tiles; the Dragon Riders start with an empty hand (Brian, 12 Oct 2026).
    public static func initialState(catalog: FactionCatalog, seed: UInt64) -> GameState {
        // Turn order follows the mission's listing: player, Hill Folk, Dragon Riders.
        var s = GameState(mapId: mapId, catalog: catalog, seed: seed,
                          turnOrder: [.horseLords, .hillFolk, .dragonRiders])

        s.placeCitadel(.horseLords, at: 61)
        for unit in [UnitType.cavalry, .shield, .leader, .swords] {
            s.setUp(unit, for: .horseLords, at: 61)
        }
        s.setUp(.ship, for: .horseLords, at: 62)

        for r in [26, 34] { s.setUp(.ship, for: .hillFolk, at: r) }
        for r in [27, 29, 30, 39, 41] { s.setUp(.castle, for: .hillFolk, at: r) }

        s.placeCitadel(.dragonRiders, at: 60)
        var homes: [Int: RegionID] = [:]
        for r in dragonStarts { homes[s.setUp(.dragon, for: .dragonRiders, at: r).id] = r }
        s.setUp(.skirmishers, for: .dragonRiders, at: 52)
        var armies: [Int: [Int]] = [:]
        for route in armyRoutes {
            armies[route.number] = [UnitType.lizardmen, .swords, .shield, .cavalry].map {
                s.setUp($0, for: .dragonRiders, at: route.start).id
            }
        }
        for r in [50, 51, 52, 59, 67, 68, 69] { s.placeVillage(.dragonRiders, at: r) }
        s.mission = .dragonHunt(State(armies: armies, dragonHomes: homes))

        s.humans = [.horseLords]
        s.draw(7, for: .horseLords)
        return s
    }

    public static func engine(map: MapGraph, catalog: FactionCatalog) -> Engine {
        Engine(map: map, catalog: catalog, script: Script())
    }

    public static func route(_ army: Int) -> ArmyRoute { armyRoutes.first { $0.number == army }! }

    /// "Citadel/Castle → Skirmisher → Lizardman → Shield → Siege Engine →
    /// Sword → Cavalry → Leader → Dragon" (campaign rules, Unit Losses).
    static let lossOrder: [UnitType] = [.citadel, .castle, .skirmishers, .lizardmen, .shield,
                                        .siegeEngine, .swords, .cavalry, .leader, .dragon]
}

// MARK: - Non-player behaviour

extension Mission1DragonHunt {
    public struct Script: MissionScript {
        public init() {}

        private static let dr = FactionID.dragonRiders

        public func isEnterable(_ region: RegionID, in s: GameState) -> Bool {
            !outOfPlay.contains(region) && !hillFolkRegions.contains(region)
        }

        public func regroups(_ faction: FactionID) -> Bool { faction != Self.dr }

        public func outcome(_ s: GameState) -> Outcome? {
            guard case .dragonHunt(let m) = s.mission else { return nil }
            if !s.units.contains(where: { $0.faction == Self.dr && $0.type == .dragon }) {
                return .victory("Both dragons are slain")
            }
            if m.outOfTiles { return .defeat("The Dragon Riders cannot draw a tile") }
            if !s.units.contains(where: { $0.faction == .horseLords && $0.type == .citadel }) {
                return .defeat("Your citadel was captured")
            }
            if s.factions[.horseLords]!.regroups >= 2 { return .defeat("You reached 2 on the Regroup track") }
            return nil
        }

        private func state(_ s: GameState) -> State {
            guard case .dragonHunt(let m) = s.mission else { preconditionFailure("not Mission 1") }
            return m
        }

        private func update(_ s: inout GameState, _ body: (inout State) -> Void) {
            var m = state(s)
            body(&m)
            s.mission = .dragonHunt(m)
        }

        // MARK: Turn

        public func step(_ s: inout GameState, engine: Engine) -> Bool {
            // The Hill Folk are neutral and never act.
            guard s.activeFaction == Self.dr else { return true }
            switch state(s).step ?? .capture {
            case .capture:
                // Any player village where Dragon Riders stand is taken, free.
                let occupied = Set(s.units(of: Self.dr).map(\.region))
                for v in s.villages where v.faction != Self.dr && occupied.contains(v.region) {
                    engine.takeVillage(v, by: Self.dr, in: &s)
                }
                update(&s) { $0.step = .contested }
            case .contested:
                // Units sharing a region with the player's must fight first.
                if let r = s.contestedRegions(for: Self.dr).first {
                    engine.startBattle(at: r, attacker: Self.dr, in: &s)
                } else {
                    update(&s) { $0.step = .draw }
                }
            case .draw:
                guard let tile = s.factions[Self.dr]!.drawFromBag(using: &s.rng) else {
                    update(&s) { $0.outOfTiles = true; $0.step = nil }
                    return false
                }
                s.factions[Self.dr]!.hand.append(tile)
                let n = army(activatedBy: tile.unit)
                s.events.append(.armyActivated(army: n, by: tile.unit))
                update(&s) { $0.activeArmy = n; $0.step = .move }
            case .move:
                update(&s) { $0.step = .dragons }
                moveArmy(state(s).activeArmy!, in: &s, engine: engine)
            case .dragons:
                moveDragons(in: &s, engine: engine)
                update(&s) { $0.step = .village }
            case .village:
                buildVillage(for: state(s).activeArmy!, in: &s, engine: engine)
                update(&s) { $0.step = .desert }
            case .desert:
                engine.removeUnitsInDesert(of: Self.dr, in: &s)
                update(&s) { $0.step = nil; $0.activeArmy = nil }
                return true
            }
            return false
        }

        private func armyUnits(_ n: Int, _ s: GameState) -> [MapUnit] {
            state(s).armies[n]!.compactMap { s.unit($0) }
        }

        /// Land regions, plus seas holding a Dragon Rider ship, open to an army.
        private func armyPassable(_ s: GameState, _ engine: Engine) -> (RegionID) -> Bool {
            { r in
                isEnterable(r, in: s)
                    && (engine.map.terrain(of: r) != .sea || engine.hasOwnShip(Self.dr, in: r, s))
                    && engine.map.terrain(of: r) != .mountains
            }
        }

        /// One step along the army's path, or back towards it. A sea step
        /// needs a Dragon Rider ship there: with one, the army crosses to the
        /// land beyond; without, it builds one instead of moving.
        private func moveArmy(_ n: Int, in s: inout GameState, engine: Engine) {
            let units = armyUnits(n, s)
            guard let here = units.first?.region else { return }
            let path = route(n).path
            let ahead: [RegionID]
            if let i = path.firstIndex(of: here) {
                ahead = Array(path[(i + 1)...])
            } else {
                let passable = armyPassable(s, engine)
                let dist = engine.map.distances(from: here, through: passable)
                guard let target = path.filter({ dist[$0] != nil }).min(by: { (dist[$0]!, $0) < (dist[$1]!, $1) }),
                      let back = engine.map.shortestPath(from: here, to: target, through: passable) else {
                    s.events.append(.armyWaits(army: n, here))
                    return
                }
                ahead = Array(back.dropFirst())
            }
            guard let next = ahead.first else { return }   // at the end of the path

            var dest = next
            if engine.map.terrain(of: next) == .sea {
                if engine.hasOwnShip(Self.dr, in: next, s) {
                    guard !s.hasEnemyUnits(of: Self.dr, in: next), ahead.count > 1 else {
                        s.events.append(.armyWaits(army: n, here))
                        return
                    }
                    dest = ahead[1]
                } else {
                    buildShip(at: next, army: n, here: here, in: &s, engine: engine)
                    return
                }
            }
            guard isEnterable(dest, in: s) else { s.events.append(.armyWaits(army: n, here)); return }
            for u in units { s.units[s.units.firstIndex { $0.id == u.id }!].region = dest }
            s.events.append(.moved(Self.dr, units: units.map(\.id), from: here, to: dest))
            if s.hasEnemyUnits(of: Self.dr, in: dest) {
                engine.startBattle(at: dest, attacker: Self.dr, in: &s)
            }
        }

        /// A ship tile from hand, paid for with one other hand tile (the
        /// lowest, keeping other ships if possible). With none, the army waits.
        private func buildShip(at sea: RegionID, army n: Int, here: RegionID, in s: inout GameState, engine: Engine) {
            let hand = s.factions[Self.dr]!.hand.sorted { $0.id < $1.id }
            guard let ship = hand.first(where: { $0.unit == .ship }),
                  let pay = hand.filter({ $0.id != ship.id })
                    .min(by: { ($0.pips, $0.unit == .ship ? 1 : 0, $0.id) < ($1.pips, $1.unit == .ship ? 1 : 0, $1.id) })
            else {
                s.events.append(.armyWaits(army: n, here))
                return
            }
            s.factions[Self.dr]!.hand.removeAll { $0.id == ship.id }
            engine.discard([pay.id], from: Self.dr, in: &s)
            s.place(ship, at: sea)
            s.events.append(.built(Self.dr, .ship, sea))
            if s.hasEnemyUnits(of: Self.dr, in: sea) {
                engine.startBattle(at: sea, attacker: Self.dr, in: &s)
            }
        }

        /// Dragons fly onto an adjacent player village with no player units
        /// on it, furthest from the citadel first; lower numbers break ties.
        private func moveDragons(in s: inout GameState, engine: Engine) {
            let citadel = s.units(of: Self.dr).first { $0.type == .citadel }?.region
            let dist = citadel.map { engine.map.distances(from: $0) } ?? [:]
            let dragons = s.units(of: Self.dr).filter { $0.type == .dragon }
                .sorted { (-(dist[$0.region] ?? 0), $0.id) < (-(dist[$1.region] ?? 0), $1.id) }
            for d in dragons {
                let target = engine.map.neighbors(of: d.region).first { r in
                    isEnterable(r, in: s)
                        && s.villages.contains { $0.region == r && $0.faction != Self.dr }
                        && !s.hasEnemyUnits(of: Self.dr, in: r)
                }
                guard let target else { continue }
                s.units[s.units.firstIndex { $0.id == d.id }!].region = target
                s.events.append(.moved(Self.dr, units: [d.id], from: d.region, to: target))
            }
        }

        /// One village where the activated army stands, if there isn't one
        /// already. Non-player villages ignore the adjacency rules.
        private func buildVillage(for n: Int, in s: inout GameState, engine: Engine) {
            guard let r = armyUnits(n, s).first?.region,
                  engine.villageCost(r) != nil, isEnterable(r, in: s),
                  s.factions[Self.dr]!.villageSupply > 0,
                  !s.villages.contains(where: { $0.region == r }),
                  !s.units.contains(where: { $0.region == r && ($0.faction != Self.dr || $0.type == .citadel) })
            else { return }
            s.placeVillage(Self.dr, at: r)
            s.events.append(.villageBuilt(Self.dr, r))
        }

        // MARK: Battle decisions

        /// Only dragons withdraw: towards their starting region if they can,
        /// otherwise to the highest-numbered option.
        public func withdrawal(_ b: Battle, options: [RegionID], in s: GameState, engine: Engine) -> RegionID? {
            guard let dragon = engine.force(b.defender, in: b, s).first(where: { $0.type == .dragon }),
                  !options.isEmpty else { return nil }
            let home = state(s).dragonHomes[dragon.id] ?? dragon.region
            let dist = engine.map.distances(from: home)
            let closer = options.filter { dist[$0, default: .max] < dist[b.region, default: .max] }
            if let best = closer.min(by: { (dist[$0]!, $0) < (dist[$1]!, $1) }) { return best }
            return options.max()
        }

        /// Substitute one tile only if that wins the battle outright: the
        /// lowest tile that does, sparing ships.
        public func substitution(_ b: Battle, for f: FactionID, in s: GameState, engine: Engine) -> (tile: Int, replacing: Int)? {
            guard let mine = b.drawn[f], let theirs = b.drawn[b.opponent(of: f)],
                  !engine.wins(f, tiles: mine, against: theirs, in: b, s) else { return nil }
            let lowest = mine.indices.max()!
            let hand = s.factions[f]!.hand.sorted {
                ($0.pips, $0.unit == .ship ? 1 : 0, $0.id) < ($1.pips, $1.unit == .ship ? 1 : 0, $1.id)
            }
            for t in hand {
                var tiles = mine
                tiles[lowest] = t.pips
                if engine.wins(f, tiles: tiles, against: theirs, in: b, s) { return (t.id, lowest) }
            }
            return nil
        }

        public func casualty(_ b: Battle, choices: [MapUnit], in s: GameState) -> Int {
            choices.min { a, c in
                (lossOrder.firstIndex(of: a.type) ?? 0, a.id) < (lossOrder.firstIndex(of: c.type) ?? 0, c.id)
            }!.id
        }

        /// Back along the army's path if possible, else the lowest-numbered option.
        public func retreat(_ b: Battle, options: [RegionID], in s: GameState, engine: Engine) -> RegionID {
            let ids = Set(s.units.filter { $0.region == b.region && $0.faction == Self.dr }.map(\.id))
            if let (n, _) = state(s).armies.first(where: { !ids.isDisjoint(with: $0.value) }) {
                let path = route(n).path
                if let i = path.firstIndex(of: b.region), i > 0, options.contains(path[i - 1]) {
                    return path[i - 1]
                }
            }
            return options.min()!
        }
    }
}
