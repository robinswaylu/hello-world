import Foundation

/// Generates a placeholder scratch tone (a sine sweep) so the audio engine
/// is testable before any real, licensed sample content exists. Per the
/// spec, the classic "ahh"/"fresh" scratch samples are copyrighted and
/// must not ship — this generator exists specifically so dev/testing
/// doesn't depend on sourcing real audio first.
enum SineSweepGenerator {
    static func generate(startFrequency: Double, endFrequency: Double, duration: Double, sampleRate: Double) -> [Float] {
        let frameCount = Int(duration * sampleRate)
        guard frameCount > 0 else { return [] }

        var samples = [Float](repeating: 0, count: frameCount)
        var phase = 0.0
        for i in 0..<frameCount {
            let t = Double(i) / Double(frameCount)
            let instantaneousFrequency = startFrequency + (endFrequency - startFrequency) * t
            phase += 2 * .pi * instantaneousFrequency / sampleRate
            samples[i] = Float(sin(phase))
        }
        return samples
    }
}
