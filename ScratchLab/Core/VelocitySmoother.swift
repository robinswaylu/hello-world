import Foundation

/// Light low-pass + slew-rate limiting so the audio engine's playback rate
/// doesn't zipper on raw sensor noise between gyro updates. Tuned to add
/// under 10ms of effective lag at ~100Hz input.
struct VelocitySmoother {
    var lowPassAlpha: Double
    var maxSlewPerSecond: Double

    private var smoothed: Double = 0
    private var lastTimestamp: TimeInterval?

    init(lowPassAlpha: Double = 0.6, maxSlewPerSecond: Double = 200.0) {
        self.lowPassAlpha = lowPassAlpha
        self.maxSlewPerSecond = maxSlewPerSecond
    }

    mutating func process(_ z: Double, timestamp: TimeInterval) -> Double {
        defer { lastTimestamp = timestamp }

        guard let lastTimestamp else {
            smoothed = z
            return smoothed
        }

        let dt = max(timestamp - lastTimestamp, 0.0001)
        let lowPassTarget = smoothed + lowPassAlpha * (z - smoothed)
        let maxDelta = maxSlewPerSecond * dt
        let delta = (lowPassTarget - smoothed).clamped(to: -maxDelta...maxDelta)
        smoothed += delta
        return smoothed
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
