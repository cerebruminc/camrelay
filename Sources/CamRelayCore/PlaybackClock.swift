/// Maps a continuous camera clock to a source position that can be paused or reset.
public struct PlaybackClock: Equatable, Sendable {
    public private(set) var generation: UInt64 = 1
    public private(set) var paused: Bool
    private var anchorTime: UInt64
    private var anchorPosition: UInt64 = 0

    public init(at time: UInt64 = 0, paused: Bool = false) {
        anchorTime = time
        self.paused = paused
    }

    public func position(at time: UInt64) -> UInt64 {
        anchorPosition + (paused || time < anchorTime ? 0 : time - anchorTime)
    }

    public mutating func select(at time: UInt64, paused: Bool) {
        generation += 1
        anchorTime = time
        anchorPosition = 0
        self.paused = paused
    }

    public mutating func setPaused(_ paused: Bool, at time: UInt64) {
        guard self.paused != paused else { return }
        anchorPosition = position(at: time)
        anchorTime = time
        self.paused = paused
        generation += 1
    }
}
