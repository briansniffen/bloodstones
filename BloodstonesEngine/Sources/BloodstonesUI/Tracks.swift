import BloodstonesEngine
import SwiftUI

/// The victory point and regroup tracks printed around the board, floating
/// over the map, with a marker for each faction.
struct TracksView: View {
    let model: GameModel

    static let cell: CGFloat = 22
    static let vpMax = 50

    var body: some View {
        let s = model.state
        let present = FactionID.allCases.filter { s.factions[$0] != nil }
        let scorers = present.filter { $0 == model.you || s.factions[$0]!.victoryPoints > 0 }
        let regroupers = present.filter { model.engine.script.regroups($0) && ($0 == model.you || s.factions[$0]!.regroups > 0) }
        HStack(alignment: .bottom, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                label("Victory points")
                VStack(alignment: .leading, spacing: 0) {
                    row(0...25, markers: scorers.map { ($0, s.factions[$0]!.victoryPoints) })
                    row(26...Self.vpMax, markers: scorers.map { ($0, s.factions[$0]!.victoryPoints) })
                }
            }
            if !regroupers.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    label("Regroups")
                    row(0...3, markers: regroupers.map { ($0, s.factions[$0]!.regroups) })
                }
            }
        }
        .padding(8)
        .background(BoardBackground())
        .allowsHitTesting(false)
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 9, weight: .bold, design: .serif)).foregroundStyle(.black.opacity(0.55))
    }

    /// One row of numbered spaces, with markers sitting on theirs. Scores
    /// past the end go round again, as on the board.
    private func row(_ spaces: ClosedRange<Int>, markers: [(FactionID, Int)]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(spaces), id: \.self) { n in
                let here = markers.filter { $0.1 % (Self.vpMax + 1) == n }
                ZStack {
                    Rectangle().fill(LinearGradient(colors: [Color(red: 0.93, green: 0.76, blue: 0.6), Color(red: 0.85, green: 0.65, blue: 0.48)],
                                                    startPoint: .top, endPoint: .bottom))
                    Rectangle().stroke(Color(red: 0.35, green: 0.2, blue: 0.12).opacity(0.8), lineWidth: 0.75)
                    Text("\(n)").font(.system(size: 11, weight: .medium, design: .serif)).foregroundStyle(.black.opacity(0.8))
                    ForEach(Array(here.enumerated()), id: \.offset) { i, m in
                        marker(m.0)
                            .offset(x: CGFloat(i) * 4 - CGFloat(here.count - 1) * 2, y: -CGFloat(i) * 4 + CGFloat(here.count - 1) * 2)
                    }
                }
                .frame(width: Self.cell, height: Self.cell)
            }
        }
    }

    /// A wooden-looking disc in the faction's colour.
    private func marker(_ f: FactionID) -> some View {
        let d = Self.cell * 0.82
        return ZStack(alignment: .top) {
            Circle().fill(Palette.faction(f)).overlay(Circle().fill(.black.opacity(0.4)))
                .frame(width: d, height: d).offset(y: d * 0.12)
            Circle().fill(Palette.faction(f))
                .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
                .frame(width: d, height: d)
        }
        .frame(width: d, height: d * 1.12, alignment: .top)
        .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
    }
}
