import Foundation
import Testing
@testable import BloodstonesEngine

/// The repo root, found from this file, so tests run against the real data.
let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

func loadMap(_ id: String) throws -> MapGraph {
    try MapGraph(contentsOf: repoRoot.appendingPathComponent("data/maps/\(id).json"))
}

@Suite struct MapGraphTests {
    @Test(arguments: [
        ("tyrants_lament", 75, 198), ("swan_dance", 76, 198), ("lady_of_the_lake", 44, 110),
        ("sorcerers_crucible", 98, 273), ("remains_of_the_past", 69, 177),
    ])
    func allMapsLoad(id: String, regions: Int, edges: Int) throws {
        let map = try loadMap(id)
        #expect(map.mapId == id)
        #expect(map.regions.count == regions)
        let undirected = map.regionIDs.reduce(0) { n, r in n + map.neighbors(of: r).filter { $0 > r }.count }
        #expect(undirected == edges)
        #expect(map.reachable(from: map.regionIDs[0]).count == regions)
    }

    @Test func tyrantsLamentBasics() throws {
        let map = try loadMap("tyrants_lament")
        #expect(map.terrain(of: 61) == .forest)
        #expect(map.terrain(of: 36) == .sea)
        #expect(map.areAdjacent(1, 9))      // added in Brian's review
        #expect(!map.areAdjacent(2, 8))     // one of the March graph's errors
        #expect(map.neighbors(of: 61) == [53, 62])
    }

    @Test func shortestPathPrefersLowerNumbers() throws {
        let map = try loadMap("tyrants_lament")
        // 61 → 63 is two steps, via 53 or 62; ties go low.
        #expect(map.shortestPath(from: 61, to: 63) == [61, 62, 63])
        #expect(map.shortestPath(from: 61, to: 61) == [61])
        let path = try #require(map.shortestPath(from: 61, to: 50))
        #expect(path.count - 1 == map.distances(from: 61)[50])
        for (a, b) in zip(path, path.dropFirst()) { #expect(map.areAdjacent(a, b)) }
    }

    @Test func passabilityIsRespected() throws {
        let map = try loadMap("tyrants_lament")
        // 61's only neighbours are 53 and 62; block both and it is cut off.
        #expect(map.shortestPath(from: 61, to: 50, through: { ![53, 62].contains($0) }) == nil)
        #expect(map.reachable(from: 61, through: { ![53, 62].contains($0) }) == [61])
    }

    @Test func cheapestCostsUseTerrain() throws {
        let map = try loadMap("tyrants_lament")
        // Base movement costs; sea and mountains forbidden for a land unit.
        let pips: [Terrain: Int] = [.plains: 1, .forest: 2, .hills: 3, .desert: 1]
        let costs = map.cheapestCosts(from: 61) { _, to in pips[map.terrain(of: to)] }
        #expect(costs[61] == 0)
        #expect(costs[53] == 2)                 // forest
        #expect(costs[62] == nil)               // sea, not enterable on foot
        #expect(costs[45] == 3)                 // forest 53, then plains 45
    }
}

@Suite struct Mission1MapTests {
    @Test func everyRouteStepIsABorder() throws {
        let map = try loadMap(Mission1DragonHunt.mapId)
        for route in Mission1DragonHunt.armyRoutes {
            #expect(route.path.contains(route.start), "army \(route.number) starts off its path")
            #expect(route.path.last == Mission1DragonHunt.playerCitadel)
            for (a, b) in zip(route.path, route.path.dropFirst()) {
                #expect(map.areAdjacent(a, b), "army \(route.number): \(a)→\(b) is not a border")
            }
        }
    }

    @Test func routesStayInPlay() throws {
        let off = Mission1DragonHunt.outOfPlay.union(Mission1DragonHunt.hillFolkRegions)
        for route in Mission1DragonHunt.armyRoutes {
            #expect(off.isDisjoint(with: route.path))
        }
    }

    @Test func playAreaIsConnected() throws {
        let map = try loadMap(Mission1DragonHunt.mapId)
        let inPlay = map.regionIDs.filter { !Mission1DragonHunt.outOfPlay.contains($0) }
        #expect(inPlay.count == 47)
        let enterable = { (r: RegionID) in
            !Mission1DragonHunt.outOfPlay.contains(r) && !Mission1DragonHunt.hillFolkRegions.contains(r)
        }
        #expect(map.reachable(from: 61, through: enterable).count == 40)
    }
}
