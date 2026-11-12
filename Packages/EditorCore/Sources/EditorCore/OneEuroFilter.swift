// What: One Euro filter for smoothing noisy per-frame values (video later).
// Inputs/Outputs: Value + timestamp in; adaptively smoothed value out.
// Threading: Mutating struct, not thread-safe; own it on one thread.
import Foundation

/// One Euro filter (Casiez et al.): a low-pass filter whose cutoff
/// adapts to the signal speed, so slow motion is heavily smoothed
/// while fast motion stays responsive. For video landmark tracks.
public struct OneEuroFilter: Sendable {
    public var rate: Float
    public var minCutoff: Float
    public var beta: Float
    public var derivativeCutoff: Float

    private var lastValue: Float = 0
    private var lastDerivative: Float = 0
    private var lastTimestamp: Float = 0
    private var isInitialized: Bool = false

    public init(
        rate: Float = 60,
        minCutoff: Float = 1.0,
        beta: Float = 0.0,
        derivativeCutoff: Float = 1.0
    ) {
        self.rate = rate
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    private func smoothingFactor(cutoff: Float, dt: Float) -> Float {
        guard cutoff > 0, dt > 0 else { return 1 }
        let tau = 1 / (2 * Float.pi * cutoff)
        return 1 / (1 + tau / dt)
    }

    /// Filters `value` at the given `timestamp` (seconds) and returns
    /// the smoothed value. The first call returns the value as-is.
    /// Non-positive dt reuses the last value (no NaN, no jump).
    public mutating func filter(value: Float, timestamp: Float) -> Float {
        guard isInitialized else {
            lastValue = value
            lastDerivative = 0
            lastTimestamp = timestamp
            isInitialized = true
            return value
        }
        let dt = timestamp - lastTimestamp
        guard dt > 0 else { return lastValue }
        let derivative = (value - lastValue) / dt
        let derivativeAlpha = smoothingFactor(cutoff: derivativeCutoff, dt: dt)
        let smoothedDerivative = lastDerivative + derivativeAlpha * (derivative - lastDerivative)
        let cutoff = minCutoff + beta * abs(smoothedDerivative)
        let alpha = smoothingFactor(cutoff: cutoff, dt: dt)
        let smoothed = lastValue + alpha * (value - lastValue)
        lastValue = smoothed
        lastDerivative = smoothedDerivative
        lastTimestamp = timestamp
        return smoothed
    }

    /// Resets the filter so the next call returns its value as-is.
    public mutating func reset() {
        lastValue = 0
        lastDerivative = 0
        lastTimestamp = 0
        isInitialized = false
    }
}
