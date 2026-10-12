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
        for r in dragonStarts { s.setUp(.dragon, for: .dragonRiders, at: r) }
        s.setUp(.skirmishers, for: .dragonRiders, at: 52)
        var armies: [Int: [Int]] = [:]
        for route in armyRoutes {
            armies[route.number] = [UnitType.lizardmen, .swords, .shield, .cavalry].map {
                s.setUp($0, for: .dragonRiders, at: route.start).id
            }
        }
        for r in [50, 51, 52, 59, 67, 68, 69] { s.placeVillage(.dragonRiders, at: r) }
        s.mission = .dragonHunt(State(armies: armies))

        s.draw(7, for: .horseLords)
        return s
    }
}
