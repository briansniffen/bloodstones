import BloodstonesEngine
import SwiftUI

struct BattlePanel: View {
    let model: GameModel

    var body: some View {
        if let b = model.battle {
            let you = model.you
            let foe = b.opponent(of: you)
            VStack(alignment: .leading, spacing: 10) {
                Text("Battle in \(model.describer.region(b.region))\(b.round > 1 ? " — round \(b.round)" : "")")
                    .font(.headline)
                Text(b.attacker == you ? "You are attacking." : "You are defending.")
                    .font(.callout).foregroundStyle(.secondary)
                force(you, b)
                force(foe, b)
                tiles(b)
                decision(b)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.08)))
        }
    }

    private func force(_ f: FactionID, _ b: Battle) -> some View {
        let units = model.engine.force(f, in: b, model.state)
        return VStack(alignment: .leading, spacing: 2) {
            Text(model.describer.name(f)).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.faction(f))
            Text(units.map { model.describer.name($0.type) }.joined(separator: ", ")).font(.caption)
        }
    }

    @ViewBuilder private func tiles(_ b: Battle) -> some View {
        if let mine = b.drawn[model.you] {
            HStack(spacing: 6) {
                ForEach(Array(mine.enumerated()), id: \.offset) { i, v in
                    Text("\(v)")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 6).fill(i < 3 ? Color.primary.opacity(0.12) : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.3)))
                }
                Spacer()
                if let total = model.yourBattleTotal {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(total)").font(.title2.weight(.bold).monospacedDigit())
                        Text("your total").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Top three tiles count, plus unit modifiers.").font(.caption2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func decision(_ b: Battle) -> some View {
        switch b.step {
        case .withdraw:
            Text("You may withdraw: tap an orange region, or stand.").font(.callout)
            Button("Stand and fight") { model.perform(.stand) }.buttonStyle(PanelButtonStyle(prominent: true))
        case .substitute:
            Text("Pick one hand tile below to swap for your lowest Battle tile, or keep these.").font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Keep tiles") { model.perform(.keepTiles) }.buttonStyle(PanelButtonStyle(prominent: true))
                if let sub = model.substitution {
                    Button("Substitute") { model.perform(sub) }
                        .buttonStyle(PanelButtonStyle(prominent: true, tint: .orange))
                }
            }
        case .casualty:
            Text("You lost. Choose the unit to lose:").font(.callout)
            FlowRow(items: model.engine.force(model.you, in: b, model.state)) { u in
                Button(model.describer.name(u.type)) { model.perform(.eliminate(unit: u.id)) }
                    .buttonStyle(PanelButtonStyle(tint: .red))
            }
        case .retreat:
            Text("Retreat: tap an orange region.").font(.callout)
        }
    }
}
