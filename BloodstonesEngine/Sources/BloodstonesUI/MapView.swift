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

    init(scale: CGFloat, centre: CGPoint, in view: CGSize) {
        self.scale = scale
        origin = CGPoint(x: view.width / 2 - centre.x * scale, y: view.height / 2 - centre.y * scale)
    }

    func toView(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale) }
    func toMap(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - origin.x) / scale, y: (p.y - origin.y) / scale) }
    var transform: CGAffineTransform {
        CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: scale, y: scale)
    }
}

/// Where the map view is looking. Zoom 1 fills the view with the playable
/// area (the printed tracks around it are shown as overlays instead); it
/// can zoom out as far as the whole board and in to four times that.
struct Camera: Equatable {
    var zoom: CGFloat = 1
    /// The map point at the middle of the view; nil for the middle of the map.
    var centre: CGPoint?

    static let maxZoom: CGFloat = 4

    /// `playable` is the regions' extent, `whole` the board image's.
    func fit(playable: CGRect, whole: CGRect, in view: CGSize) -> MapFit {
        guard view.width > 0, view.height > 0 else { return MapFit(map: whole, in: CGSize(width: 1, height: 1)) }
        let base = max(view.width / playable.width, view.height / playable.height)
        let scale = base * zoom.clamped(to: minZoom(playable: playable, whole: whole, in: view)...Self.maxZoom)
        // Keep the playable area covering the view where it can; where it
        // can't, centre the board.
        func axis(_ c: CGFloat, _ span: CGFloat, _ lo: CGFloat, _ hi: CGFloat, _ mid: CGFloat) -> CGFloat {
            let half = span / 2 / scale
            return hi - lo >= 2 * half ? c.clamped(to: (lo + half)...(hi - half)) : mid
        }
        let c = centre ?? CGPoint(x: playable.midX, y: playable.midY)
        return MapFit(scale: scale,
                      centre: CGPoint(x: axis(c.x, view.width, playable.minX, playable.maxX, whole.midX),
                                      y: axis(c.y, view.height, playable.minY, playable.maxY, whole.midY)),
                      in: view)
    }

    /// Far enough out to see the whole board.
    func minZoom(playable: CGRect, whole: CGRect, in view: CGSize) -> CGFloat {
        let base = max(view.width / playable.width, view.height / playable.height)
        return min(1, min(view.width / whole.width, view.height / whole.height) / base)
    }
}

extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}

