import Foundation

enum BuiltInDrills {
    static let babyScratchSlow = makeBabyScratch(bpm: 80, bars: 4)
    static let babyScratchMedium = makeBabyScratch(bpm: 90, bars: 4)
    static let babyScratchFast = makeBabyScratch(bpm: 120, bars: 4)

    // Trimmed down to just the baby scratch family for now while the
    // scoring/feel is being tuned; drag/scribble/release-timing/tempo
    // ladder will come back once baby scratch feels right.
    static let all: [ScratchPattern] = [babyScratchSlow, babyScratchMedium, babyScratchFast]

    // The first stroke lands the instant the countdown hands off to the
    // drill, with no lead-in the way every later stroke gets from the
    // stroke before it - so it gets a wider tolerance than the rest to
    // cover that reaction-time gap, instead of the same flat 100ms.
    private static let firstStrokeToleranceMs = 250.0
    private static let strokeToleranceMs = 100.0

    /// Alternating forward/back strokes on every eighth note, per the
    /// spec's example of what a baby scratch pattern looks like.
    private static func makeBabyScratch(bpm: Double, bars: Int) -> ScratchPattern {
        let eighthsPerBar = 8
        let totalEighths = bars * eighthsPerBar
        // Each sub-expression is pulled out and explicitly typed rather
        // than nested into the initializer call. Inline, the type checker
        // has to solve two ternaries, an implicit-member lookup
        // (.forward/.back), a `nil` that has to resolve to
        // ClosedRange<Double>?, and Double(i) * 0.5 all simultaneously,
        // which is enough to blow past its time limit ("unable to
        // type-check this expression in reasonable time").
        let strokes: [TargetStroke] = (0..<totalEighths).map { i in
            let beatPosition: Double = Double(i) * 0.5
            let direction: Direction = (i % 2 == 0) ? .forward : .back
            let tolerance: Double = (i == 0) ? firstStrokeToleranceMs : strokeToleranceMs
            let displacement: ClosedRange<Double>? = nil
            return TargetStroke(
                beatPosition: beatPosition,
                direction: direction,
                relativeDisplacement: displacement,
                timingToleranceMs: tolerance
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
