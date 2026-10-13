import BloodstonesEngine
import SwiftUI

/// Snapshots render without scroll views (they are platform views on macOS).
struct SnapshotModeKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    public var snapshotMode: Bool {
        get { self[SnapshotModeKey.self] }
        set { self[SnapshotModeKey.self] = newValue }
    }
}

struct Scrolling<Content: View>: View {
    @Environment(\.snapshotMode) private var snapshot
    @ViewBuilder let content: Content
    var body: some View {
        if snapshot { content.frame(maxHeight: .infinity, alignment: .top) } else { ScrollView { content } }
    }
}

struct SidePanel: View {
    let model: GameModel

    var body: some View {
        Scrolling {
            VStack(alignment: .leading, spacing: 14) {
                header
                if let message = model.message {
                    Text(message).font(.callout).foregroundStyle(.red)
                }
                if model.pending != nil { ConfirmStrip(model: model) } else { controls }
                HandView(model: model)
                DragonRidersView(model: model)
                LogView(model: model)
            }
            .padding(16)
        }
        .background(.background)
    }

    private var header: some View {
        let s = model.state
        let hl = s.factions[model.you]!
        let dr = s.factions[.dragonRiders]!
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Dragon Hunt").font(.title3.weight(.bold))
                Spacer()
                Button("Undo") { model.undo() }
                    .buttonStyle(PanelButtonStyle()).disabled(!model.canUndo)
            }
            Text("Turn \(s.turnNumber) · \(phaseName)").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                stat("VP", "\(hl.victoryPoints)")
                stat("Regroups", "\(hl.regroups)/2", warn: hl.regroups >= 1)
                stat("Bag", "\(hl.bag.count)")
                stat("Discard", "\(hl.discard.count)")
                stat("DR clock", "\(dr.bag.count)", warn: dr.bag.count <= 5)
            }
            if let o = s.outcome {
                switch o {
                case .victory(let why): banner("Victory — \(why)", .green)
                case .defeat(let why): banner("Defeat — \(why)", .red)
                }
            }
        }
    }

    private var phaseName: String {
        if model.state.battle != nil { return "Battle" }
        switch model.state.phase {
        case .capture: return "Capture villages"
        case .main: return "Main actions"
        case .construct: return "Construct villages"
        case .nonPlayer: return "Dragon Riders"
        case .gameOver: return "Game over"
        }
    }

    private func stat(_ label: String, _ value: String, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(warn ? .red : .primary)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func banner(_ text: String, _ color: Color) -> some View {
        Text(text).font(.headline).foregroundStyle(.white)
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(color))
    }

    @ViewBuilder private var controls: some View {
        if model.isOver {
            EmptyView()
        } else if model.state.battle != nil {
            BattlePanel(model: model)
        } else {
            switch model.state.phase {
            case .capture:
                hint("Tap a blue region to capture a village there. One tile pays for the whole phase"
                     + (model.state.pipBudget.map { " — \($0) pips left." } ?? "."))
                endButton("Done capturing")
            case .main:
                MainControls(model: model)
            case .construct:
                hint("Tap a blue region to build a village. One tile pays for the whole phase"
                     + (model.state.pipBudget.map { " — \($0) pips left." } ?? "."))
                endButton("End turn")
            default:
                EmptyView()
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func endButton(_ title: String) -> some View {
        Button(title) { model.perform(.endPhase) }
            .buttonStyle(PanelButtonStyle(prominent: true))
            .disabled(!model.endPhaseAvailable)
    }
}

struct MainControls: View {
    let model: GameModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let t = model.buildTile, let tile = model.hand.first(where: { $0.id == t }) {
                Text("Building \(model.describer.name(tile.unit)): tap a blue region. "
                     + (tile.buildCost == 0 ? "It's free." : "It costs \(tile.buildCost!) other tile\(tile.buildCost == 1 ? "" : "s"): pick them below, or the cheapest are used."))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Cancel build") { model.buildTile = nil }.buttonStyle(PanelButtonStyle())
            } else if let r = model.selectedRegion {
                Text("Moving from \(model.describer.region(r)) — tap units to include them, then tap a green region. Pick tiles below to pay, or the cheapest are used.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                FlowRow(items: model.pickable(in: r)) { u in
                    Button(model.describer.name(u.type)) { model.toggleUnit(u.id) }
                        .buttonStyle(PanelButtonStyle(prominent: model.selectedUnits.contains(u.id),
                                                      tint: Palette.faction(u.faction)))
                }
            } else {
                Text("Tap your units on the map to move them, a red region to fight, or Build on a tile.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            let contested = model.state.contestedRegions(for: model.you)
            Button(contested.isEmpty ? "Done with actions" : "Fight in \(contested.map(String.init).joined(separator: ", ")) first") {
                model.perform(.endPhase)
            }
            .buttonStyle(PanelButtonStyle(prominent: true))
            .disabled(!model.endPhaseAvailable)
        }
    }
}

/// A simple wrapping row.
struct FlowRow<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    @ViewBuilder let cell: (Item) -> Cell
    var body: some View {
        let rows = stride(from: 0, to: items.count, by: 4).map { Array(items[$0..<min($0 + 4, items.count)]) }
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 6) { ForEach(rows[i]) { cell($0) } }
            }
        }
    }
}

