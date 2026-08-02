import Foundation

enum BuiltInDrills {
    static let babyScratch80 = makeBabyScratch(bpm: 80, bars: 4)
    static let babyScratch120 = makeBabyScratch(bpm: 120, bars: 4)

    static let all: [ScratchPattern] = [babyScratch80, babyScratch120]

    /// Alternating forward/back strokes on every eighth note, per the
    /// spec's example of what a baby scratch pattern looks like.
    private static func makeBabyScratch(bpm: Double, bars: Int) -> ScratchPattern {
        let eighthsPerBar = 8
        let totalEighths = bars * eighthsPerBar
        let strokes = (0..<totalEighths).map { i -> TargetStroke in
            TargetStroke(
                beatPosition: Double(i) * 0.5,
                direction: i % 2 == 0 ? .forward : .back,
                relativeDisplacement: nil,
                timingToleranceMs: 100
            )
        }
        return ScratchPattern(
            id: "baby-scratch-\(Int(bpm))",
            name: "Baby Scratch (\(Int(bpm)) BPM)",
            bpm: bpm,
            bars: bars,
            strokes: strokes,
            beatLoopAsset: nil,
            defaultSampleAsset: "sine-sweep"
        )
    }
}
