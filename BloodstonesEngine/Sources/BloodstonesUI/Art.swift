import BloodstonesEngine
import Foundation
import ImageIO
import SwiftUI

/// An image with its size in pixels, for fitting it into a rectangle.
public struct Sprite: Sendable {
    public let image: Image
    public let size: CGSize

    /// The largest rectangle with the sprite's shape that fits in `rect`, centred.
    func fit(in rect: CGRect) -> CGRect {
        let s = min(rect.width / size.width, rect.height / size.height)
        let w = size.width * s, h = size.height * s
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}

/// The publisher's artwork, cut from the PDFs by `tools/art/extract_art.py`
/// into an `art/` folder (licensed, so it stays out of git). The app draws
/// plain shapes for anything missing.
public struct Art: Sendable {
    public struct MapArt: Sendable {
        public let sprite: Sprite
        /// Where map coordinate (0, 0) falls in the image: the board frame
        /// around the playable area.
        public let inset: CGPoint
        /// The image's extent in map coordinates.
        public var bounds: CGRect {
            CGRect(x: -inset.x, y: -inset.y, width: sprite.size.width, height: sprite.size.height)
        }
    }

    public let map: MapArt?
    let units: [FactionID: [UnitType: Sprite]]
    let citadels: [FactionID: Sprite]
    let villages: [FactionID: Sprite]
    public let cards: [FactionID: Sprite]
    let tileColours: [FactionID: Color]

    func unit(_ f: FactionID, _ t: UnitType) -> Sprite? {
        t == .citadel ? citadels[f] : units[f]?[t]
    }
    func village(_ f: FactionID) -> Sprite? { villages[f] }
    func tileColour(_ f: FactionID) -> Color? { tileColours[f] }

    private struct Manifest: Decodable {
        struct MapEntry: Decodable { let file: String; let inset: [Double] }
        struct FactionEntry: Decodable { let tile: String }
        let maps: [String: MapEntry]
        let factions: [String: FactionEntry]
    }

    /// Loads `art.json` and the images for one map from an `art/` folder.
    public static func load(from dir: URL, mapId: String) throws -> Art {
        let m = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: dir.appendingPathComponent("art.json")))
        func sprite(_ path: String) -> Sprite? {
            let url = dir.appendingPathComponent(path)
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
            return Sprite(image: Image(decorative: cg, scale: 1),
                          size: CGSize(width: cg.width, height: cg.height))
        }
        var units: [FactionID: [UnitType: Sprite]] = [:]
        var citadels: [FactionID: Sprite] = [:], villages: [FactionID: Sprite] = [:], cards: [FactionID: Sprite] = [:]
        var colours: [FactionID: Color] = [:]
        for f in FactionID.allCases {
            for t in UnitType.allCases {
                if let s = sprite("units/\(f.rawValue)/\(t.rawValue).png") { units[f, default: [:]][t] = s }
            }
            citadels[f] = sprite("citadels/\(f.rawValue).png")
            villages[f] = sprite("villages/\(f.rawValue).png")
            cards[f] = sprite("cards/\(f.rawValue).jpg")
            if let hex = m.factions[f.rawValue]?.tile { colours[f] = Color(hex: hex) }
        }
        let map = m.maps[mapId].flatMap { e in
            sprite(e.file).map { MapArt(sprite: $0, inset: CGPoint(x: e.inset[0], y: e.inset[1])) }
        }
        return Art(map: map, units: units, citadels: citadels, villages: villages, cards: cards, tileColours: colours)
    }
}

extension Color {
    /// `#rrggbb`.
    init?(hex: String) {
        guard hex.hasPrefix("#"), hex.count == 7, let v = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double(v >> 16 & 0xff) / 255, green: Double(v >> 8 & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}