public struct MapView: View {
    let model: GameModel
    var shapes: MapShapes { model.shapes }
    /// A press in progress: where it started, and whether it has turned
    /// into a hold (which peeks instead of tapping).
    @State private var press: CGPoint?
    @State private var holdTimer: Task<Void, Never>?
    @State private var camera = Camera()
    /// The camera when the current drag or pinch began, and the fit then.
    @State private var dragStart: (camera: Camera, fit: MapFit)?
    @State private var pinchStart: (camera: Camera, fit: MapFit)?
    /// The current press has panned or pinched, so it isn't a tap.
    @State private var moved = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: GameModel) { self.model = model }

    var playable: CGRect { CGRect(origin: .zero, size: shapes.size) }
    var whole: CGRect { model.art?.map?.bounds ?? playable.insetBy(dx: -20, dy: -20) }

    public var body: some View {
        GeometryReader { geo in
            let fit = camera.fit(playable: playable, whole: whole, in: geo.size)
            let highlights = model.highlights()
            let glows = glowShapes(highlights)
            ZStack(alignment: .topLeading) {
                // The board, then the glow on highlighted regions (the only
                // layer that animates), then numbers, costs and pieces.
                Canvas { ctx, _ in drawBoard(&ctx, fit: fit) }
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: highlights.isEmpty || reduceMotion)) { tl in
                    Canvas { ctx, _ in
                        drawGlow(&ctx, fit: fit, glows: glows, phase: reduceMotion ? 0.6 : breath(tl.date))
                    }
                }
                .allowsHitTesting(false)
                Canvas { ctx, _ in
                    draw(in: &ctx, fit: fit, highlights: highlights)
                }
                .contentShape(Rectangle())
                .gesture(pressGesture(fit, in: geo.size))
                .simultaneousGesture(pinchGesture(fit, in: geo.size))
                // Floating over the map, fixed to the screen.
                TracksView(model: model)
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                ArmyBoards(model: model, size: CGSize(width: min(340, geo.size.width * 0.42), height: geo.size.height - 90))
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                zoomButtons(geo.size)
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                if let r = model.peek, let c = shapes.centres[r] {
                    PeekView(model: model, region: r)
                        .fixedSize()
                        .position(peekPosition(fit.toView(c), in: geo.size))
                        .allowsHitTesting(false)
                }
            }
            .clipped()
        }
        .background(Palette.border.opacity(0.85))
    }

    /// Tap a region to act on it; hold to see everything in it; drag to
    /// move the map.
    private func pressGesture(_ fit: MapFit, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                if press == nil {
                    press = v.startLocation
                    dragStart = (camera, fit)
                    let r = target(at: v.startLocation, fit: fit)
                    holdTimer = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        if !Task.isCancelled, !moved, r.map({ !model.state.units(in: $0).isEmpty }) == true { model.peek = r }
                    }
                }
                if hypot(v.translation.width, v.translation.height) > 12 {
                    holdTimer?.cancel()
                    if model.peek == nil { moved = true }
                }
                // Pan, unless peeking or pinching (the pinch moves the map then).
                if moved, model.peek == nil, pinchStart == nil, let start = dragStart {
                    camera = Camera(zoom: start.camera.zoom,
                                    centre: start.fit.toMap(CGPoint(x: size.width / 2 - v.translation.width,
                                                                    y: size.height / 2 - v.translation.height)))
                }
            }
            .onEnded { v in
                holdTimer?.cancel()
                defer { press = nil; dragStart = nil; moved = false }
                if model.peek != nil { model.peek = nil; return }
                guard !moved, hypot(v.translation.width, v.translation.height) <= 12 else { return }
                if let r = target(at: v.startLocation, fit: fit) { model.tap(r) }
            }
    }

    /// Pinch to zoom about the fingers.
    private func pinchGesture(_ fit: MapFit, in size: CGSize) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { v in
                holdTimer?.cancel()
                moved = true
                if pinchStart == nil { pinchStart = (camera, fit) }
                guard let start = pinchStart else { return }
                setZoom(start.camera.zoom * v.magnification, keeping: v.startLocation, from: start.fit, in: size)
            }
            .onEnded { _ in pinchStart = nil }
    }

    /// Zoom so the map point under `anchor` (in `from`) stays put.
    private func setZoom(_ zoom: CGFloat, keeping anchor: CGPoint, from: MapFit, in size: CGSize) {
        let z = zoom.clamped(to: camera.minZoom(playable: playable, whole: whole, in: size)...Camera.maxZoom)
        let p = from.toMap(anchor)
        let scale = Camera(zoom: z).fit(playable: playable, whole: whole, in: size).scale
        camera = Camera(zoom: z, centre: CGPoint(x: p.x - (anchor.x - size.width / 2) / scale,
                                                 y: p.y - (anchor.y - size.height / 2) / scale))
    }

    private func zoomButtons(_ size: CGSize) -> some View {
        let fit = camera.fit(playable: playable, whole: whole, in: size)
        let mid = CGPoint(x: size.width / 2, y: size.height / 2)
        return VStack(spacing: 8) {
            Button { setZoom(camera.zoom * 1.5, keeping: mid, from: fit, in: size) } label: {
                Image(systemName: "plus").frame(width: 44, height: 40)
            }
            Button { setZoom(camera.zoom / 1.5, keeping: mid, from: fit, in: size) } label: {
                Image(systemName: "minus").frame(width: 44, height: 40)
            }
            Button { camera = Camera() } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left").frame(width: 44, height: 40)
            }
        }
        .buttonStyle(BoardButtonStyle())
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

    /// The board art (or plain terrain and borders), with regions out of
    /// play darkened.
    private func drawBoard(_ ctx: inout GraphicsContext, fit: MapFit) {
        let board = model.art?.map
        if let board {
            let r = board.bounds
            let tl = fit.toView(r.origin)
            ctx.draw(board.sprite.image, in: CGRect(x: tl.x, y: tl.y, width: r.width * fit.scale, height: r.height * fit.scale))
        }
        for id in model.map.regionIDs {
            let path = shapes.paths[id]!.applying(fit.transform)
            if board == nil {
                ctx.fill(path, with: .color(Palette.terrain(model.map.terrain(of: id))))
                ctx.stroke(path, with: .color(Palette.border.opacity(0.7)), lineWidth: 0.8)
            }
            if !model.engine.script.isEnterable(id, in: model.state) { ctx.fill(path, with: .color(Palette.offLimits)) }
        }
    }

    /// 0…1 and back, slowly: one breath every two seconds.
    private func breath(_ date: Date) -> Double {
        (sin(date.timeIntervalSinceReferenceDate * .pi) + 1) / 2
    }

    /// Highlighted regions merged by kind, in map coordinates: a move range
    /// glows as one area, outlined once, not region by region. Region
    /// outlines don't quite meet, so each is fattened a little first.
    private func glowShapes(_ highlights: [RegionID: Highlight]) -> [(path: Path, h: Highlight)] {
        let kinds = Dictionary(grouping: highlights, by: { Palette.glowKind($0.value) })
        return kinds.keys.sorted().map { kind in
            let group = kinds[kind]!
            let union = group.map(\.key).sorted().reduce(nil as CGPath?) { acc, r in
                let p = shapes.paths[r]!.cgPath
                let fat = p.union(p.copy(strokingWithWidth: 4, lineCap: .round, lineJoin: .round, miterLimit: 2))
                return acc?.union(fat) ?? fat
            }
            return (Path(union!), group[0].value)
        }
    }

    /// Highlighted areas glow: a soft aura spilling over the edge into the
    /// neighbours, a light wash inside, and a crisp coloured edge. The aura
    /// breathes with `phase`.
    private func drawGlow(_ ctx: inout GraphicsContext, fit: MapFit, glows: [(path: Path, h: Highlight)], phase: Double) {
        let lit = glows.map { (path: $0.path.applying(fit.transform), h: $0.h) }
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 6 + 4 * phase))
            for (path, h) in lit {
                let k = Palette.glowStrength(h)
                l.stroke(path, with: .color(Palette.glow(h).opacity((0.55 + 0.35 * phase) * k)), lineWidth: 10 + 6 * phase)
            }
        }
        for (path, h) in lit {
            ctx.fill(path, with: .color(Palette.glow(h).opacity((0.14 + 0.08 * phase) * Palette.glowStrength(h))))
            ctx.stroke(path, with: .color(Palette.glow(h).opacity(0.95)), lineWidth: h == .target || h == .selected ? 3 : 2)
        }
    }

    private func draw(in ctx: inout GraphicsContext, fit: MapFit, highlights: [RegionID: Highlight]) {
        let board = model.art?.map
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
        let w = chip * 1.45, h = w / TileLook.aspect
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
                // Several of a type lie in a little pile.
                let seed = region * 97 + t.rawValue.utf8.reduce(0) { $0 &* 31 &+ Int($1) }
                let step = rect.height * 0.14
                for k in stride(from: min(n, 3) - 1, through: 1, by: -1) {
                    physicalTile(&ctx, f, t, in: rect.offsetBy(dx: CGFloat(k) * step, dy: -CGFloat(k) * step),
                                 tilt: TileLook.tilt(seed + k), faceless: true)
                }
                physicalTile(&ctx, f, t, in: rect, tilt: TileLook.tilt(seed), selected: sel)
                if n > 1 { countBadge(&ctx, n, rect: rect.offsetBy(dx: CGFloat(min(n, 3) - 1) * step, dy: -CGFloat(min(n, 3) - 1) * step)) }
            case .army(let st, let sel):
                heap(&ctx, st, in: rect, selected: sel)
            case .village(let f):
                if let icon = model.art?.village(f) {
                    ctx.drawLayer { l in
                        l.addFilter(.shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1))
                        l.draw(icon.image, in: icon.fit(in: rect))
                    }
                } else {
                    house(&ctx, at: CGPoint(x: rect.midX, y: rect.midY), size: rect.width * 0.86, color: Palette.faction(f))
                }
            }
        }
    }

    /// One tile as a piece of card: the printed tile (or a stand-in), the
    /// edge showing its thickness, a shadow, and a slight hand-placed tilt.
    /// A faceless tile is one lying under others, only its colour showing.
    private func physicalTile(_ ctx: inout GraphicsContext, _ f: FactionID, _ t: UnitType, in rect: CGRect,
                              tilt: Angle, selected: Bool = false, faceless: Bool = false) {
        let art = model.art
        ctx.drawLayer { l in
            l.translateBy(x: rect.midX, y: rect.midY)
            l.rotate(by: tilt)
            let colour = TileLook.colour(art, f)
            l.addFilter(.shadow(color: .black.opacity(0.35), radius: rect.height * 0.07, x: 0, y: rect.height * 0.06))
            if t == .citadel {
                let d = rect.height * 1.2
                let r = CGRect(x: -d / 2, y: -d / 2, width: d, height: d)
                let under = Path(ellipseIn: r.offsetBy(dx: 0, dy: d * TileLook.thickness))
                l.fill(under, with: .color(colour))
                l.fill(under, with: .color(.black.opacity(0.4)))
                if let token = art?.unit(f, .citadel) { l.draw(token.image, in: r) } else {
                    l.fill(Path(ellipseIn: r), with: .color(Palette.faction(f)))
                }
                if selected { l.stroke(Path(ellipseIn: r), with: .color(Palette.selected), lineWidth: 2.5) }
                return
            }
            let r = CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height)
            let cr = TileLook.cornerRadius(r.height)
            let shape = Path(roundedRect: r, cornerRadius: cr)
            let under = Path(roundedRect: r.offsetBy(dx: 0, dy: r.height * TileLook.thickness), cornerRadius: cr)
            l.fill(under, with: .color(colour))
            l.fill(under, with: .color(.black.opacity(0.4)))
            if faceless {
                l.fill(shape, with: .color(colour))
            } else if let printed = art?.tile(f, t) {
                l.draw(printed.image, in: r)
            } else if let figure = art?.unit(f, t) {
                l.fill(shape, with: .color(colour))
                l.draw(figure.image, in: figure.fit(in: r.insetBy(dx: r.width * 0.14, dy: r.height * 0.06)))
            } else {
                l.fill(shape, with: .color(Palette.faction(f)))
                l.draw(Text(Palette.short(t)).font(.system(size: r.height * 0.6, weight: .bold)).foregroundStyle(.white),
                       at: .zero)
            }
            l.stroke(shape, with: .color(.black.opacity(0.25)), lineWidth: 0.6)
            if selected { l.stroke(shape, with: .color(Palette.selected), lineWidth: 2.5) }
        }
    }

    /// An army: a few tiles heaped under its lead unit, the army token on
    /// the left and the unit count on the right.
    private func heap(_ ctx: inout GraphicsContext, _ st: Stack, in rect: CGRect, selected: Bool) {
        let layers = min(3, st.units.count)
        let step = rect.height * 0.14
        let lead = st.ordered[0]
        for k in stride(from: layers - 1, through: 1, by: -1) {
            physicalTile(&ctx, st.faction, lead.type, in: rect.offsetBy(dx: CGFloat(k) * step, dy: -CGFloat(k) * step),
                         tilt: TileLook.tilt(st.ordered[k].id), faceless: true)
        }
        physicalTile(&ctx, st.faction, lead.type, in: rect, tilt: TileLook.tilt(lead.id), selected: selected)
        armyToken(&ctx, st, centre: CGPoint(x: rect.minX - rect.height * 0.1, y: rect.midY), size: rect.height * 0.95)
        countBadge(&ctx, st.units.count, rect: rect.offsetBy(dx: CGFloat(layers - 1) * step, dy: -CGFloat(layers - 1) * step))
    }

    /// A round card token with the army's letter or number.
    private func armyToken(_ ctx: inout GraphicsContext, _ st: Stack, centre: CGPoint, size: CGFloat) {
        ctx.drawLayer { l in
            let r = CGRect(x: centre.x - size / 2, y: centre.y - size / 2, width: size, height: size)
            l.addFilter(.shadow(color: .black.opacity(0.35), radius: size * 0.07, x: 0, y: size * 0.06))
            let under = Path(ellipseIn: r.offsetBy(dx: 0, dy: size * TileLook.thickness))
            l.fill(under, with: .color(Palette.faction(st.faction)))
            l.fill(under, with: .color(.black.opacity(0.4)))
            l.fill(Path(ellipseIn: r), with: .color(Palette.faction(st.faction)))
            l.stroke(Path(ellipseIn: r.insetBy(dx: 1, dy: 1)), with: .color(.white), lineWidth: max(1, size * 0.06))
            l.draw(Text(st.token ?? "").font(.system(size: size * 0.6, weight: .heavy)).foregroundStyle(.white),
                   at: CGPoint(x: r.midX, y: r.midY))
        }
    }

    private func countBadge(_ ctx: inout GraphicsContext, _ n: Int, rect: CGRect) {
        let d = rect.height * 0.62
        let badge = CGRect(x: rect.maxX - d * 0.7, y: rect.minY - d * 0.3, width: d, height: d)
        ctx.fill(Path(ellipseIn: badge), with: .color(.black.opacity(0.8)))
        ctx.draw(Text("\(n)").font(.system(size: d * 0.68, weight: .bold)).foregroundStyle(.white),
                 at: CGPoint(x: badge.midX, y: badge.midY))
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
