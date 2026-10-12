import SwiftUI

/// The app icon: a faceted bloodstone (dark green, flecked with red) on
/// parchment. Drawn here rather than with SF Symbols, which can't be used
/// in app icons.
struct IconView: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width
            func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * s, y: y * s) }

            // Parchment.
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                Gradient(colors: [Color(red: 0.96, green: 0.90, blue: 0.76), Color(red: 0.78, green: 0.64, blue: 0.44)]),
                center: p(0.5, 0.42), startRadius: 0, endRadius: s * 0.75))

            // A gem cut as a crown over a pavilion.
            let crown = [p(0.30, 0.30), p(0.70, 0.30), p(0.84, 0.44), p(0.16, 0.44)]
            let culet = p(0.50, 0.86)
            let girdleL = p(0.16, 0.44), girdleR = p(0.84, 0.44)
            let table = [p(0.38, 0.30), p(0.62, 0.30), p(0.68, 0.40), p(0.32, 0.40)]

            func poly(_ pts: [CGPoint]) -> Path {
                var path = Path()
                path.addLines(pts)
                path.closeSubpath()
                return path
            }

            // Shadow.
            ctx.fill(Path(ellipseIn: CGRect(x: 0.24 * s, y: 0.86 * s, width: 0.52 * s, height: 0.06 * s)),
                     with: .color(.black.opacity(0.18)))

            let greens = [Color(red: 0.10, green: 0.30, blue: 0.20), Color(red: 0.14, green: 0.40, blue: 0.27),
                          Color(red: 0.07, green: 0.22, blue: 0.15), Color(red: 0.18, green: 0.47, blue: 0.32)]
            // Pavilion facets, fanning from the girdle to the culet.
            let girdle = [girdleL, p(0.33, 0.44), p(0.50, 0.44), p(0.67, 0.44), girdleR]
            for i in 0..<(girdle.count - 1) {
                ctx.fill(poly([girdle[i], girdle[i + 1], culet]), with: .color(greens[i % greens.count]))
            }
            // Crown facets around the table.
            ctx.fill(poly(crown), with: .color(greens[1]))
            ctx.fill(poly([crown[0], table[0], table[3], girdleL]), with: .color(greens[3]))
            ctx.fill(poly([crown[1], table[1], table[2], girdleR]), with: .color(greens[2]))
            ctx.fill(poly(table), with: .color(Color(red: 0.24, green: 0.55, blue: 0.38)))

            // The blood: red flecks across the stone.
            let flecks: [(Double, Double, Double)] = [
                (0.44, 0.35, 0.030), (0.57, 0.37, 0.020), (0.27, 0.41, 0.018), (0.72, 0.42, 0.022),
                (0.40, 0.53, 0.034), (0.58, 0.58, 0.026), (0.49, 0.68, 0.022), (0.33, 0.49, 0.015),
                (0.66, 0.50, 0.016), (0.53, 0.77, 0.014),
            ]
            for (x, y, r) in flecks {
                ctx.fill(Path(ellipseIn: CGRect(x: (x - r) * s, y: (y - r) * s, width: 2 * r * s, height: 2 * r * s)),
                         with: .color(Color(red: 0.75, green: 0.08, blue: 0.08)))
            }

            // Edges and a highlight.
            let outline = poly([crown[0], crown[1], girdleR, culet, girdleL])
            ctx.stroke(outline, with: .color(Color(red: 0.03, green: 0.12, blue: 0.08)), lineWidth: s * 0.012)
            ctx.stroke(poly(table), with: .color(.white.opacity(0.25)), lineWidth: s * 0.006)
            ctx.fill(poly([p(0.40, 0.31), p(0.50, 0.31), p(0.45, 0.36)]), with: .color(.white.opacity(0.35)))
        }
    }
}