struct HandView: View {
    let model: GameModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Hand").font(.headline)
                Spacer()
                if !model.payment.isEmpty {
                    Text("Picked: \(model.paymentPips) pips").font(.caption).foregroundStyle(.secondary)
                }
            }
            let columns = [GridItem(.adaptive(minimum: model.art == nil ? 76 : 150), spacing: 8)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(model.hand, id: \.id) { tile in
                    TileCard(model: model, tile: tile)
                }
            }
        }
    }
}

struct TileCard: View {
    let model: GameModel
    let tile: Tile

    var body: some View {
        let picked = model.payment.contains(tile.id)
        let building = model.buildTile == tile.id
        VStack(spacing: 3) {
            if let art = model.art {
                TileFace(tile: tile, art: art)
            } else {
                Text("\(tile.pips)").font(.title2.weight(.bold).monospacedDigit())
            }
            Text(model.describer.name(tile.unit)).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
            if model.art?.tile(tile.faction, tile.unit) == nil {
                Text(tile.buildCost.map { String(repeating: "▪︎", count: $0).isEmpty ? "free" : String(repeating: "▪︎", count: $0) } ?? " ")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if model.canBuild(tile) {
                Button(building ? "Building" : "Build") { model.toggleBuild(tile.id) }
                    .buttonStyle(PanelButtonStyle(prominent: building, tint: Palette.faction(.horseLords)))
                    .font(.caption)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(picked ? Palette.selected.opacity(0.35) : Color.secondary.opacity(0.10))
        )
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(picked ? Palette.selected : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { model.toggleTile(tile.id) }
    }
}

/// A tile drawn like the physical one: its faction's colour, the unit's
/// figure, and the pip value.
struct TileFace: View {
    let tile: Tile
    let art: Art

    var body: some View {
        if let printed = art.tile(tile.faction, tile.unit) {
            // The tile as printed: its knots show the build cost, its marks the pips.
            printed.image.resizable()
                .aspectRatio(printed.size.width / printed.size.height, contentMode: .fit)
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                .accessibilityLabel("\(tile.pips) pips")
        } else {
            drawn
        }
    }

    private var drawn: some View {
        let colour = art.tileColour(tile.faction) ?? Palette.faction(tile.faction)
        return RoundedRectangle(cornerRadius: 7)
            .fill(colour)
            .overlay {
                if let figure = art.unit(tile.faction, tile.unit) {
                    figure.image.resizable().scaledToFit().padding(.vertical, 3).padding(.horizontal, 14)
                }
            }
            .overlay(alignment: .topLeading) {
                Text("\(tile.pips)")
                    .font(.headline.weight(.heavy).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(.black.opacity(0.75)))
                    .offset(x: -5, y: -5)
            }
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.black.opacity(0.3), lineWidth: 0.5))
            .aspectRatio(2, contentMode: .fit)
            .padding(.top, 5).padding(.leading, 5)
    }
}

struct DragonRidersView: View {
    let model: GameModel

