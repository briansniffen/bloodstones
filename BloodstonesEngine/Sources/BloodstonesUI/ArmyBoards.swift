import BloodstonesEngine
import SwiftUI

/// The army boards, floating over the part of the map no piece can reach.
/// Each holds an army's tiles, as big as the space allows; tapping one is
/// tapping the army's region.
struct ArmyBoards: View {
    let model: GameModel
    let fit: MapFit

    var body: some View {
        let armies = model.armyStacks
        if let area = model.boardArea, !armies.isEmpty {
            let tl = fit.toView(area.origin)
            let rect = CGRect(x: tl.x, y: tl.y, width: area.width * fit.scale, height: area.height * fit.scale)
                .insetBy(dx: 8, dy: 8)
            let plan = BoardPlan.fit(armies.map(\.units.count), in: rect.size)
            VStack(alignment: .leading, spacing: BoardPlan.gap) {
                ForEach(Array(stride(from: 0, to: armies.count, by: plan.columns)), id: \.self) { i in
                    HStack(alignment: .top, spacing: BoardPlan.gap) {
                        ForEach(armies[i..<min(i + plan.columns, armies.count)]) {
                            ArmyBoard(model: model, stack: $0, tileHeight: plan.tileHeight, width: plan.boardWidth)
                        }
                    }
                }
            }
            .offset(x: rect.minX, y: rect.minY)
        }
    }
}

/// How big the boards' tiles can be: the largest size at which every board
/// fits the free area, a few boards to a row.
struct BoardPlan: Equatable {
    let columns: Int
    let tileHeight: CGFloat
    let boardWidth: CGFloat

    static let gap: CGFloat = 10
    static let padding: CGFloat = 10
    static let header: CGFloat = 30
    static let tileGap: CGFloat = 6

    static func tilesPerRow(width: CGFloat, tileHeight h: CGFloat) -> Int {
        max(1, Int((width - 2 * padding + tileGap) / (h * TileLook.aspect + tileGap)))
    }

    static func boardHeight(units: Int, width: CGFloat, tileHeight h: CGFloat) -> CGFloat {
        let rows = (units + tilesPerRow(width: width, tileHeight: h) - 1) / tilesPerRow(width: width, tileHeight: h)
        return 2 * padding + header + CGFloat(rows) * (h * (1 + TileLook.thickness) + tileGap)
    }

    static func fit(_ units: [Int], in size: CGSize) -> BoardPlan {
        for h in stride(from: CGFloat(48), through: 16, by: -2) {
            for columns in 1...max(1, min(units.count, 4)) {
                let width = (size.width - CGFloat(columns - 1) * gap) / CGFloat(columns)
                // Tiles lie side by side on a board, as on the physical ones.
                let perRow = tilesPerRow(width: width, tileHeight: h)
                guard width >= 2 * padding + h * TileLook.aspect,
                      perRow >= min(2, units.max() ?? 1) else { continue }
                var total: CGFloat = 0
                for i in stride(from: 0, to: units.count, by: columns) {
                    total += units[i..<min(i + columns, units.count)]
                        .map { boardHeight(units: $0, width: width, tileHeight: h) }.max()! + gap
                }
                if total - gap <= size.height { return BoardPlan(columns: columns, tileHeight: h, boardWidth: width) }
            }
        }
        let columns = max(1, min(units.count, 4))
        return BoardPlan(columns: columns, tileHeight: 16,
                         boardWidth: (size.width - CGFloat(columns - 1) * gap) / CGFloat(columns))
    }
}

struct ArmyBoard: View {
    let model: GameModel
    let stack: Stack
    let tileHeight: CGFloat
    let width: CGFloat

