import Foundation

enum BuiltInDrills {
    static let babyScratchSlow = makeBabyScratch(bpm: 80, bars: 4)
    static let babyScratchFast = makeBabyScratch(bpm: 120, bars: 4)
    static let drag = makeDrag()
    static let scribble = makeScribble()
    static let releaseTiming = makeReleaseTiming()
    static let tempoLadder = makeTempoLadder()

    static let all: [ScratchPattern] = [
        babyScratchSlow, babyScratchFast, drag, scribble, releaseTiming, tempoLadder,
    ]

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

    /// One long push, one long pull per bar: a slow, sustained drag rather
    /// than a quick flick, with a wide displacement tolerance to match.
    private static func makeDrag(bpm: Double = 70, bars: Int = 4) -> ScratchPattern {
        var strokes: [TargetStroke] = []
        for bar in 0..<bars {
            let barStart = Double(bar) * DrillTimeline.beatsPerBar
            strokes.append(TargetStroke(beatPosition: barStart, direction: .forward, relativeDisplacement: 0.5...2.0, timingToleranceMs: 150))
            strokes.append(TargetStroke(beatPosition: barStart + 2, direction: .back, relativeDisplacement: 0.5...2.0, timingToleranceMs: 150))
        }
        return ScratchPattern(id: "drag", name: "Drag", bpm: bpm, bars: bars, strokes: strokes, beatLoopAsset: nil, defaultSampleAsset: "scratch-sentence")
    }

    /// Baby scratch's faster, tighter cousin: sixteenth notes instead of
    /// eighths, with a tighter timing tolerance to match the higher speed.
    private static func makeScribble(bpm: Double = 100, bars: Int = 4) -> ScratchPattern {
        let sixteenthsPerBar = 16
        let totalSixteenths = bars * sixteenthsPerBar
        let strokes = (0..<totalSixteenths).map { i in
            TargetStroke(beatPosition: Double(i) * 0.25, direction: i % 2 == 0 ? .forward : .back, relativeDisplacement: nil, timingToleranceMs: 60)
        }
        return ScratchPattern(id: "scribble", name: "Scribble", bpm: bpm, bars: bars, strokes: strokes, beatLoopAsset: nil, defaultSampleAsset: "scratch-sentence")
    }

    /// Push on the beat, release right before the next one (the "and-a")
    /// instead of the halfway point — a precision drill, hence the much
    /// tighter 40ms timing tolerance rather than a speed drill.
    private static func makeReleaseTiming(bpm: Double = 90, bars: Int = 4) -> ScratchPattern {
        var strokes: [TargetStroke] = []
        for bar in 0..<bars {
            let barStart = Double(bar) * DrillTimeline.beatsPerBar
            for beat in 0..<4 {
                let beatPosition = barStart + Double(beat)
                strokes.append(TargetStroke(beatPosition: beatPosition, direction: .forward, relativeDisplacement: nil, timingToleranceMs: 40))
                strokes.append(TargetStroke(beatPosition: beatPosition + 0.75, direction: .back, relativeDisplacement: nil, timingToleranceMs: 40))
            }
        }
        return ScratchPattern(id: "release-timing", name: "Release Timing", bpm: bpm, bars: bars, strokes: strokes, beatLoopAsset: nil, defaultSampleAsset: "scratch-sentence")
    }

    /// The metronome stays flat the whole way through; what changes is how
    /// close together the strokes are, section by section, so the felt
    /// tempo ramps up against a steady click — a real scratch-practice
    /// technique, not something a single fixed `bpm` normally expresses.
    /// TargetStroke.beatPosition only ever matters as
    /// `beatPosition * DrillTimeline.beatDuration(bpm)`, so a non-uniform
    /// spacing of those positions is exactly how "speeding up" is encoded
    /// without changing the architecture to support a variable tempo.
    private static func makeTempoLadder(referenceBPM: Double = 90) -> ScratchPattern {
        let strokesPerSection = 8
        let sectionSpeedMultipliers = [1.0, 1.25, 1.5, 1.75]

        var strokes: [TargetStroke] = []
        var cursor = 0.0
        for multiplier in sectionSpeedMultipliers {
            let strokeSpacing = 0.5 / multiplier
            for i in 0..<strokesPerSection {
                strokes.append(TargetStroke(beatPosition: cursor, direction: i % 2 == 0 ? .forward : .back, relativeDisplacement: nil, timingToleranceMs: 100))
                cursor += strokeSpacing
            }
        }

        let bars = Int((cursor / DrillTimeline.beatsPerBar).rounded(.up))
        return ScratchPattern(id: "tempo-ladder", name: "Tempo Ladder", bpm: referenceBPM, bars: bars, strokes: strokes, beatLoopAsset: nil, defaultSampleAsset: "scratch-sentence")
    }
}
