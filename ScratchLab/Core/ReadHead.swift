import Foundation

/// Maintains a fractional read position into a mono sample buffer and
/// produces interpolated output frames as the position is advanced by an
/// arbitrary (possibly negative, possibly fractional) rate. Forward rate
/// plays forward, negative rate reverses, linear interpolation covers
/// fractional positions, and the position wraps at the loop boundary.
///
/// This is the core scratch DSP and the whole reason a custom
/// AVAudioSourceNode is used instead of AVAudioUnitVarispeed: neither that
/// nor AVAudioPlayerNode's own rate control supports negative rates.
struct ReadHead {
    let samples: [Float]
    let loopStart: Int
    let loopEnd: Int // exclusive

    private(set) var position: Double

    init(samples: [Float], loopStart: Int = 0, loopEnd: Int? = nil, startPosition: Double? = nil) {
        self.samples = samples
        self.loopStart = loopStart
        self.loopEnd = loopEnd ?? samples.count
        self.position = startPosition ?? Double(loopStart)
    }

    var loopLength: Int { loopEnd - loopStart }

    /// Reads one frame at the current position, then advances by `rate`.
    mutating func nextFrame(rate: Double) -> Float {
        let value = interpolatedValue(at: position)
        position += rate
        wrapIfNeeded()
        return value
    }

    /// Renders `frameCount` frames, ramping the rate linearly from
    /// `startRate` to `endRate` across the buffer. This is the anti-zipper
    /// mechanism: gyro updates arrive far less often than render callbacks,
    /// so each callback smooths the transition to the latest target rate
    /// instead of snapping to it.
    mutating func render(frameCount: Int, startRate: Double, endRate: Double) -> [Float] {
        guard frameCount > 0 else { return [] }
        var output = [Float](repeating: 0, count: frameCount)
        for frame in 0..<frameCount {
            let t = frameCount > 1 ? Double(frame) / Double(frameCount - 1) : 1.0
            let rate = startRate + (endRate - startRate) * t
            output[frame] = nextFrame(rate: rate)
        }
        return output
    }

    private mutating func wrapIfNeeded() {
        guard loopLength > 0 else { return }
        while position >= Double(loopEnd) {
            position -= Double(loopLength)
        }
        while position < Double(loopStart) {
            position += Double(loopLength)
        }
    }

    private func interpolatedValue(at position: Double) -> Float {
        let lower = Int(position.rounded(.down))
        let frac = Float(position - Double(lower))
        let a = sampleAt(lower)
        let b = sampleAt(lower + 1)
        return a + (b - a) * frac
    }

    private func sampleAt(_ index: Int) -> Float {
        guard loopLength > 0 else { return 0 }
        var i = index
        while i < loopStart { i += loopLength }
        while i >= loopEnd { i -= loopLength }
        return samples.indices.contains(i) ? samples[i] : 0
    }
}