    var body: some View {
        let selected = stack.units.contains { model.selectedUnits.contains($0.id) }
        let perRow = BoardPlan.tilesPerRow(width: width, tileHeight: tileHeight)
        let units = stack.ordered
        VStack(alignment: .leading, spacing: BoardPlan.tileGap) {
            HStack(spacing: 6) {
                ArmyToken(faction: stack.faction, label: stack.token ?? "", size: 24)
                if width >= 260 {
                    Text(model.describer.name(stack.faction)).font(.callout.weight(.semibold)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(whereabouts).font(.callout.monospacedDigit()).foregroundStyle(.black.opacity(0.6))
                    .fixedSize()
            }
            .frame(height: BoardPlan.header - BoardPlan.tileGap)
            ForEach(Array(stride(from: 0, to: units.count, by: perRow)), id: \.self) { i in
                HStack(spacing: BoardPlan.tileGap) {
                    ForEach(units[i..<min(i + perRow, units.count)]) { u in
                        PhysicalTile(art: model.art, faction: u.faction, type: u.type, height: tileHeight,
                                     tilt: TileLook.tilt(u.id, max: 1.5),
                                     lifted: model.selectedUnits.contains(u.id))
                    }
                }
            }
        }
        .padding(BoardPlan.padding)
        .frame(width: width, alignment: .leading)
        .background(BoardBackground(selected: selected))
        .foregroundStyle(.black)
        .contentShape(Rectangle())
        .onTapGesture { model.tap(stack.region) }
        // Hold to peek at the army's region, as on the map.
        .onLongPressGesture(minimumDuration: 0.35) {
            model.peek = stack.region
        } onPressingChanged: { pressing in
            if !pressing { model.peek = nil }
        }
    }

    /// "61", or for a Dragon Rider army "50 → 49" (where it goes next).
    private var whereabouts: String {
        if stack.faction == .dragonRiders, let n = Int(stack.token ?? ""),
           let next = model.armies.first(where: { $0.id == n })?.next {
            return "\(stack.region) → \(next)"
        }
        return "\(stack.region)"
    }
}

/// A parchment board with a raised edge, lying on the map.
struct BoardBackground: View {
    var selected = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        shape.fill(LinearGradient(colors: [Color(red: 0.98, green: 0.94, blue: 0.83), Color(red: 0.91, green: 0.84, blue: 0.68)],
                                  startPoint: .top, endPoint: .bottom))
            .overlay(shape.inset(by: 3).stroke(Palette.border.opacity(0.35), lineWidth: 1))
            .overlay(shape.stroke(selected ? Palette.selected : Palette.border.opacity(0.7), lineWidth: selected ? 3 : 1.5))
            .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
    }
}

/// Everything in a region, shown large while it's held.
struct PeekView: View {
    let model: GameModel
    let region: RegionID

    var body: some View {
        let stacks = model.stacks.filter { $0.region == region }
        let villages = model.state.villages(in: region)
        VStack(alignment: .leading, spacing: 10) {
            Text(model.describer.region(region)).font(.headline)
            ForEach(stacks) { st in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if let t = st.token { ArmyToken(faction: st.faction, label: t) }
                        Text(model.describer.name(st.faction)).font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.faction(st.faction))
                        Text("· \(st.units.count) unit\(st.units.count == 1 ? "" : "s")").font(.caption)
                    }
                    let units = st.ordered
                    ForEach(Array(stride(from: 0, to: units.count, by: 4)), id: \.self) { i in
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(units[i..<min(i + 4, units.count)]) { u in
                                VStack(spacing: 3) {
                                    PhysicalTile(art: model.art, faction: u.faction, type: u.type, height: 40,
                                                 tilt: TileLook.tilt(u.id, max: 1.5))
                                    Text(model.describer.name(u.type)).font(.caption2)
                                }
                            }
                        }
                    }
                }
            }
            if !villages.isEmpty {
                Text("Villages: " + Dictionary(grouping: villages, by: \.faction)
                    .map { "\(model.describer.name($0.key)) \($0.value.count)" }.sorted().joined(separator: ", "))
                    .font(.caption)
            }
        }
        .padding(14)
        .foregroundStyle(.black)
        .background(BoardBackground())
    }
}
