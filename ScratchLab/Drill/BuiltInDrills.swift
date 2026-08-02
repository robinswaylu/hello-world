import Foundation

enum BuiltInDrills {
    static let babyScratchSlow = makeBabyScratch(bpm: 80, bars: 4)
    static let babyScratchMedium = makeBabyScratch(bpm: 90, bars: 4)
    static let babyScratchFast = makeBabyScratch(bpm: 120, bars: 4)

    /// Same 90 BPM pulse as `babyScratchMedium`, but on sixteenth notes -
    /// four strokes per beat instead of two, so each stroke gets half the
    /// time. Everything that depends on stroke spacing scales with it:
    /// the timing tolerance (kept at the same *proportion* of the gap, so
    /// it's the same difficulty rather than an unplayably wide window),
    /// and the metronome, which subdivides to match so every stroke still
    /// lands on a click.
    static let babyScratchDoubleTime90 = makeBabyScratch(
        bpm: 90,
        bars: 4,
        strokesPerBeat: 4,
        strokeToleranceMs: 50,
        firstStrokeToleranceMs: 125,
        // A double-time scratch is a shorter, tighter motion - not the
        // same throw at twice the speed. Without shortening it, hitting
        // on-target amplitude here would need ~10.4 rad/s peaks; with it,
        // ~6.6 rad/s, in line with the other drills.
        nominalStrokeDisplacement: 0.7,
        nameSuffix: "Double Time"
    )

    // Trimmed down to just the baby scratch family for now while the
    // scoring/feel is being tuned; drag/scribble/release-timing/tempo
    // ladder will come back once baby scratch feels right.
    static let all: [ScratchPattern] = [
        babyScratchSlow,
        babyScratchMedium,
        babyScratchFast,
        babyScratchDoubleTime90,
    ]

    // One empty bar between the count-in ending and the first stroke.
    // Without it the drill demands a stroke the instant the countdown
    // hands off; with it you get a full bar of metronome at tempo to
    // settle into the groove first. It's counted into the pattern's
    // `bars`, so a "4 bar" drill actually runs 5 bars end to end.
    private static let leadInBars = 1

    private static let defaultStrokeToleranceMs = 100.0

    // Even with the lead-in bar, the first stroke is still the only one
    // with no preceding stroke to establish the rhythm, so it gets a
    // wider tolerance than every other stroke.
    private static let defaultFirstStrokeToleranceMs = 250.0

    /// Alternating forward/back strokes on an even subdivision of the beat,
    /// per the spec's example of what a baby scratch pattern looks like.
    private static func makeBabyScratch(
        bpm: Double,
        bars: Int,
        strokesPerBeat: Int = 2,
        strokeToleranceMs: Double = defaultStrokeToleranceMs,
        firstStrokeToleranceMs: Double = defaultFirstStrokeToleranceMs,
        nominalStrokeDisplacement: Double? = nil,
        nameSuffix: String? = nil
    ) -> ScratchPattern {
        let gapBeats: Double = 1.0 / Double(strokesPerBeat)
        let strokesPerBar = Int(DrillTimeline.beatsPerBar) * strokesPerBeat
        let totalStrokes = bars * strokesPerBar
        let leadInBeats: Double = Double(leadInBars) * DrillTimeline.beatsPerBar

        // Each sub-expression is pulled out and explicitly typed rather
        // than nested into the initializer call. Inline, the type checker
        // has to solve two ternaries, an implicit-member lookup
        // (.forward/.back), a `nil` that has to resolve to
        // ClosedRange<Double>?, and the arithmetic all simultaneously,
        // which is enough to blow past its time limit ("unable to
        // type-check this expression in reasonable time").
        let strokes: [TargetStroke] = (0..<totalStrokes).map { i in
            let beatPosition: Double = leadInBeats + Double(i) * gapBeats
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

        let suffix: String = nameSuffix.map { " \($0)" } ?? ""
        let idSuffix: String = nameSuffix.map { "-" + $0.lowercased().replacingOccurrences(of: " ", with: "-") } ?? ""

        return ScratchPattern(
            id: "baby-scratch-\(Int(bpm))\(idSuffix)",
            name: "Baby Scratch (\(Int(bpm)) BPM)\(suffix)",
            bpm: bpm,
            bars: bars + leadInBars,
            strokes: strokes,
            beatLoopAsset: nil,
            defaultSampleAsset: "scratch-sentence",
            nominalStrokeDisplacement: nominalStrokeDisplacement
        )
    }
}
