import BloodstonesEngine
import SwiftUI

/// Credits, the licence, and where to find the rules.
struct AboutView: View {
    let art: Art?
    @Environment(\.dismiss) private var dismiss

    /// The publisher's downloads, from wallacedesigns.com.au/bloodstones-rules.
    private enum Links {
        static let rulesPage = URL(string: "https://www.wallacedesigns.com.au/bloodstones-rules/")!
        static let rulebook = URL(string: "https://drive.google.com/file/d/1NTuWisZ37103oKcX9sPIh1aJWbe1Bz_E/view")!
        static let mission1 = URL(string: "https://drive.google.com/file/d/1NJmQzIOoWPSkTutwby1uKJ1H6BfdMy8O/view")!
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let b = info?["CFBundleVersion"] as? String
        return b.map { "\(v) (\($0))" } ?? v
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bloodstones for iPad").font(.title2.weight(.semibold))
                        Text("Version \(version)").font(.caption).foregroundStyle(.secondary)
                        Text("© 2026 Brian Sniffen.  Built with Claude")
                    }
                    .padding(.vertical, 4)
                }
                Section("The game") {
                    Text("*Bloodstones* is designed by Martin Wallace and published by Wallace Designs. Rules © Martin Wallace 2020.  This is a hobby project in hopes of working with Wallace.")
                    Text("Artwork by Atticus McNaughton and Leith Walton, used in hopes of a license from Martin Wallace.")
                    Text("Solo campaign by Stephen Hurn.")
                }
                Section("Rules") {
                    Link(destination: Links.rulebook) { Label("Rulebook (PDF)", systemImage: "book") }
                    Link(destination: Links.mission1) { Label("Solo campaign: Mission 1, Dragon Hunt (PDF)", systemImage: "map") }
                    Link(destination: Links.rulesPage) { Label("All 18 solo missions and translated rulebooks", systemImage: "books.vertical") }
                    if let art, !art.cards.isEmpty {
                        NavigationLink { FactionCardsView(art: art) } label: {
                            Label("Faction cards", systemImage: "rectangle.stack")
                        }
                    } else {
                        Link(destination: Links.rulebook) { Label("Faction cards (rulebook pp. 24–26)", systemImage: "rectangle.stack") }
                    }
                }
            }
            .navigationTitle("About")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

/// The six faction cards from the rulebook.
struct FactionCardsView: View {
    let art: Art

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 440), spacing: 16)], spacing: 16) {
                ForEach(FactionID.allCases, id: \.self) { f in
                    if let card = art.cards[f] {
                        card.image.resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .shadow(radius: 2)
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Faction cards")
    }
}
