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
    /// A press in progress: where it started, and whether it has turned
    /// into a hold (which peeks instead of tapping).
    @State private var press: CGPoint?
    @State private var holdTimer: Task<Void, Never>?

    public init(model: GameModel) { self.model = model }

    public var body: some View {
        GeometryReader { geo in
            let fit = MapFit(map: model.art?.map?.bounds ?? CGRect(origin: .zero, size: shapes.size), in: geo.size)
            let highlights = model.highlights()
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    draw(in: &ctx, fit: fit, highlights: highlights)
                }
                .contentShape(Rectangle())
                .gesture(pressGesture(fit))
                ArmyBoards(model: model, fit: fit)
                if let r = model.peek, let c = shapes.centres[r] {
                    PeekView(model: model, region: r)
                        .fixedSize()
                        .position(peekPosition(fit.toView(c), in: geo.size))
                        .allowsHitTesting(false)
                }
            }
        }
        .background(Palette.border.opacity(0.85))
    }

    /// Tap a region to act on it; hold to see everything in it.
    private func pressGesture(_ fit: MapFit) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                if press == nil {
                    press = v.startLocation
                    let r = target(at: v.startLocation, fit: fit)
                    holdTimer = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        if !Task.isCancelled, r.map({ !model.state.units(in: $0).isEmpty }) == true { model.peek = r }
                    }
                }
                if hypot(v.translation.width, v.translation.height) > 12 { holdTimer?.cancel() }
            }
            .onEnded { v in
                holdTimer?.cancel()
                defer { press = nil }
                if model.peek != nil { model.peek = nil; return }
                guard hypot(v.translation.width, v.translation.height) <= 12 else { return }
                if let r = target(at: v.startLocation, fit: fit) { model.tap(r) }
            }
    }

    /// The region a press is about: the one whose pieces are under the
    /// finger (pieces often spill over a border), else the region itself.
    func target(at p: CGPoint, fit: MapFit) -> RegionID? {
        let slop = max(6, 10 * fit.scale)
        let regions = Set(model.stacks.map(\.region)).union(model.state.villages.map(\.region))
        for r in regions.sorted() {
            let rects = layout(region: r, fit: fit).map(\.rect)
            if rects.contains(where: { $0.insetBy(dx: -slop, dy: -slop).contains(p) }) { return r }
        }
        return shapes.region(at: fit.toMap(p))
    }

    /// Above the finger, kept on screen.
    private func peekPosition(_ p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: min(max(p.x, 170), size.width - 170), y: max(p.y - 120, 110))
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
        let chip = markSize(fit)
        for id in model.map.regionIDs {
            let c = fit.toView(shapes.centres[id]!)
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
            drawPieces(&ctx, region: id, fit: fit)
        }
    }

    /// Size of cost badges and village houses.
    func markSize(_ fit: MapFit) -> CGFloat { max(13, (model.art?.map == nil ? 30 : 40) * fit.scale) }
    /// Size of unit tiles: big enough to read the figures.
    func chipSize(_ fit: MapFit) -> CGFloat { markSize(fit) * 2.5 }

    enum Piece {
        case tiles(FactionID, UnitType, count: Int, selected: Bool)
        case army(Stack, selected: Bool)
        case village(FactionID)
    }

    /// Where a region's pieces go, in view coordinates: loose units as tiles
    /// (grouped by type), armies as a heap, in rows under the region number
    /// (under the printed number circle on the board art), then villages.
    func layout(region: RegionID, fit: MapFit) -> [(piece: Piece, rect: CGRect)] {
        let chip = chipSize(fit), mark = markSize(fit)
        var c = fit.toView(shapes.centres[region]!)
        if model.art?.map != nil { c.y += 30 * fit.scale + chip * 0.45 }
        var pieces: [Piece] = []
        for st in model.stacks where st.region == region {
            let selected = st.units.contains { model.selectedUnits.contains($0.id) }
            if st.token != nil {
                pieces.append(.army(st, selected: selected))
            } else {
                for g in st.groups {
                    let sel = st.units.contains { $0.type == g.type && model.selectedUnits.contains($0.id) }
                    pieces.append(.tiles(st.faction, g.type, count: g.count, selected: sel))
                }
            }
        }
        var out: [(piece: Piece, rect: CGRect)] = []
        let perRow = 3
        let w = chip * 1.45, h = chip * 0.82
        for (i, piece) in pieces.enumerated() {
            let row = i / perRow, col = i % perRow
            let inRow = min(perRow, pieces.count - row * perRow)
            let x = c.x + (CGFloat(col) - CGFloat(inRow - 1) / 2) * (w + 4)
            let y = c.y + CGFloat(row) * (h + 4) + h * 0.2
            var rect = CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h)
            if case .army = piece {
                // A little bigger, and nudged right to make room for the token.
                rect = rect.insetBy(dx: -w * 0.08, dy: -h * 0.08).offsetBy(dx: h * 0.4, dy: 0)
            }
            out.append((piece, rect))
        }
        let rows = (pieces.count + perRow - 1) / perRow
        let villages = model.state.villages(in: region)
        let size = mark * 0.7
        let vy = c.y + CGFloat(rows) * (h + 4) - h * 0.3 + size * 0.6
        for (i, v) in villages.enumerated() {
            let x = c.x + (CGFloat(i) - CGFloat(villages.count - 1) / 2) * (mark * 0.75)
            out.append((.village(v.faction), CGRect(x: x - size / 2, y: vy - size / 2, width: size, height: size)))
        }
        return out
    }

    private func badge(_ ctx: inout GraphicsContext, _ text: String, at p: CGPoint, size: CGFloat) {
        let rect = CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
        ctx.fill(Path(ellipseIn: rect), with: .color(.white))
        ctx.stroke(Path(ellipseIn: rect), with: .color(.black.opacity(0.6)), lineWidth: 1)
        ctx.draw(Text(text).font(.system(size: size * 0.62, weight: .bold)).foregroundStyle(.black), at: p)
    }

    private func drawPieces(_ ctx: inout GraphicsContext, region: RegionID, fit: MapFit) {
        for (piece, rect) in layout(region: region, fit: fit) {
            switch piece {
            case .tiles(let f, let t, let n, let sel):
                tile(&ctx, f, t, in: rect)
                if n > 1 { countBadge(&ctx, n, rect: rect) }
                if sel { ctx.stroke(Path(roundedRect: rect, cornerRadius: 3), with: .color(Palette.selected), lineWidth: 2.5) }
            case .army(let st, let sel):
                heap(&ctx, st, in: rect, selected: sel)
            case .village(let f):
                if let icon = model.art?.village(f) {
                    ctx.draw(icon.image, in: icon.fit(in: rect))
                } else {
                    house(&ctx, at: CGPoint(x: rect.midX, y: rect.midY), size: rect.width * 0.86, color: Palette.faction(f))
                }
            }
        }
    }

    /// One tile: the art if there is some, else a coloured chip with a label.
    private func tile(_ ctx: inout GraphicsContext, _ f: FactionID, _ t: UnitType, in rect: CGRect) {
        if let art = model.art, let figure = art.unit(f, t) {
            artChip(&ctx, f, t, figure: figure, in: rect, art: art)
        } else {
            ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(Palette.faction(f)))
            ctx.draw(Text(Palette.short(t)).font(.system(size: rect.height * 0.62, weight: .bold)).foregroundStyle(.white),
                     at: CGPoint(x: rect.midX, y: rect.midY))
        }
    }

    /// An army: a few tiles heaped under its lead unit, the army token on
    /// the left and the unit count on the right.
    private func heap(_ ctx: inout GraphicsContext, _ st: Stack, in rect: CGRect, selected: Bool) {
        let colour = model.art?.tileColour(st.faction) ?? Palette.faction(st.faction)
        let layers = min(3, st.units.count)
        let step = rect.height * 0.14
        for k in stride(from: layers - 1, through: 1, by: -1) {
            let r = rect.offsetBy(dx: CGFloat(k) * step, dy: -CGFloat(k) * step)
            let shape = Path(roundedRect: r, cornerRadius: r.height * 0.18)
            ctx.fill(shape, with: .color(colour))
            ctx.stroke(shape, with: .color(.black.opacity(0.4)), lineWidth: 0.6)
        }
        tile(&ctx, st.faction, st.lead, in: rect)
        if selected { ctx.stroke(Path(roundedRect: rect, cornerRadius: 3), with: .color(Palette.selected), lineWidth: 2.5) }
        armyToken(&ctx, st, centre: CGPoint(x: rect.minX - rect.height * 0.1, y: rect.midY), size: rect.height * 0.95)
        countBadge(&ctx, st.units.count, rect: rect.offsetBy(dx: CGFloat(layers - 1) * step, dy: -CGFloat(layers - 1) * step))
    }

    private func armyToken(_ ctx: inout GraphicsContext, _ st: Stack, centre: CGPoint, size: CGFloat) {
        let r = CGRect(x: centre.x - size / 2, y: centre.y - size / 2, width: size, height: size)
        ctx.fill(Path(ellipseIn: r), with: .color(Palette.faction(st.faction)))
        ctx.stroke(Path(ellipseIn: r), with: .color(.white), lineWidth: 1.5)
        ctx.draw(Text(st.token ?? "").font(.system(size: size * 0.6, weight: .heavy)).foregroundStyle(.white), at: centre)
    }

    private func countBadge(_ ctx: inout GraphicsContext, _ n: Int, rect: CGRect) {
        let d = rect.height * 0.62
        let badge = CGRect(x: rect.maxX - d * 0.7, y: rect.minY - d * 0.3, width: d, height: d)
        ctx.fill(Path(ellipseIn: badge), with: .color(.black.opacity(0.8)))
        ctx.draw(Text("\(n)").font(.system(size: d * 0.68, weight: .bold)).foregroundStyle(.white),
                 at: CGPoint(x: badge.midX, y: badge.midY))
    }

    /// A tile in its faction's colour with the unit's figure. Citadels are
    /// their round token.
    private func artChip(_ ctx: inout GraphicsContext, _ f: FactionID, _ t: UnitType, figure: Sprite,
                         in rect: CGRect, art: Art) {
        if t == .citadel {
            ctx.draw(figure.image, in: figure.fit(in: rect.insetBy(dx: 0, dy: -rect.height * 0.15)))
        } else {
            let shape = Path(roundedRect: rect, cornerRadius: rect.height * 0.18)
            ctx.fill(shape, with: .color(art.tileColour(f) ?? Palette.faction(f)))
            ctx.stroke(shape, with: .color(.black.opacity(0.35)), lineWidth: 0.6)
            ctx.draw(figure.image, in: figure.fit(in: rect.insetBy(dx: rect.width * 0.12, dy: rect.height * 0.06)))
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
