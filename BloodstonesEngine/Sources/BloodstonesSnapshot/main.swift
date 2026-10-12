import AppKit
import BloodstonesEngine
import BloodstonesUI
import SwiftUI

// Renders the play screen for a few game positions to PNGs, so the UI can
// be checked without a simulator.
//   swift run BloodstonesSnapshot <output dir>
//   swift run BloodstonesSnapshot --icon <file.png>

@MainActor func render(_ model: GameModel, to url: URL, size: CGSize = CGSize(width: 1194, height: 834)) {
    let view = GameScreen(model: model)
        .frame(width: size.width, height: size.height)
        .environment(\.snapshotMode, true)
        .background(Color.white)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
        print("render failed for \(url.lastPathComponent)"); return
    }
    try? png.write(to: url)
    print("wrote \(url.path)")
}

/// `--icon <file.png>`: the 1024-px app icon, opaque as App Store Connect requires.
@MainActor func renderIcon(to url: URL) {
    let renderer = ImageRenderer(content: IconView().frame(width: 1024, height: 1024))
    renderer.scale = 1
    renderer.isOpaque = true
    guard let cg = renderer.cgImage,
          let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
        print("icon render failed"); return
    }
    try? png.write(to: url)
    print("wrote \(url.path)")
}

@MainActor func main() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.first == "--icon", args.count > 1 { renderIcon(to: URL(fileURLWithPath: args[1])); return }
    let out = URL(fileURLWithPath: args.first ?? ".")
    var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    while !FileManager.default.fileExists(atPath: dir.appendingPathComponent("data/factions.json").path) {
        dir.deleteLastPathComponent()
        guard dir.path != "/" else { print("no data/ found"); return }
    }
    let data = try GameData.load(from: dir.appendingPathComponent("data"))
    let start = data.newGame(seed: 7)

    // 1. Opening: main phase, the stack on 61 selected.
    let m1 = GameModel(engine: data.engine, state: start)
    m1.perform(.endPhase)
    m1.tap(61)
    render(m1, to: out.appendingPathComponent("1-move.png"))
    m1.tap(53)
    render(m1, to: out.appendingPathComponent("1b-confirm.png"))

    // 2. A battle: cavalry into the skirmisher on 52, then fight.
    let m2 = GameModel(engine: data.engine, state: start)
    m2.perform(.endPhase)
    m2.tap(61)
    for u in m2.selectedUnits where m2.state.unit(u)?.type != .cavalry { m2.toggleUnit(u) }
    m2.tap(52)
    m2.confirmPending()
    m2.tap(52)
    render(m2, to: out.appendingPathComponent("2-battle.png"))

    // 3. A few turns in, ending phases only, to show the Dragon Riders moving.
    let m3 = GameModel(engine: data.engine, state: start)
    for _ in 0..<9 where m3.endPhaseAvailable { m3.perform(.endPhase) }
    render(m3, to: out.appendingPathComponent("3-later.png"))
}

try MainActor.assumeIsolated { try main() }
