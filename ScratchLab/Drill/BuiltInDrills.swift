import Foundation

enum BuiltInDrills {
    static let babyScratchSlow = makeBabyScratch(bpm: 80, bars: 4)
    static let babyScratchMedium = makeBabyScratch(bpm: 90, bars: 4)
    static let babyScratchFast = makeBabyScratch(bpm: 120, bars: 4)

    // Trimmed down to just the baby scratch family for now while the
    // scoring/feel is being tuned; drag/scribble/release-timing/tempo
    // ladder will come back once baby scratch feels right.
    static let all: [ScratchPattern] = [babyScratchSlow, babyScratchMedium, babyScratchFast]

    // One empty bar between the count-in ending and the first stroke.
    // Without it the drill demands a stroke the instant the countdown
    // hands off; with it you get a full bar of metronome at tempo to
    // settle into the groove first. It's counted into the pattern's
    // `bars`, so a "4 bar" drill actually runs 5 bars end to end.
    private static let leadInBars = 1

    // Even with the lead-in bar, the first stroke is still the only one
    // with no preceding stroke to establish the rhythm, so it keeps a
    // wider tolerance than the flat 100ms every other stroke gets.
    private static let firstStrokeToleranceMs = 250.0
    private static let strokeToleranceMs = 100.0

    /// Alternating forward/back strokes on every eighth note, per the
    /// spec's example of what a baby scratch pattern looks like.
    private static func makeBabyScratch(bpm: Double, bars: Int) -> ScratchPattern {
        let eighthsPerBar = 8
        let totalEighths = bars * eighthsPerBar
        let leadInBeats: Double = Double(leadInBars) * DrillTimeline.beatsPerBar
        // Each sub-expression is pulled out and explicitly typed rather
        // than nested into the initializer call. Inline, the type checker
        // has to solve two ternaries, an implicit-member lookup
        // (.forward/.back), a `nil` that has to resolve to
        // ClosedRange<Double>?, and Double(i) * 0.5 all simultaneously,
        // which is enough to blow past its time limit ("unable to
        // type-check this expression in reasonable time").
        let strokes: [TargetStroke] = (0..<totalEighths).map { i in
            let beatPosition: Double = leadInBeats + Double(i) * 0.5
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
            bars: bars + leadInBars,
            strokes: strokes,
            beatLoopAsset: nil,
            defaultSampleAsset: "scratch-sentence"
        )
    }
}
