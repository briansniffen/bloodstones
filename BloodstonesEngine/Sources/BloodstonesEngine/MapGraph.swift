import Foundation

public typealias RegionID = Int

public enum Terrain: String, Codable, Sendable, CaseIterable {
    case plains, forest, hills, mountains, desert, sea
}

public struct Region: Codable, Sendable, Equatable {
    public let id: RegionID
    public let terrain: Terrain
    public let adjacentTo: [RegionID]
    public let displayPosition: [Double]
    public let polygon: [[Double]]
}

/// One map from `data/maps/<id>.json`: terrain, borders and the graph
/// queries the rules and the mission scripts need. Immutable once loaded.
public struct MapGraph: Sendable {
    public let mapId: String
    public let displayName: String
    public let regions: [RegionID: Region]
    /// Ascending region IDs, so every traversal is deterministic.
    public let regionIDs: [RegionID]
    private let neighborList: [RegionID: [RegionID]]

    public enum LoadError: Error, Equatable {
        case unknownNeighbor(region: RegionID, neighbor: RegionID)
        case duplicateRegion(RegionID)
        case statsMismatch(field: String, expected: Int, found: Int)
    }

    private struct File: Decodable {
        struct Stats: Decodable { let totalRegions: Int; let adjacencyEdges: Int }
        let mapId: String
        let displayName: String
        let stats: Stats
        let regions: [Region]
    }

    public init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        var regions: [RegionID: Region] = [:]
        for region in file.regions {
            guard regions[region.id] == nil else { throw LoadError.duplicateRegion(region.id) }
            regions[region.id] = region
        }
        for region in file.regions {
            for n in region.adjacentTo where regions[n] == nil {
                throw LoadError.unknownNeighbor(region: region.id, neighbor: n)
            }
        }
        mapId = file.mapId
        displayName = file.displayName
        self.regions = regions
        regionIDs = regions.keys.sorted()
        neighborList = regions.mapValues { $0.adjacentTo.sorted() }

        if regions.count != file.stats.totalRegions {
            throw LoadError.statsMismatch(field: "totalRegions",
                                          expected: file.stats.totalRegions, found: regions.count)
        }
        let edges = Set(neighborList.flatMap { a, ns in ns.map { [min(a, $0), max(a, $0)] } }).count
        if edges != file.stats.adjacencyEdges {
            throw LoadError.statsMismatch(field: "adjacencyEdges",
                                          expected: file.stats.adjacencyEdges, found: edges)
        }
    }

    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url))
    }

    // MARK: - Basic queries

    public func terrain(of id: RegionID) -> Terrain { regions[id]!.terrain }

    /// Neighbours in ascending order.
    public func neighbors(of id: RegionID) -> [RegionID] { neighborList[id] ?? [] }

    public func areAdjacent(_ a: RegionID, _ b: RegionID) -> Bool {
        neighborList[a]?.contains(b) ?? false
    }

    // MARK: - Unweighted (steps)

    /// Step counts from `start` to every region reachable through regions
    /// for which `passable` holds. `start` itself is always included.
    public func distances(from start: RegionID,
                          through passable: (RegionID) -> Bool = { _ in true }) -> [RegionID: Int] {
        var dist = [start: 0]
        var frontier = [start]
        while !frontier.isEmpty {
            var next: [RegionID] = []
            for r in frontier {
                for n in neighbors(of: r) where dist[n] == nil && passable(n) {
                    dist[n] = dist[r]! + 1
                    next.append(n)
                }
            }
            frontier = next
        }
        return dist
    }

    public func reachable(from start: RegionID,
                          through passable: (RegionID) -> Bool = { _ in true }) -> Set<RegionID> {
        Set(distances(from: start, through: passable).keys)
    }

    /// A shortest path by step count, inclusive of both ends, or nil.
    /// Ties go to the path whose sequence of regions is lowest, compared
    /// region by region from the start, so results never depend on hashing.
    public func shortestPath(from start: RegionID, to goal: RegionID,
                             through passable: (RegionID) -> Bool = { _ in true }) -> [RegionID]? {
        if start == goal { return [start] }
        // Distances measured back from the goal let us walk forward greedily,
        // taking the lowest-numbered neighbour that stays on a shortest path.
        let toGoal = distances(from: goal, through: { $0 == start || passable($0) })
        guard var remaining = toGoal[start] else { return nil }
        var path = [start]
        var current = start
        while remaining > 0 {
            remaining -= 1
            current = neighbors(of: current).first { toGoal[$0] == remaining }!
            path.append(current)
        }
        return path
    }

    // MARK: - Weighted (pips)

    /// Cheapest cost from `start` to every reachable region. `cost(from, to)`
    /// is the price of the step into `to`, or nil if that step is forbidden.
    public func cheapestCosts(from start: RegionID,
                              cost: (RegionID, RegionID) -> Int?) -> [RegionID: Int] {
        var best = [start: 0]
        var done = Set<RegionID>()
        // The maps have under 100 regions; a linear scan beats a heap here.
        while let (r, d) = best.filter({ !done.contains($0.key) })
                               .min(by: { ($0.value, $0.key) < ($1.value, $1.key) }) {
            done.insert(r)
            for n in neighbors(of: r) where !done.contains(n) {
                guard let c = cost(r, n) else { continue }
                if d + c < best[n, default: .max] { best[n] = d + c }
            }
        }
        return best
    }
}
