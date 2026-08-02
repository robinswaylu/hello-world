import Foundation

enum BuiltInDrills {
    static let babyScratchSlow = makeBabyScratch(bpm: 80, bars: 4)
    static let babyScratchMedium = makeBabyScratch(bpm: 90, bars: 4)
    static let babyScratchFast = makeBabyScratch(bpm: 120, bars: 4)

    // Trimmed down to just the baby scratch family for now while the
    // scoring/feel is being tuned; drag/scribble/release-timing/tempo
    // ladder will come back once baby scratch feels right.
    static let all: [ScratchPattern] = [babyScratchSlow, babyScratchMedium, babyScratchFast]

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
            defaultSampleAsset: "scratch-sentence"
        )
    }
}
