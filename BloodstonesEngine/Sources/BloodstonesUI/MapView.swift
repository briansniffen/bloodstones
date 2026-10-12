import BloodstonesEngine
import SwiftUI

/// Region shapes in map pixels, built once per map.
struct MapShapes {
    let size: CGSize
    let paths: [RegionID: Path]
    let centres: [RegionID: CGPoint]

    init(_ map: MapGraph) {
        var maxX = 0.0, maxY = 0.0
        for r in map.regions.values {
            for pt in r.polygon { maxX = max(maxX, pt[0]); maxY = max(maxY, pt[1]) }
        }
        size = CGSize(width: maxX, height: maxY)
        var paths: [RegionID: Path] = [:]
        var centres: [RegionID: CGPoint] = [:]
        for (id, r) in map.regions {
            var p = Path()
            if let first = r.polygon.first {
                p.move(to: CGPoint(x: first[0], y: first[1]))
                for pt in r.polygon.dropFirst() { p.addLine(to: CGPoint(x: pt[0], y: pt[1])) }
                p.closeSubpath()
            }
            paths[id] = p
            centres[id] = CGPoint(x: r.displayPosition[0], y: r.displayPosition[1])
        }
        self.paths = paths
        self.centres = centres
    }

    func region(at p: CGPoint) -> RegionID? {
        paths.first { $0.value.contains(p) }?.key
    }
}

/// Fits the map into the view, keeping its shape. `map` is the part of map
/// space to show: the regions, or the whole board image.
struct MapFit {
    let scale: CGFloat
    let origin: CGPoint

    init(map: CGRect, in view: CGSize) {
        scale = min(view.width / map.width, view.height / map.height)
        origin = CGPoint(x: (view.width - map.width * scale) / 2 - map.minX * scale,
                         y: (view.height - map.height * scale) / 2 - map.minY * scale)
    }

    func toView(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale) }
    func toMap(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - origin.x) / scale, y: (p.y - origin.y) / scale) }
    var transform: CGAffineTransform {
        CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: scale, y: scale)
    }
}

public struct MapView: View {
    let model: GameModel
    var shapes: MapShapes { model.shapes }

    public init(model: GameModel) { self.model = model }

    public var body: some View {
        GeometryReader { geo in
            let fit = MapFit(map: model.art?.map?.bounds ?? CGRect(origin: .zero, size: shapes.size), in: geo.size)
            let highlights = model.highlights()
            Canvas { ctx, _ in
                draw(in: &ctx, fit: fit, highlights: highlights)
            }
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { loc in
                if let r = shapes.region(at: fit.toMap(loc)) { model.tap(r) }
            }
        }
        .background(Palette.border.opacity(0.85))
    }

    private func draw(in ctx: inout GraphicsContext, fit: MapFit, highlights: [RegionID: Highlight]) {
        let s = model.state
        let board = model.art?.map
        // The board (or plain terrain), then highlights, then borders.
        if let board {
            let r = board.bounds
            let tl = fit.toView(r.origin)
            ctx.draw(board.sprite.image, in: CGRect(x: tl.x, y: tl.y, width: r.width * fit.scale, height: r.height * fit.scale))
        }
        for id in model.map.regionIDs {
            let path = shapes.paths[id]!.applying(fit.transform)
            if board == nil { ctx.fill(path, with: .color(Palette.terrain(model.map.terrain(of: id)))) }
            if !model.engine.script.isEnterable(id, in: s) { ctx.fill(path, with: .color(Palette.offLimits)) }
            if let h = highlights[id] { ctx.fill(path, with: .color(Palette.highlight(h))) }
        }
        for id in model.map.regionIDs {
            let path = shapes.paths[id]!.applying(fit.transform)
            if board == nil { ctx.stroke(path, with: .color(Palette.border.opacity(0.7)), lineWidth: 0.8) }
            if highlights[id] == .selected { ctx.stroke(path, with: .color(Palette.selected), lineWidth: 3) }
            if highlights[id] == .target { ctx.stroke(path, with: .color(.white), lineWidth: 4) }
        }
        // Numbers (printed on the board art), costs and pieces.
        let chip = max(13, (board == nil ? 30 : 40) * fit.scale)
        for id in model.map.regionIDs {
            var c = fit.toView(shapes.centres[id]!)
            if board == nil {
                ctx.draw(Text("\(id)").font(.system(size: chip * 0.55, weight: .semibold)).foregroundStyle(.black.opacity(0.55)),
                         at: CGPoint(x: c.x, y: c.y - chip * 0.55))
            }
            switch highlights[id] {
            case .target:
                // Pip cost on the target; builds cost tiles, shown in the panel.
                if let p = model.pending, !p.costsTiles {
                    badge(&ctx, "\(p.cost)", at: CGPoint(x: c.x + chip * 1.1, y: c.y - chip * 0.6), size: chip * 0.8)
                }
            case .move(let cost), .village(let cost), .capture(let cost):
                badge(&ctx, "\(cost)", at: CGPoint(x: c.x + chip * 1.1, y: c.y - chip * 0.6), size: chip * 0.8)
            default: break
            }
            // Pieces go under the printed number circle.
            if board != nil { c.y += 30 * fit.scale + chip * 0.45 }
            drawPieces(&ctx, region: id, at: c, chip: chip)
        }
    }

