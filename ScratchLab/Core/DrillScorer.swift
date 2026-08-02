import Foundation

enum TargetStrokeStatus: Equatable {
    case upcoming
    case hit(score: Double)
    case missed
}

/// Builds on PatternMatcher for live practice: a target with no matching
/// performed stroke isn't a "miss" until its timing window has actually
/// closed — before that it's just not due yet.
enum DrillScorer {
    static func statuses(pattern: ScratchPattern, performed: [ScratchStroke], elapsedTime: TimeInterval) -> [TargetStrokeStatus] {
        let beatDuration = DrillTimeline.beatDuration(bpm: pattern.bpm)
        let result = PatternMatcher.match(pattern: pattern, performed: performed)

        return pattern.strokes.indices.map { index in
            let score = result.strokeScores[index]
            if score.matched {
                return .hit(score: score.score)
            }

            let target = pattern.strokes[index]
            let targetTime = target.beatPosition * beatDuration
            let toleranceSeconds = target.timingToleranceMs / 1000.0
            let windowCloses = targetTime + toleranceSeconds * 3
            return elapsedTime > windowCloses ? .missed : .upcoming
        }
    }
}
