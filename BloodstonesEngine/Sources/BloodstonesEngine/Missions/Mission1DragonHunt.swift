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
}