    var body: some View {
        let dr = model.state.factions[.dragonRiders]!
        VStack(alignment: .leading, spacing: 4) {
            Text("Dragon Riders").font(.headline).foregroundStyle(Palette.faction(.dragonRiders))
            Text("\(dr.bag.count) tiles left in their bag; you lose when it's empty. Hand: \(dr.hand.count).")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(model.armies) { a in
                Text(a.region.map { "Army \(a.id) on \($0)" + (a.next.map { " → \($0)" } ?? "") + " · " + a.units.map(Palette.short).joined(separator: " ") }
                     ?? "Army \(a.id) destroyed")
                    .font(.caption.monospaced())
            }
            Text("Dragons: " + (model.dragons.isEmpty ? "none" : model.dragons.map { "\($0.region)" }.joined(separator: ", ")))
                .font(.caption.monospaced())
        }
    }
}

struct LogView: View {
    let model: GameModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Log").font(.headline)
            ForEach(model.log.suffix(30).reversed()) { line in
                Text(line.text).font(.caption).foregroundStyle(line.text.hasPrefix("—") ? .primary : .secondary)
            }
        }
    }
}

/// Shows what a tile-spending action will cost and what will pay for it.
struct ConfirmStrip: View {
    let model: GameModel

    var body: some View {
        if let p = model.pending {
            VStack(alignment: .leading, spacing: 8) {
                Text(title(p)).font(.headline)
                HStack(spacing: 4) {
                    Text(costText(p))
                    Text("·").foregroundStyle(.secondary)
                    Text(paying(p)).foregroundStyle(model.pendingAction == nil ? .red : .primary)
                }
                .font(.callout)
                if let problem = model.pendingProblem {
                    Text(problem).font(.caption).foregroundStyle(.red)
                } else {
                    Text("Tap hand tiles below to change what you spend.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Confirm") { model.confirmPending() }
                        .buttonStyle(PanelButtonStyle(prominent: true))
                        .disabled(model.pendingAction == nil)
                    Button("Cancel") { model.cancelPending() }
                        .buttonStyle(PanelButtonStyle())
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.selected.opacity(0.15)))
        }
    }

    private func title(_ p: Pending) -> String {
        let d = model.describer
        switch p.kind {
        case .move(let leg):
            let from = model.state.unit(leg.units[0])?.region ?? 0
            let units = leg.units.compactMap { model.state.unit($0) }.map { d.name($0.type) }.joined(separator: ", ")
            return "Move \(units): \(from) → \(d.region(leg.to))"
        case .build(let t, let r):
            let name = model.hand.first { $0.id == t }.map { d.name($0.unit) } ?? "unit"
            return "Build \(name) in \(d.region(r))"
        case .capture(let r): return "Capture the village in \(d.region(r))"
        case .construct(let r): return "Build a village in \(d.region(r))"
        }
    }

    private func costText(_ p: Pending) -> String {
        if case .build = p.kind { return "Costs \(p.cost) tile\(p.cost == 1 ? "" : "s")" }
        return "Costs \(p.cost) pip\(p.cost == 1 ? "" : "s")"
    }

    private func paying(_ p: Pending) -> String {
        let tiles = model.payment.compactMap { id in model.hand.first { $0.id == id } }
        if tiles.isEmpty { return "nothing picked" }
        let names = tiles.map { "\(model.describer.name($0.unit)) \($0.pips)" }.joined(separator: " + ")
        if case .build = p.kind { return "discarding " + names }
        return "paying " + names + (tiles.count > 1 ? " = \(model.paymentPips)" : "")
    }
}
