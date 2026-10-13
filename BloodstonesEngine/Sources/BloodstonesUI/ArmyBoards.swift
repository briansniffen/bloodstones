import BloodstonesEngine
import SwiftUI

/// The army boards, floating over the part of the map no piece can reach.
/// Each lists an army's units; tapping one is tapping the army's region.
struct ArmyBoards: View {
    let model: GameModel
    let fit: MapFit

    var body: some View {
        let armies = model.armyStacks
        if let area = model.boardArea, !armies.isEmpty {
            let tl = fit.toView(area.origin)
            let rect = CGRect(x: tl.x, y: tl.y, width: area.width * fit.scale, height: area.height * fit.scale)
                .insetBy(dx: 8, dy: 8)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 8, alignment: .top)],
                      alignment: .leading, spacing: 8) {
                ForEach(armies) { ArmyBoard(model: model, stack: $0) }
            }
            .frame(width: rect.width, height: rect.height, alignment: .topLeading)
            .offset(x: rect.minX, y: rect.minY)
        }
    }
}

struct ArmyBoard: View {
    let model: GameModel
    let stack: Stack

    var body: some View {
        let selected = stack.units.contains { model.selectedUnits.contains($0.id) }
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                ArmyToken(faction: stack.faction, label: stack.token ?? "")
                Text(model.describer.name(stack.faction)).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                Text(whereabouts).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            UnitGroups(model: model, stack: stack, tileHeight: 20)
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.97, green: 0.93, blue: 0.82).opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Palette.selected : Palette.border.opacity(0.6),
                                                          lineWidth: selected ? 3 : 1))
        .foregroundStyle(.black)
        .contentShape(Rectangle())
        .onTapGesture { model.tap(stack.region) }
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

struct ArmyToken: View {
    let faction: FactionID
    let label: String
    var size: CGFloat = 22

    var body: some View {
        Text(label)
            .font(.system(size: size * 0.6, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Palette.faction(faction)))
            .overlay(Circle().stroke(.white, lineWidth: 1.5))
    }
}

/// A stack's units, one tile per type with a count.
struct UnitGroups: View {
    let model: GameModel
    let stack: Stack
    let tileHeight: CGFloat

    var body: some View {
        let groups = stack.groups.map { Group(type: $0.type, count: $0.count) }
        FlowRow(items: groups) { g in
            HStack(spacing: 2) {
                UnitTile(art: model.art, faction: stack.faction, type: g.type, height: tileHeight)
                if g.count > 1 { Text("×\(g.count)").font(.system(size: tileHeight * 0.6, weight: .semibold)) }
            }
        }
    }

    struct Group: Identifiable {
        let type: UnitType
        let count: Int
        var id: UnitType { type }
    }
}

/// One unit as a small tile: the art, or a coloured chip with its short name.
struct UnitTile: View {
    let art: Art?
    let faction: FactionID
    let type: UnitType
    let height: CGFloat

    var body: some View {
        if let art, let figure = art.unit(faction, type) {
            if type == .citadel {
                figure.image.resizable().scaledToFit().frame(width: height * 1.3, height: height * 1.3)
            } else {
                RoundedRectangle(cornerRadius: height * 0.18)
                    .fill(art.tileColour(faction) ?? Palette.faction(faction))
                    .overlay(figure.image.resizable().scaledToFit().padding(.vertical, height * 0.06)
                        .padding(.horizontal, height * 0.24))
                    .overlay(RoundedRectangle(cornerRadius: height * 0.18).stroke(.black.opacity(0.3), lineWidth: 0.5))
                    .frame(width: height * 2, height: height)
            }
        } else {
            Text(Palette.short(type))
                .font(.system(size: height * 0.55, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: height * 2, height: height)
                .background(RoundedRectangle(cornerRadius: 3).fill(Palette.faction(faction)))
        }
    }
}

/// Everything in a region, shown large while it's held.
struct PeekView: View {
    let model: GameModel
    let region: RegionID

    var body: some View {
        let stacks = model.stacks.filter { $0.region == region }
        let villages = model.state.villages(in: region)
        VStack(alignment: .leading, spacing: 8) {
            Text(model.describer.region(region)).font(.headline)
            ForEach(stacks) { st in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if let t = st.token { ArmyToken(faction: st.faction, label: t) }
                        Text(model.describer.name(st.faction)).font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.faction(st.faction))
                        Text("· \(st.units.count) unit\(st.units.count == 1 ? "" : "s")").font(.caption)
                    }
                    FlowRow(items: st.groups.map { UnitGroups.Group(type: $0.type, count: $0.count) }) { g in
                        VStack(spacing: 2) {
                            UnitTile(art: model.art, faction: st.faction, type: g.type, height: 34)
                            Text(model.describer.name(g.type) + (g.count > 1 ? " ×\(g.count)" : ""))
                                .font(.caption2)
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
        .padding(12)
        .foregroundStyle(.black)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.98, green: 0.95, blue: 0.86)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 1.5))
        .shadow(radius: 8)
    }
}
