/// A mission's non-player behaviour and its special rules. One small type
/// per mission; there is no general rules language.
public protocol MissionScript: Sendable {
    /// Whether any piece may enter or be placed in `region` (e.g. Mission 1's
    /// Hill Folk line).
    func isEnterable(_ region: RegionID, in s: GameState) -> Bool

    /// Runs the next piece of a non-player faction's turn. The engine calls
    /// this repeatedly, resolving any battle it starts in between. Returns
    /// true when the turn is over.
    func step(_ s: inout GameState, engine: Engine) -> Bool

    /// Non-player battle decisions.
    func withdrawal(_ b: Battle, options: [RegionID], in s: GameState, engine: Engine) -> RegionID?
    func substitution(_ b: Battle, for f: FactionID, in s: GameState, engine: Engine) -> (tile: Int, replacing: Int)?
    func casualty(_ b: Battle, choices: [MapUnit], in s: GameState) -> Int
    func retreat(_ b: Battle, options: [RegionID], in s: GameState, engine: Engine) -> RegionID

    /// Whether `faction` regroups when its bag runs dry (it may not, as in
    /// Mission 1, where an empty Dragon Rider bag ends the game).
    func regroups(_ faction: FactionID) -> Bool

    /// Checked after every step; non-nil ends the game.
    func outcome(_ s: GameState) -> Outcome?
}
