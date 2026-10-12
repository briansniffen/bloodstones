/// Everything a human player can do. Non-player factions never send
/// actions; their mission script acts for them inside `Engine.apply`.
public enum Action: Codable, Hashable, Sendable {
    /// Capture → main → construct → end of turn.
    case endPhase

    // Capture villages phase. The first capture names the one tile spent
    // this phase; later captures draw on its remaining pips (payWith nil).
    case captureVillage(region: RegionID, payWith: Int?)

    // Main actions.
    case build(tile: Int, region: RegionID, payWith: [Int])
    case move(legs: [MoveLeg], payWith: [Int])
    case battle(region: RegionID)

    // Construct villages phase; same one-tile budget as capture.
    case constructVillage(region: RegionID, payWith: Int?)

    // Battle decisions, made by whichever side the battle is waiting on.
    case withdraw(to: RegionID)
    case stand
    case substitute(tile: Int, replacing: Int)
    case keepTiles
    case eliminate(unit: Int)
    case retreat(to: RegionID)
}

/// Some units moving together from one region to another.
public struct MoveLeg: Codable, Hashable, Sendable {
    public let units: [Int]
    public let to: RegionID
    public init(units: [Int], to: RegionID) { self.units = units; self.to = to }
}

public enum Phase: String, Codable, Sendable {
    case capture, main, construct
    /// A mission script is running a non-player faction's turn.
    case nonPlayer
    case gameOver
}

public enum Outcome: Codable, Hashable, Sendable {
    case victory(String)
    case defeat(String)
}

public struct EngineError: Error, Equatable, CustomStringConvertible {
    public let description: String
    init(_ d: String) { description = d }
}

/// What happened during one `apply`, for the UI and for tests.
public enum Event: Codable, Hashable, Sendable {
    case turnStarted(FactionID)
    case drew(FactionID, count: Int)
    case regrouped(FactionID, regroups: Int, villagesScored: Int)
    case built(FactionID, UnitType, RegionID)
    case moved(FactionID, units: [Int], from: RegionID, to: RegionID)
    case villageBuilt(FactionID, RegionID)
    case villageCaptured(by: FactionID, from: FactionID, RegionID)
    case battleStarted(RegionID, attacker: FactionID, defender: FactionID)
    case battleTiles(FactionID, [Int])
    case substituted(FactionID, pips: Int)
    case battleRound(attacker: Int, defender: Int)
    case battleWon(FactionID, RegionID, victoryPoints: Int)
    case withdrew(FactionID, from: RegionID, to: RegionID)
    case retreated(FactionID, from: RegionID, to: RegionID)
    case eliminated(FactionID, UnitType, RegionID)
    case armyActivated(army: Int, by: UnitType)
    case armyWaits(army: Int, RegionID)
    case gameOver(Outcome)
}

/// A battle in progress. It pauses whenever a human has to decide.
public struct Battle: Codable, Equatable, Sendable {
    public enum Step: Codable, Equatable, Sendable {
        /// The defender may withdraw.
        case withdraw
        case substitute(FactionID)
        case casualty
        case retreat
    }

    public let region: RegionID
    public let attacker: FactionID
    public let defender: FactionID
    public var step: Step
    public var round = 1
    /// Battle tile values drawn this round, after any substitution.
    public var drawn: [FactionID: [Int]] = [:]
    public var substituted: Set<FactionID> = []
    public var loser: FactionID?
    /// Units each side had when the battle began; the winner scores the loser's.
    public let unitsAtStart: [FactionID: Int]

    public func opponent(of f: FactionID) -> FactionID { f == attacker ? defender : attacker }

    /// The faction whose decision the battle is waiting on.
    public var decider: FactionID {
        switch step {
        case .withdraw: defender
        case .substitute(let f): f
        case .casualty, .retreat: loser!
        }
    }
}
