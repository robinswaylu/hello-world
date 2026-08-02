import Foundation

/// The reference "perfect run" for a drill: every target stroke played at
/// exactly its beat, in the right direction, peaking at exactly the
/// velocity that amplitude grading measures against - so each hump's tip
/// touches its target dot on the practice chart.
///
/// Values are normalized against the 33⅓ RPM reference velocity, the same
/// normalization the practice chart's y-axis and `PatternMatcher`'s
/// amplitude grading both use, so `1.0` means "exactly on-target
/// amplitude, forward" and lines up with a forward dot, `-1.0` with a
/// back dot.
///
/// This is a shape to aim at, not a synthetic input that would literally
/// score 100 if fed through the segmenter: `GestureSegmenter` marks a
/// stroke as starting when velocity crosses its start threshold, which
/// happens a few milliseconds after each hump leaves zero. What it does
/// show, at a glance, is the three things grading actually looks at -
/// each stroke's timing, direction, and peak amplitude.
enum PerfectRunCurve {
    struct Point {
        let beat: Double
        /// Velocity as a multiple of the 33⅓ reference (±1 = on target).
        let normalizedVelocity: Double
    }

    /// Points per stroke hump. Each hump is only a few points wide on
    /// screen (a whole drill spans the chart's width), so this is about
    /// keeping the arc from looking angular vertically - well past that
    /// it's just extra path segments to stroke every frame.
    static let samplesPerStroke = 8

    /// Fallback stroke spacing when a pattern has only one target. Every
    /// built-in drill is on eighth notes.
    private static let defaultGapBeats = 0.5

    /// Nominal platter rotation for a single stroke, in radians - roughly
    /// 0.18 of a revolution, about 63°.
    ///
    /// This is what sets the amplitude target, and it's the one number
    /// here most worth tuning against real playing. It replaced using the
    /// 33⅓ RPM playback reference as the target, which was a category
    /// error: 33⅓ is how fast the record turns during *playback* (the
    /// right unit for the audio engine's rate), but a scratch is
    /// deliberately much faster than that. Real captured strokes peak
    /// around 6.5-14 rad/s against a 3.49 rad/s playback reference, so
    /// every genuine stroke was landing 2-4x "over" target and grading
    /// Poor on amplitude no matter how well it was played.
    static let nominalStrokeDisplacement: Double = 1.1

    /// Peak angular velocity (rad/s) a stroke in this drill should reach:
    /// the peak of a half-sine that covers `nominalStrokeDisplacement`
    /// over one stroke slot. Derived from the drill's own tempo, so a
    /// faster drill asks for faster strokes to cover the same distance in
    /// less time, rather than one flat number across every tempo.
    static func targetPeakVelocity(for pattern: ScratchPattern) -> Double {
        let beatDuration = DrillTimeline.beatDuration(bpm: pattern.bpm)
        let strokeDuration = gapBeats(for: pattern) * beatDuration
        guard strokeDuration > 0 else { return 0 }
        return nominalStrokeDisplacement * Double.pi / (2 * strokeDuration)
    }

    /// Spacing between consecutive targets, in beats.
    static func gapBeats(for pattern: ScratchPattern) -> Double {
        let positions: [Double] = pattern.strokes.map(\.beatPosition)
        guard positions.count > 1 else { return defaultGapBeats }

        var smallest = Double.greatestFiniteMagnitude
        for index in 1..<positions.count {
            let gap: Double = positions[index] - positions[index - 1]
            if gap > 0, gap < smallest {
                smallest = gap
            }
        }
        return smallest < .greatestFiniteMagnitude ? smallest : defaultGapBeats
    }

    static func points(for pattern: ScratchPattern) -> [Point] {
        let strokes = pattern.strokes
        guard !strokes.isEmpty else { return [] }

        // Each hump is *centred* on its target beat rather than starting
        // there, so the tip of the arc lands exactly on the target's dot.
        // That's the whole contract of this curve - the dot marks the
        // moment to be at full speed - and it's why `PatternMatcher`
        // grades timing on a stroke's peak rather than its start.
        let halfSpan: Double = gapBeats(for: pattern) / 2
        var points: [Point] = []
        points.reserveCapacity(strokes.count * (samplesPerStroke + 1))

        for stroke in strokes {
            let sign: Double = stroke.direction == .forward ? 1 : -1
            let start: Double = stroke.beatPosition - halfSpan

            // Half-sine hump (0 -> peak -> 0) rather than a flat hold: a
            // real stroke accelerates and decelerates, and the peak is
            // what amplitude grading samples.
            for step in 0...samplesPerStroke {
                let t: Double = Double(step) / Double(samplesPerStroke)
                let beat: Double = start + halfSpan * 2 * t
                let value: Double = sign * sin(Double.pi * t)
                points.append(Point(beat: beat, normalizedVelocity: value))
            }
        }

        return points
    }
}
