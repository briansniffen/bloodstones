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
                controls
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
            let columns = [GridItem(.adaptive(minimum: 76), spacing: 6)]
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
            Text("\(tile.pips)").font(.title2.weight(.bold).monospacedDigit())
            Text(model.describer.name(tile.unit)).font(.caption2).lineLimit(1).minimumScaleFactor(0.7)
            Text(tile.buildCost.map { String(repeating: "▪︎", count: $0).isEmpty ? "free" : String(repeating: "▪︎", count: $0) } ?? " ")
                .font(.caption2).foregroundStyle(.secondary)
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
