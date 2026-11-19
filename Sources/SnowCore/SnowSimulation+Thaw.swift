import Foundation

/// A gradual alternative to `clear()`: settled snow sinks away on the existing simulation clock.
extension SnowSimulation {
    public static let defaultThawDuration: Float = 8

    public var isThawing: Bool { thawRemaining > 0 }

    /// Starts melting every cap and loose grain so that all of it is gone after `duration`
    /// simulated seconds. Reduced Motion snaps to the cleared state instead of animating.
    public func beginThaw(duration: Float = SnowSimulation.defaultThawDuration) {
        guard duration.isFinite, duration > 0, !reducedMotion else { clear(); return }
        thawRemaining = min(duration, 60)
    }

    /// Scaling by the fraction of time left makes every height a straight line to zero that
    /// ends on time at any frame rate. It adds no clock, buffer, or faster mesh rebuild.
    func advanceThaw(dt: Float) {
        guard thawRemaining > 0 else { return }
        guard !reducedMotion, dt < thawRemaining else { clear(); return }
        let factor = (thawRemaining - dt) / thawRemaining
        thawRemaining -= dt
        for drift in drifts { drift.melt(by: factor) }
        looseSnow.melt(by: factor)
        // Queued hand-offs and releases stay whole: they join a cap or the field on a later
        // tick and melt there, and the final clear() drops anything still waiting.
        meshDirty = true
    }
}
