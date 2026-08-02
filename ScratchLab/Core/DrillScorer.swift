import Foundation

enum TargetStrokeStatus: Equatable {
    case upcoming
    case hit(grade: StrokeGrade, score: Double)
    case missed
}

/// Builds on PatternMatcher for live practice: a target with no matching
/// performed stroke isn't a "miss" until its timing window has actually
/// closed — before that it's just not due yet.
enum DrillScorer {
    static func statuses(pattern: ScratchPattern, performed: [ScratchStroke], elapsedTime: TimeInterval) -> [TargetStrokeStatus] {
        let result = PatternMatcher.match(pattern: pattern, performed: performed)
        return pattern.strokes.indices.map { index in
            let score = result.strokeScores[index]
            if score.matched {
                return .hit(grade: score.grade, score: score.score)
            }
            return missedOrUpcoming(pattern: pattern, index: index, elapsedTime: elapsedTime)
        }
    }

    /// Live capture calls this every ~100Hz sample, but which strokes have
    /// been *performed* only changes a couple dozen times over a whole
    /// drill (when one starts or completes) - re-running the full
    /// PatternMatcher match on every sample regardless was the actual
    /// scoring-lag bug: allocating and re-matching all of a pattern's
    /// targets from scratch, over a hundred times a second, almost all of
    /// which produce an identical result to the previous sample.
    ///
    /// When nothing about the performed strokes changed since the last
    /// call, only the cheap upcoming -> missed time check needs to run.
    ///
    /// Either way, a target that has already resolved keeps the status it
    /// resolved to. That has to be enforced explicitly on the re-match
    /// path, because live matching runs against a rolling few-seconds
    /// window of strokes rather than the whole run: once the stroke that
    /// satisfied a target ages out of that window, a full re-match no
    /// longer finds anything for that target, and since its timing window
    /// closed long ago it would come back `.missed`. A dot graded Perfect
    /// would quietly turn red a few seconds later, on whatever stroke
    /// happened to trigger the next re-match.
    ///
    /// (Bounding the window is still right - a stale stroke genuinely
    /// can't match any *future* target. The flaw was that the re-match
    /// recomputes past targets too, not just upcoming ones.)
    static func statuses(previous: [TargetStrokeStatus], pattern: ScratchPattern, performed: [ScratchStroke], elapsedTime: TimeInterval, performedDidChange: Bool) -> [TargetStrokeStatus] {
        guard performedDidChange else {
            return previous.indices.map { index in
                guard previous[index] == .upcoming else { return previous[index] }
                return missedOrUpcoming(pattern: pattern, index: index, elapsedTime: elapsedTime)
            }
        }

        let rematched = statuses(pattern: pattern, performed: performed, elapsedTime: elapsedTime)
        return rematched.indices.map { index in
            let previousStatus = index < previous.count ? previous[index] : .upcoming
            guard previousStatus == .upcoming else { return previousStatus }
            return rematched[index]
        }
    }

    private static func missedOrUpcoming(pattern: ScratchPattern, index: Int, elapsedTime: TimeInterval) -> TargetStrokeStatus {
        let beatDuration = DrillTimeline.beatDuration(bpm: pattern.bpm)
        let target = pattern.strokes[index]
        let targetTime = target.beatPosition * beatDuration
        let toleranceSeconds = target.timingToleranceMs / 1000.0
        let windowCloses = targetTime + toleranceSeconds * 3
        return elapsedTime > windowCloses ? .missed : .upcoming
    }
}
