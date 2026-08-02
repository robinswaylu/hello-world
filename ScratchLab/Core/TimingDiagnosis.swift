import Foundation

/// Turns a finished run into one actionable sentence about *why* the score
/// came out how it did.
///
/// A column of per-stroke millisecond errors doesn't distinguish the two
/// problems that matter most, and they need opposite fixes: playing
/// steadily at the wrong tempo looks, stroke by stroke, a lot like playing
/// erratically at the right one. Separating them is the point of this
/// type.
///
/// Three independent axes, because no single number covers it:
/// - **Tempo**: are the strokes the right distance apart?
/// - **Consistency**: are they *evenly* spaced, whatever the tempo?
/// - **Alignment**: is the whole run sitting on the grid, or offset from it?
///
/// Deliberately measured from the player's own stroke times rather than
/// from the matched per-target timing errors. Those errors wrap: when a
/// player drifts far enough, the matcher re-aligns onto a later stroke and
/// the error jumps by a discontinuity whose size depends on the player's
/// own period - the very quantity being estimated. Consecutive differences
/// of raw peak times have no such artefact.
struct TimingDiagnosis: Equatable {
    enum Headline: Equatable {
        /// Too few clean strokes to say anything honest.
        case notEnoughData
        /// Steady enough, on the grid, at the right tempo.
        case solid
        /// Strokes are too close together - playing faster than the drill.
        case rushing(effectiveBPM: Double, percent: Double)
        /// Strokes are too far apart - playing slower than the drill.
        case dragging(effectiveBPM: Double, percent: Double)
        /// Right tempo on average, but the spacing wanders.
        case uneven(jitterMs: Double)
        /// Right tempo and steady, but consistently off the beat.
        case offset(ms: Double)
    }

    let headline: Headline
    /// The tempo actually played, in BPM. `nil` when there wasn't enough data.
    let effectiveBPM: Double?
    /// Positive = rushing, negative = dragging.
    let tempoErrorPercent: Double?
    /// Median absolute deviation of the gaps between strokes. Low means
    /// metronomic, whatever the tempo.
    let jitterMs: Double?
    /// Median timing error across matched targets. Positive = late.
    let alignmentMs: Double?

    // MARK: - Thresholds

    private enum Threshold {
        /// Below this the tempo is close enough not to be the story.
        static let tempoPercent = 5.0
        /// Jitter as a fraction of the drill's own stroke spacing, so a
        /// fast drill isn't judged against a slow drill's absolute ms.
        static let jitterFractionOfSpacing = 0.12
        /// Alignment as a fraction of stroke tolerance - roughly the point
        /// where a stroke stops being Great on timing alone.
        static let alignmentFractionOfTolerance = 0.4
        /// Fewer clean strokes than this and any fit is noise.
        static let minimumStrokes = 8
        /// Strokes peaking below this fraction of the drill's target
        /// velocity are wind-up flicks and sensor noise, not attempts -
        /// leaving them in corrupts the interval sequence.
        static let strokeVelocityFloor = 0.25
    }

    static func analyze(pattern: ScratchPattern, strokes: [ScratchStroke], result: MatchResult) -> TimingDiagnosis {
        let beatDuration = DrillTimeline.beatDuration(bpm: pattern.bpm)
        let spacingMs = PerfectRunCurve.gapBeats(for: pattern) * beatDuration * 1000.0
        let targetPeak = PerfectRunCurve.targetPeakVelocity(for: pattern)
        let floor = targetPeak * Threshold.strokeVelocityFloor

        let attempts = strokes
            .filter { $0.peakVelocity >= floor }
            .map(\.peakTime)
            .sorted()

        guard attempts.count >= Threshold.minimumStrokes, spacingMs > 0 else {
            return TimingDiagnosis(headline: .notEnoughData, effectiveBPM: nil, tempoErrorPercent: nil, jitterMs: nil, alignmentMs: nil)
        }

        var intervals: [Double] = []
        intervals.reserveCapacity(attempts.count - 1)
        for index in 1..<attempts.count {
            intervals.append((attempts[index] - attempts[index - 1]) * 1000.0)
        }

        // Median, not mean: one long pause mid-run shouldn't drag the
        // estimate of how fast everything else was played.
        guard let period = median(intervals), period > 0 else {
            return TimingDiagnosis(headline: .notEnoughData, effectiveBPM: nil, tempoErrorPercent: nil, jitterMs: nil, alignmentMs: nil)
        }
        let jitter = median(intervals.map { abs($0 - period) }) ?? 0

        let tempoRatio = spacingMs / period
        let tempoErrorPercent = (tempoRatio - 1) * 100
        let effectiveBPM = pattern.bpm * tempoRatio

        let matchedErrors = result.strokeScores.compactMap(\.timingErrorMs)
        let alignment = median(matchedErrors)

        let headline = self.headline(
            tempoErrorPercent: tempoErrorPercent,
            effectiveBPM: effectiveBPM,
            jitter: jitter,
            alignment: alignment,
            spacingMs: spacingMs,
            pattern: pattern
        )

        return TimingDiagnosis(
            headline: headline,
            effectiveBPM: effectiveBPM,
            tempoErrorPercent: tempoErrorPercent,
            jitterMs: jitter,
            alignmentMs: alignment
        )
    }

    /// Worst axis wins. Tempo first: a steady run at the wrong speed will
    /// also show a large alignment error as the drift accumulates, and
    /// reporting that instead would send the player chasing the wrong fix.
    private static func headline(
        tempoErrorPercent: Double,
        effectiveBPM: Double,
        jitter: Double,
        alignment: Double?,
        spacingMs: Double,
        pattern: ScratchPattern
    ) -> Headline {
        if tempoErrorPercent >= Threshold.tempoPercent {
            return .rushing(effectiveBPM: effectiveBPM, percent: tempoErrorPercent)
        }
        if tempoErrorPercent <= -Threshold.tempoPercent {
            return .dragging(effectiveBPM: effectiveBPM, percent: tempoErrorPercent)
        }
        if jitter > spacingMs * Threshold.jitterFractionOfSpacing {
            return .uneven(jitterMs: jitter)
        }
        let tolerance = typicalToleranceMs(for: pattern)
        if let alignment, abs(alignment) > tolerance * Threshold.alignmentFractionOfTolerance {
            return .offset(ms: alignment)
        }
        return .solid
    }

    /// The tolerance most strokes in the drill use. Skips the first, which
    /// is deliberately given a wider window and would skew a mean.
    private static func typicalToleranceMs(for pattern: ScratchPattern) -> Double {
        median(pattern.strokes.dropFirst().map(\.timingToleranceMs)) ?? 100
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