    private func badge(_ ctx: inout GraphicsContext, _ text: String, at p: CGPoint, size: CGFloat) {
        let rect = CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
        ctx.fill(Path(ellipseIn: rect), with: .color(.white))
        ctx.stroke(Path(ellipseIn: rect), with: .color(.black.opacity(0.6)), lineWidth: 1)
        ctx.draw(Text(text).font(.system(size: size * 0.62, weight: .bold)).foregroundStyle(.black), at: p)
    }

    /// Unit chips (grouped by type, with counts) and village houses, in rows
    /// under the region number.
    private func drawPieces(_ ctx: inout GraphicsContext, region: RegionID, at c: CGPoint, chip: CGFloat) {
        let s = model.state
        struct Chip { let faction: FactionID; let type: UnitType; let count: Int; let label: String; let selected: Bool }
        var chips: [Chip] = []
        for f in FactionID.allCases {
            let units = s.units(in: region).filter { $0.faction == f }
            let groups = Dictionary(grouping: units, by: \.type).sorted { $0.key.rawValue < $1.key.rawValue }
            for (type, us) in groups {
                let label = Palette.short(type) + (us.count > 1 ? "\(us.count)" : "")
                chips.append(Chip(faction: f, type: type, count: us.count, label: label,
                                  selected: us.contains { model.selectedUnits.contains($0.id) }))
            }
        }
        let villages = s.villages(in: region)
        let perRow = 3
        let w = chip * 1.45, h = chip * 0.82
        let rows = (chips.count + perRow - 1) / perRow
        for (i, ch) in chips.enumerated() {
            let row = i / perRow, col = i % perRow
            let inRow = min(perRow, chips.count - row * perRow)
            let x = c.x + (CGFloat(col) - CGFloat(inRow - 1) / 2) * (w + 2)
            let y = c.y + CGFloat(row) * (h + 2) + h * 0.2
            let rect = CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)
            let shape = Path(roundedRect: rect, cornerRadius: 3)
            if let art = model.art, let figure = art.unit(ch.faction, ch.type) {
                artChip(&ctx, ch.faction, ch.type, figure: figure, count: ch.count, in: rect, art: art)
            } else {
                ctx.fill(shape, with: .color(Palette.faction(ch.faction)))
                ctx.draw(Text(ch.label).font(.system(size: h * 0.62, weight: .bold)).foregroundStyle(.white),
                         at: CGPoint(x: x, y: y))
            }
            if ch.selected { ctx.stroke(shape, with: .color(Palette.selected), lineWidth: 2.5) }
        }
        // Houses below the chips.
        let vy = c.y + CGFloat(rows) * (h + 2) + h * 0.45
        for (i, v) in villages.enumerated() {
            let x = c.x + (CGFloat(i) - CGFloat(villages.count - 1) / 2) * (chip * 0.75)
            if let icon = model.art?.village(v.faction) {
                let size = chip * 0.7
                ctx.draw(icon.image, in: icon.fit(in: CGRect(x: x - size / 2, y: vy - size / 2, width: size, height: size)))
            } else {
                house(&ctx, at: CGPoint(x: x, y: vy), size: chip * 0.6, color: Palette.faction(v.faction))
            }
        }
    }

    /// A tile in its faction's colour with the unit's figure, and a count
    /// badge for stacks. Citadels are their round token.
    private func artChip(_ ctx: inout GraphicsContext, _ f: FactionID, _ t: UnitType, figure: Sprite,
                         count: Int, in rect: CGRect, art: Art) {
        if t == .citadel {
            ctx.draw(figure.image, in: figure.fit(in: rect.insetBy(dx: 0, dy: -rect.height * 0.15)))
        } else {
            let shape = Path(roundedRect: rect, cornerRadius: rect.height * 0.18)
            ctx.fill(shape, with: .color(art.tileColour(f) ?? Palette.faction(f)))
            ctx.stroke(shape, with: .color(.black.opacity(0.35)), lineWidth: 0.6)
            ctx.draw(figure.image, in: figure.fit(in: rect.insetBy(dx: rect.width * 0.12, dy: rect.height * 0.06)))
        }
        if count > 1 {
            let d = rect.height * 0.62
            let badge = CGRect(x: rect.maxX - d * 0.7, y: rect.minY - d * 0.3, width: d, height: d)
            ctx.fill(Path(ellipseIn: badge), with: .color(.black.opacity(0.8)))
            ctx.draw(Text("\(count)").font(.system(size: d * 0.68, weight: .bold)).foregroundStyle(.white),
                     at: CGPoint(x: badge.midX, y: badge.midY))
        }
    }

    private func house(_ ctx: inout GraphicsContext, at p: CGPoint, size: CGFloat, color: Color) {
        var path = Path()
        path.move(to: CGPoint(x: p.x - size / 2, y: p.y))
        path.addLine(to: CGPoint(x: p.x, y: p.y - size / 2))
        path.addLine(to: CGPoint(x: p.x + size / 2, y: p.y))
        path.addLine(to: CGPoint(x: p.x + size * 0.35, y: p.y))
        path.addLine(to: CGPoint(x: p.x + size * 0.35, y: p.y + size / 2))
        path.addLine(to: CGPoint(x: p.x - size * 0.35, y: p.y + size / 2))
        path.addLine(to: CGPoint(x: p.x - size * 0.35, y: p.y))
        path.closeSubpath()
        ctx.fill(path, with: .color(color))
        ctx.stroke(path, with: .color(.white), lineWidth: 1)
    }
}
