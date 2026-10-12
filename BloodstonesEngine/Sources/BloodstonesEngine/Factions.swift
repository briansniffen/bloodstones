import Foundation

public enum FactionID: String, Codable, Sendable, CaseIterable, CodingKeyRepresentable {
    case dragonRiders, horseLords, necromancers, hillFolk, chaosHorde, corsairs
}

/// Every unit type printed on a tile, plus the citadel (a unit, not a tile).
public enum UnitType: String, Codable, Sendable, CaseIterable {
    case skirmishers, swords, shield, cavalry, siegeEngine, leader, ship, castle, blank
    case lizardmen, dragon, goblins, necromancer, undead, reivers, giant, hordes, axes
    case citadel
}

public enum BonusCondition: String, Codable, Sendable {
    case always, attacking, defending, inForest, inPlains, vsCastleOrCitadel
}

/// One row of a faction card: a kind of tile and how many are in the bag.
public struct TileSpec: Codable, Sendable, Equatable {
    public let unit: UnitType
    public let count: Int
    /// Stone blocks; nil means the tile cannot be built as a unit.
    public let buildCost: Int?
    public let pips: Int
    public let battleBonus: Int
    public let bonusWhen: BonusCondition?
    public let winsTiesDefending: Bool?
    public let mayRemainInDesert: Bool?
    public let movesOneExtraUnitFree: Bool?
    public let carriesLandUnitsAcrossSea: Bool?
    public let immobile: Bool?
    public let alwaysDrawFourInBattle: Bool?
    public let special: String?
}

public struct CitadelSpec: Codable, Sendable, Equatable {
    public let battleBonus: Int
    public let bonusWhen: BonusCondition
}

public struct FactionSpec: Codable, Sendable, Equatable {
    public let faction: FactionID
    public let name: String
    public let handSize: Int
    public let villages: Int
    public let citadel: CitadelSpec?
    public let tiles: [TileSpec]
    /// Kept out of the bag (Necromancer Undead).
    public let asideTiles: [TileSpec]?

    public func spec(for unit: UnitType) -> TileSpec? {
        tiles.first { $0.unit == unit } ?? asideTiles?.first { $0.unit == unit }
    }
}

/// `data/factions.json`, loaded once.
public struct FactionCatalog: Sendable {
    public let factions: [FactionID: FactionSpec]

    public subscript(id: FactionID) -> FactionSpec { factions[id]! }

    private struct File: Decodable { let factions: [FactionSpec] }

    public init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        factions = Dictionary(uniqueKeysWithValues: file.factions.map { ($0.faction, $0) })
    }

    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url))
    }

    /// A faction's full bag of physical tiles, in card order, with IDs
    /// `firstID…`. Tile IDs are what make two Swords distinguishable.
    public func bag(for id: FactionID, firstID: Int) -> [Tile] {
        var next = firstID
        var tiles: [Tile] = []
        for spec in self[id].tiles {
            for _ in 0..<spec.count {
                tiles.append(Tile(id: next, faction: id, unit: spec.unit,
                                  pips: spec.pips, buildCost: spec.buildCost))
                next += 1
            }
        }
        return tiles
    }
}

/// One physical faction tile. Copies the card's pips and build cost so a
/// saved game is readable without the catalog.
public struct Tile: Codable, Sendable, Hashable {
    public let id: Int
    public let faction: FactionID
    public let unit: UnitType
    public let pips: Int
    public let buildCost: Int?
}
