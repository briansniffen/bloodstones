import BloodstonesEngine
import SwiftUI

/// How a tile looks in the hand: the printed tile (or a drawn stand-in)
/// with the thickness of a real piece of card, a soft shadow, and a
/// slight tilt as if set down by hand.
enum TileLook {
    /// Printed tiles are a little over twice as wide as they are tall.
    static let aspect: CGFloat = 2.03
    /// The visible edge under a tile, as a fraction of its height.
    static let thickness: CGFloat = 0.09
    static func cornerRadius(_ height: CGFloat) -> CGFloat { height * 0.17 }

    /// A small fixed tilt for a piece, so tiles look placed rather than
    /// stamped, without wobbling from one redraw to the next.
    static func tilt(_ seed: Int, max: Double = 2) -> Angle {
        var x = UInt64(bitPattern: Int64(seed)) &+ 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x ^= x >> 31
        return .degrees((Double(x % 1001) / 1000 - 0.5) * 2 * max)
    }

    static func colour(_ art: Art?, _ f: FactionID) -> Color { art?.tileColour(f) ?? Palette.faction(f) }
}

/// One tile, `height` points tall, standing a little off the table.
struct PhysicalTile: View {
    let art: Art?
    let faction: FactionID
    let type: UnitType
    let height: CGFloat
    var tilt: Angle = .zero
    /// Picked up: raised, with a longer shadow.
    var lifted = false

    var body: some View {
        let edge = height * TileLook.thickness
        Group {
            if type == .citadel {
                citadel(edge)
            } else {
                tile(edge)
            }
        }
        .rotationEffect(tilt)
        .shadow(color: .black.opacity(lifted ? 0.35 : 0.28), radius: lifted ? height * 0.16 : height * 0.05,
                y: lifted ? height * 0.14 : height * 0.04)
        .offset(y: lifted ? -height * 0.12 : 0)
        .animation(.spring(duration: 0.25), value: lifted)
    }

    private func tile(_ edge: CGFloat) -> some View {
        let w = height * TileLook.aspect
        let shape = RoundedRectangle(cornerRadius: TileLook.cornerRadius(height))
        return ZStack(alignment: .top) {
            shape.fill(TileLook.colour(art, faction))
                .overlay(shape.fill(.black.opacity(0.4)))
                .frame(width: w, height: height)
                .offset(y: edge)
            face.frame(width: w, height: height)
                .clipShape(shape)
                .overlay(shape.stroke(.black.opacity(0.22), lineWidth: 0.5))
        }
        .frame(width: w, height: height + edge, alignment: .top)
    }

    @ViewBuilder private var face: some View {
        if let printed = art?.tile(faction, type) {
            printed.image.resizable()
        } else if let figure = art?.unit(faction, type) {
            TileLook.colour(art, faction)
                .overlay(figure.image.resizable().scaledToFit()
                    .padding(.vertical, height * 0.06).padding(.horizontal, height * 0.3))
        } else {
            Palette.faction(faction)
                .overlay(Text(Palette.short(type)).font(.system(size: height * 0.5, weight: .bold)).foregroundStyle(.white))
        }
    }

    /// The citadel is a round token rather than a tile.
    private func citadel(_ edge: CGFloat) -> some View {
        let d = height * 1.3
        return ZStack(alignment: .top) {
            Circle().fill(TileLook.colour(art, faction)).overlay(Circle().fill(.black.opacity(0.4)))
                .frame(width: d, height: d).offset(y: edge)
            Group {
                if let token = art?.unit(faction, .citadel) {
                    token.image.resizable()
                } else {
                    Circle().fill(Palette.faction(faction))
                        .overlay(Text("Cit").font(.system(size: d * 0.3, weight: .bold)).foregroundStyle(.white))
                }
            }
            .frame(width: d, height: d)
            .clipShape(Circle())
        }
        .frame(width: d, height: d + edge, alignment: .top)
    }
}

/// A round army token (A, B, … or a mission army's number), with the same
/// thickness as the tiles.
struct ArmyToken: View {
    let faction: FactionID
    let label: String
    var size: CGFloat = 22

    var body: some View {
        let edge = size * TileLook.thickness
        ZStack(alignment: .top) {
            Circle().fill(Palette.faction(faction)).overlay(Circle().fill(.black.opacity(0.4)))
                .frame(width: size, height: size).offset(y: edge)
            Text(label)
                .font(.system(size: size * 0.6, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(Palette.faction(faction)))
                .overlay(Circle().stroke(.white, lineWidth: max(1, size * 0.06)))
        }
        .frame(width: size, height: size + edge, alignment: .top)
        .shadow(color: .black.opacity(0.28), radius: size * 0.06, y: size * 0.05)
    }
}
