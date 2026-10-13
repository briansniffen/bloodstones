import BloodstonesEngine
import SwiftUI

/// One faction's units in one region, as the map draws them. Big stacks are
/// armies: a token on the map, and their units listed on an army board
/// floating over an unused part of the board (as the second edition's
/// A/B/C tokens and boards do).
public struct Stack: Identifiable, Equatable, Sendable {
    public let faction: FactionID
    public let region: RegionID
    public let units: [MapUnit]
    /// The army token ("A", or a mission army's number); nil for a loose
    /// handful of units drawn as tiles.
    public let token: String?

    public var id: String { "\(faction.rawValue)/\(region)/\(token ?? "-")" }

    /// The unit whose figure goes on top of the heap.
    var lead: UnitType {
        let order: [UnitType] = [.dragon, .citadel, .leader, .giant, .necromancer, .cavalry, .siegeEngine,
                                 .swords, .axes, .hordes, .reivers, .lizardmen, .goblins, .undead,
                                 .shield, .skirmishers, .castle, .ship, .blank]
        let types = Set(units.map(\.type))
        return order.first(where: types.contains) ?? units[0].type
    }

    /// The units, lead first, then by type, as they're laid out on a board.
    var ordered: [MapUnit] {
        units.sorted { ($0.type == lead ? 0 : 1, $0.type.rawValue, $0.id) < ($1.type == lead ? 0 : 1, $1.type.rawValue, $1.id) }
    }

    /// (type, count), most important first.
    var groups: [(type: UnitType, count: Int)] {
        Dictionary(grouping: units, by: \.type)
            .map { ($0.key, $0.value.count) }
            .sorted { ($0.0 == lead ? 0 : 1, $0.0.rawValue) < ($1.0 == lead ? 0 : 1, $1.0.rawValue) }
    }
}

/// Stacks of this many units or more are armies.
let armyMinimum = 3

extension GameModel {
    /// Splits the units on the map into stacks. A mission's own armies (the
    /// Dragon Riders' 1, 2, 3) keep their numbers. Any other stack of
    /// `armyMinimum` or more gets a letter, kept from `previous` when it
    /// still holds most of the same units, so an army keeps its letter as
    /// it moves, splits or loses units.
    static func makeStacks(_ s: GameState, previous: [FactionID: [String: Set<Int>]])
        -> (stacks: [Stack], letters: [FactionID: [String: Set<Int>]]) {
        var stacks: [Stack] = []
        var scripted = Set<Int>()
        if case .dragonHunt(let m) = s.mission {
            for (n, ids) in m.armies.sorted(by: { $0.key < $1.key }) {
                let us = ids.compactMap { s.unit($0) }
                guard let r = us.first?.region else { continue }
                stacks.append(Stack(faction: .dragonRiders, region: r, units: us, token: "\(n)"))
                scripted.formUnion(ids)
            }
        }
        var letters: [FactionID: [String: Set<Int>]] = [:]
        for f in FactionID.allCases {
            // Citadels never move, so they're never part of an army.
            let all = s.units(of: f).filter { !scripted.contains($0.id) }
            for c in all where c.type == .citadel {
                stacks.append(Stack(faction: f, region: c.region, units: [c], token: nil))
            }
            let mine = all.filter { $0.type != .citadel }
            let byRegion = Dictionary(grouping: mine, by: \.region).sorted { $0.key < $1.key }
            var big: [(RegionID, [MapUnit])] = []
            for (r, us) in byRegion {
                if us.count >= armyMinimum { big.append((r, us)) } else {
                    stacks.append(Stack(faction: f, region: r, units: us, token: nil))
                }
            }
            // Keep letters where the units mostly carried over; biggest overlaps first.
            let old = previous[f] ?? [:]
            var pairs: [(overlap: Int, letter: String, index: Int)] = []
            for (i, (_, us)) in big.enumerated() {
                let ids = Set(us.map(\.id))
                for (letter, was) in old where !was.isDisjoint(with: ids) {
                    pairs.append((was.intersection(ids).count, letter, i))
                }
            }
            var assigned: [Int: String] = [:]
            for p in pairs.sorted(by: { ($0.overlap, $1.letter) > ($1.overlap, $0.letter) })
            where assigned[p.index] == nil && !assigned.values.contains(p.letter) {
                assigned[p.index] = p.letter
            }
            let alphabet = (65...90).map { String(UnicodeScalar($0)!) }
            for i in big.indices where assigned[i] == nil {
                assigned[i] = alphabet.first { !assigned.values.contains($0) }
            }
            for (i, (r, us)) in big.enumerated() {
                let letter = assigned[i]!
                stacks.append(Stack(faction: f, region: r, units: us, token: letter))
                letters[f, default: [:]][letter] = Set(us.map(\.id))
            }
        }
        return (stacks, letters)
    }

    /// Army stacks, for the boards: the mission's armies, then lettered ones.
    public var armyStacks: [Stack] {
        stacks.filter { $0.token != nil }.sorted {
            ($0.faction == you ? 1 : 0, $0.token!) < ($1.faction == you ? 1 : 0, $1.token!)
        }
    }
}

extension MapShapes {
    /// The largest rectangle of the board, in map coordinates, that no
    /// `blocked` region touches: where the army boards can float.
    func freeRect(blocked: Set<RegionID>, cell: CGFloat = 30) -> CGRect? {
        let cols = Int(size.width / cell), rows = Int(size.height / cell)
        guard cols > 0, rows > 0 else { return nil }
        let blockedPaths = blocked.compactMap { paths[$0] }
        // heights[c]: free cells ending at this row in column c.
        var heights = [Int](repeating: 0, count: cols)
        var best = (area: 0, rect: CGRect.zero)
        for row in 0..<rows {
            for c in 0..<cols {
                let cellRect = CGRect(x: CGFloat(c) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                let probes = [CGPoint(x: cellRect.midX, y: cellRect.midY), cellRect.origin,
                              CGPoint(x: cellRect.maxX, y: cellRect.maxY)]
                let free = !blockedPaths.contains { p in probes.contains { p.contains($0) } }
                heights[c] = free ? heights[c] + 1 : 0
            }
            // Largest rectangle in the histogram.
            var stack: [Int] = []
            for c in 0...cols {
                let h = c < cols ? heights[c] : 0
                while let top = stack.last, heights[top] >= h {
                    stack.removeLast()
                    let left = stack.last.map { $0 + 1 } ?? 0
                    let area = heights[top] * (c - left)
                    if area > best.area {
                        best = (area, CGRect(x: CGFloat(left) * cell, y: CGFloat(row - heights[top] + 1) * cell,
                                             width: CGFloat(c - left) * cell, height: CGFloat(heights[top]) * cell))
                    }
                }
                if c < cols { stack.append(c) }
            }
        }
        return best.area > 0 ? best.rect : nil
    }
}
