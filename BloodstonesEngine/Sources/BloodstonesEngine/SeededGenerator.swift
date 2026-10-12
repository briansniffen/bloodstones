/// SplitMix64. Lives in `GameState`, so a saved game replays exactly.
/// Bounded draws use our own rejection sampling rather than the standard
/// library's `random(in:using:)`, whose algorithm is not promised to stay
/// the same across Swift versions.
public struct SeededGenerator: RandomNumberGenerator, Codable, Sendable, Equatable {
    public private(set) var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in `0..<bound`.
    public mutating func index(below bound: Int) -> Int {
        precondition(bound > 0)
        let b = UInt64(bound)
        let limit = UInt64.max - UInt64.max % b
        while true {
            let x = next()
            if x < limit { return Int(x % b) }
        }
    }
}
