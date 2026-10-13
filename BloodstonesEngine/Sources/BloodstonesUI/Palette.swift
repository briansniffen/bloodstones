import BloodstonesEngine
import SwiftUI

/// Board colours are fixed (the map is a physical object, not chrome);
/// panel colours follow the system's light and dark appearance.
enum Palette {
    static func terrain(_ t: Terrain) -> Color {
        switch t {
        case .plains: Color(red: 0.80, green: 0.85, blue: 0.55)
        case .forest: Color(red: 0.42, green: 0.62, blue: 0.38)
        case .hills: Color(red: 0.86, green: 0.66, blue: 0.70)
        case .mountains: Color(red: 0.62, green: 0.60, blue: 0.58)
        case .desert: Color(red: 0.93, green: 0.82, blue: 0.56)
        case .sea: Color(red: 0.55, green: 0.74, blue: 0.86)
        }
    }

    static func faction(_ f: FactionID) -> Color {
        switch f {
        case .horseLords: Color(red: 0.13, green: 0.33, blue: 0.75)
        case .dragonRiders: Color(red: 0.78, green: 0.13, blue: 0.13)
        case .hillFolk: Color(red: 0.20, green: 0.50, blue: 0.25)
        case .necromancers: Color(red: 0.35, green: 0.25, blue: 0.45)
        case .chaosHorde: Color(red: 0.55, green: 0.40, blue: 0.20)
        case .corsairs: Color(red: 0.15, green: 0.15, blue: 0.15)
        }
    }

    static let border = Color(red: 0.25, green: 0.20, blue: 0.15)
    static let offLimits = Color.black.opacity(0.42)
    static let selected = Color(red: 1.0, green: 0.85, blue: 0.1)

    static func highlight(_ h: Highlight) -> Color {
        switch h {
        case .selected: selected.opacity(0.35)
        case .move: Color(red: 0.1, green: 0.75, blue: 0.25).opacity(0.22)
        case .buildSite, .village, .capture: Color(red: 0.1, green: 0.5, blue: 1.0).opacity(0.38)
        case .battle: Color(red: 1.0, green: 0.15, blue: 0.1).opacity(0.45)
        case .withdraw, .retreat: Color(red: 1.0, green: 0.6, blue: 0.0).opacity(0.45)
        case .target: Color.white.opacity(0.45)
        }
    }

    /// The colour a highlighted region glows.
    static func glow(_ h: Highlight) -> Color {
        switch h {
        case .selected: selected
        case .move: Color(red: 0.25, green: 0.95, blue: 0.35)
        case .buildSite, .village, .capture: Color(red: 0.25, green: 0.65, blue: 1.0)
        case .battle: Color(red: 1.0, green: 0.2, blue: 0.12)
        case .withdraw, .retreat: Color(red: 1.0, green: 0.62, blue: 0.1)
        case .target: .white
        }
    }

    /// Highlights that glow together as one area.
    static func glowKind(_ h: Highlight) -> String {
        switch h {
        case .selected: "selected"
        case .move: "move"
        case .buildSite, .village, .capture: "site"
        case .battle: "battle"
        case .withdraw, .retreat: "away"
        case .target: "target"
        }
    }

    /// Moves light up many regions at once, so their glow is gentler; the
    /// region you're acting on is strongest.
    static func glowStrength(_ h: Highlight) -> Double {
        switch h {
        case .move: 0.7
        case .selected, .target: 1.2
        default: 1
        }
    }

    /// Short labels for unit chips on the map.
    static func short(_ t: UnitType) -> String {
        switch t {
        case .skirmishers: "Sk"
        case .swords: "Sw"
        case .shield: "Sh"
        case .cavalry: "Cv"
        case .siegeEngine: "Sg"
        case .leader: "Ld"
        case .ship: "Shp"
        case .castle: "Cs"
        case .citadel: "Cit"
        case .dragon: "DRG"
        case .lizardmen: "Lz"
        case .blank: "–"
        case .goblins: "Gb"
        case .necromancer: "Nc"
        case .undead: "Ud"
        case .reivers: "Rv"
        case .giant: "Gi"
        case .hordes: "Hd"
        case .axes: "Ax"
        }
    }
}

/// Buttons drawn by SwiftUI itself, so they look the same everywhere and
/// render in snapshots.
struct PanelButtonStyle: ButtonStyle {
    var prominent = false
    var tint: Color = .accentColor
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(prominent ? .semibold : .regular))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: prominent ? .infinity : nil)
            .foregroundStyle(prominent ? Color.white : tint)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(prominent ? tint : tint.opacity(0.12))
            )
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}
