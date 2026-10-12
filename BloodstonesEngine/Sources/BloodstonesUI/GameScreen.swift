import SwiftUI

/// The play screen: the map, with the side panel on the right.
public struct GameScreen: View {
    let model: GameModel

    public init(model: GameModel) { self.model = model }

    public var body: some View {
        HStack(spacing: 0) {
            MapView(model: model)
            Divider()
            SidePanel(model: model).frame(width: 360)
        }
    }
}
