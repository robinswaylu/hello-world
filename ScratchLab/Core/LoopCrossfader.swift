import Foundation

/// Bakes a linear crossfade into the tail of a loop region so the wrap
/// point is seamless in both playback directions, without needing
/// direction-aware logic in the read head itself.
enum LoopCrossfader {
    static func apply(to samples: [Float], loopStart: Int, loopEnd: Int, crossfadeFrames: Int) -> [Float] {
        var result = samples
        let loopLength = loopEnd - loopStart
        let frames = min(crossfadeFrames, loopLength / 2)
        guard frames > 0 else { return result }

        for i in 0..<frames {
            let tailIndex = loopEnd - frames + i
            let headIndex = loopStart + i
            guard result.indices.contains(tailIndex), result.indices.contains(headIndex) else { continue }
            let fadeIn = Float(i + 1) / Float(frames)
            let fadeOut = 1 - fadeIn
            result[tailIndex] = result[tailIndex] * fadeOut + samples[headIndex] * fadeIn
        }
        return result
    }
}
