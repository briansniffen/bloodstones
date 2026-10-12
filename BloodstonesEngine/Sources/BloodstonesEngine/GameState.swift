/// A unit on the map: a tile that was built, or a citadel.
public struct MapUnit: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let faction: FactionID
    public let type: UnitType
    /// The tile this unit was built from; nil for a citadel. It goes to the
    /// owner's discard pile when the unit is eliminated.
    public let tile: Tile?
    public var region: RegionID
}

public struct Village: Codable, Sendable, Hashable {
    public let faction: FactionID
    public var region: RegionID
}

/// Everything one faction holds off the map.
public struct FactionState: Codable, Sendable, Equatable {
    public var bag: [Tile]
    public var hand: [Tile] = []
    public var discard: [Tile] = []
    public var handSize: Int
    public var villageSupply: Int
    public var victoryPoints = 0
    public var regroups = 0
    /// Enemy villages captured; they score at the end of the game.
    public var capturedVillages = 0
    public var capturedCitadels = 0

    /// Draws one tile at random from the bag, or nil if the bag is empty.
    /// Regrouping is a rules decision, so it is the caller's job.
    public mutating func drawFromBag(using rng: inout SeededGenerator) -> Tile? {
        guard !bag.isEmpty else { return nil }
        return bag.remove(at: rng.index(below: bag.count))
    }

    /// Takes a specific kind of tile out of the bag for setup (lowest ID).
    mutating func takeFromBag(_ unit: UnitType) -> Tile? {
        guard let i = bag.indices.filter({ bag[$0].unit == unit })
                .min(by: { bag[$0].id < bag[$1].id }) else { return nil }
        return bag.remove(at: i)
    }
}

/// Mission-specific state. One case per mission, so `GameState` stays a
/// plain Codable value.
public enum MissionState: Codable, Sendable, Equatable {
    case dragonHunt(Mission1DragonHunt.State)
}

public struct GameState: Codable, Sendable, Equatable {
    public var mapId: String
    public var rng: SeededGenerator
    /// Play order; the solo player is first and non-player factions follow.
    public var turnOrder: [FactionID]
    public var activeIndex = 0
    public var turnNumber = 1
    public var factions: [FactionID: FactionState]
    public var units: [MapUnit] = []
    public var villages: [Village] = []
    public var nextUnitID = 1
    public var mission: MissionState?

    public var activeFaction: FactionID { turnOrder[activeIndex] }

    public func units(in region: RegionID) -> [MapUnit] { units.filter { $0.region == region } }
    public func units(of faction: FactionID) -> [MapUnit] { units.filter { $0.faction == faction } }
    public func villages(in region: RegionID) -> [Village] { villages.filter { $0.region == region } }

    /// Builds a unit from `tile` at `region`. Payment is the caller's job.
    @discardableResult
    mutating func place(_ tile: Tile, at region: RegionID) -> MapUnit {
        let unit = MapUnit(id: nextUnitID, faction: tile.faction, type: tile.unit, tile: tile, region: region)
        nextUnitID += 1
        units.append(unit)
        return unit
    }

    @discardableResult
    mutating func placeCitadel(_ faction: FactionID, at region: RegionID) -> MapUnit {
        let unit = MapUnit(id: nextUnitID, faction: faction, type: .citadel, tile: nil, region: region)
        nextUnitID += 1
        units.append(unit)
        return unit
    }

    /// Takes a tile of the given type out of `faction`'s bag and places it.
    /// Setup only: the mission says which units start where.
    @discardableResult
    mutating func setUp(_ unit: UnitType, for faction: FactionID, at region: RegionID) -> MapUnit {
        guard let tile = factions[faction]!.takeFromBag(unit) else {
            preconditionFailure("\(faction) has no \(unit) left for setup")
        }
        return place(tile, at: region)
    }

    mutating func placeVillage(_ faction: FactionID, at region: RegionID) {
        precondition(factions[faction]!.villageSupply > 0, "\(faction) is out of villages")
        factions[faction]!.villageSupply -= 1
        villages.append(Village(faction: faction, region: region))
    }

    /// Draws up to `count` tiles into `faction`'s hand; stops if the bag runs out.
    mutating func draw(_ count: Int, for faction: FactionID) {
        for _ in 0..<count {
            guard let tile = factions[faction]!.drawFromBag(using: &rng) else { return }
            factions[faction]!.hand.append(tile)
        }
    }
}

extension GameState {
    /// A fresh state with every listed faction's full bag and no pieces.
    /// Tile IDs are assigned in `FactionID.allCases` order so they don't
    /// depend on which factions are in the game.
    init(mapId: String, catalog: FactionCatalog, seed: UInt64, turnOrder: [FactionID]) {
        var factions: [FactionID: FactionState] = [:]
        var firstID = 1
        for id in FactionID.allCases {
            let bag = catalog.bag(for: id, firstID: firstID)
            firstID += 100
            guard turnOrder.contains(id) else { continue }
            let spec = catalog[id]
            factions[id] = FactionState(bag: bag, handSize: spec.handSize, villageSupply: spec.villages)
        }
        self.init(mapId: mapId, rng: SeededGenerator(seed: seed), turnOrder: turnOrder, factions: factions)
    }
}
