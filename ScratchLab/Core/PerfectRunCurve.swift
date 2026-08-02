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

    /// Hump width for the final stroke, which has no following stroke to
    /// bound it. Every built-in drill is on eighth notes, so half a beat
    /// matches the spacing of every other stroke in the pattern.
    private static let trailingStrokeBeats = 0.5

    static func points(for pattern: ScratchPattern) -> [Point] {
        let strokes = pattern.strokes
        guard !strokes.isEmpty else { return [] }

        var points: [Point] = []
        points.reserveCapacity(strokes.count * (samplesPerStroke + 1))

        for (index, stroke) in strokes.enumerated() {
            let start: Double = stroke.beatPosition
            let end: Double
            if index + 1 < strokes.count {
                end = strokes[index + 1].beatPosition
            } else {
                end = start + trailingStrokeBeats
            }

            let sign: Double = stroke.direction == .forward ? 1 : -1
            let span: Double = end - start

            // Half-sine hump (0 -> peak -> 0) rather than a flat hold: a
            // real stroke accelerates and decelerates, and the peak is
            // what amplitude grading samples.
            for step in 0...samplesPerStroke {
                let t: Double = Double(step) / Double(samplesPerStroke)
                let beat: Double = start + span * t
                let value: Double = sign * sin(Double.pi * t)
                points.append(Point(beat: beat, normalizedVelocity: value))
            }
        }

        return points
    }
}
