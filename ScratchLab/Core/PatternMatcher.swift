import Foundation

/// A Guitar-Hero-style judgement for one stroke. `perfect` is a real,
/// reachable 100 — not just "close enough".
enum StrokeGrade: String, Equatable {
    case perfect
    case great
    case good
    case poor
    case missed
}

struct StrokeScore {
    let targetIndex: Int
    let matched: Bool
    let timingErrorMs: Double?
    let directionCorrect: Bool
    let displacementOk: Bool
    let grade: StrokeGrade
    let score: Double // 0-100
}

struct MatchResult {
    let strokeScores: [StrokeScore]
    let overallScore: Double // 0-100
}

/// Scores a performed sequence of strokes against a target ScratchPattern.
/// A target stroke with no plausible match (nothing performed within 3x its
/// timing tolerance) is `.missed` and scores 0.
///
/// Direction is treated as a gate, not a bonus: playing the wrong direction
/// is a fundamentally different move, not an imprecise version of the right
/// one, so it caps the grade at `.poor` regardless of how well-timed it was.
/// Among correct-direction strokes, timing accuracy (as a fraction of the
/// stroke's own tolerance) determines perfect/great/good/poor — modeled on
/// rhythm-game judgement windows rather than a single linear scale, so a
/// true 100 is only awarded within a tight timing band.
enum PatternMatcher {
    enum Grading {
        static let perfectRatio = 0.15
        static let greatRatio = 0.4
        static let goodRatio = 1.0
    }

    static func match(pattern: ScratchPattern, performed: [ScratchStroke]) -> MatchResult {
        let beatDuration = 60.0 / pattern.bpm
        var usedPerformedIndices = Set<Int>()
        var scores: [StrokeScore] = []

        for (targetIndex, target) in pattern.strokes.enumerated() {
            let targetTime = target.beatPosition * beatDuration
            let toleranceSeconds = target.timingToleranceMs / 1000.0

            let candidate = performed.enumerated()
                .filter { !usedPerformedIndices.contains($0.offset) }
                .min { abs($0.element.startTime - targetTime) < abs($1.element.startTime - targetTime) }

            guard let (performedIndex, stroke) = candidate,
                  abs(stroke.startTime - targetTime) <= toleranceSeconds * 3 else {
                scores.append(StrokeScore(targetIndex: targetIndex, matched: false, timingErrorMs: nil, directionCorrect: false, displacementOk: false, grade: .missed, score: 0))
                continue
            }
            usedPerformedIndices.insert(performedIndex)

            let timingErrorMs = (stroke.startTime - targetTime) * 1000.0
            let timingRatio = abs(timingErrorMs) / target.timingToleranceMs
            let directionCorrect = stroke.direction == target.direction

            // Not currently scored (no built-in drill constrains it), but
            // kept for drills that do specify a displacement range.
            let displacementOk: Bool
            if let range = target.relativeDisplacement {
                displacementOk = range.contains(abs(stroke.displacement))
            } else {
                displacementOk = true
            }

            let (grade, score) = Self.grade(timingRatio: timingRatio, directionCorrect: directionCorrect)
            scores.append(StrokeScore(targetIndex: targetIndex, matched: true, timingErrorMs: timingErrorMs, directionCorrect: directionCorrect, displacementOk: displacementOk, grade: grade, score: score))
        }

        let overall = scores.isEmpty ? 0 : scores.map(\.score).reduce(0, +) / Double(scores.count)
        return MatchResult(strokeScores: scores, overallScore: overall)
    }

    private static func grade(timingRatio: Double, directionCorrect: Bool) -> (StrokeGrade, Double) {
        guard directionCorrect else {
            // Wrong direction: small consolation credit at best, decaying
            // to 0 as timing gets worse too.
            let score = max(0, 20 * (1 - min(timingRatio, 1)))
            return (.poor, score.rounded())
        }

        if timingRatio <= Grading.perfectRatio {
            return (.perfect, 100)
        } else if timingRatio <= Grading.greatRatio {
            let t = (timingRatio - Grading.perfectRatio) / (Grading.greatRatio - Grading.perfectRatio)
            return (.great, (100 - t * 15).rounded())
        } else if timingRatio <= Grading.goodRatio {
            let t = (timingRatio - Grading.greatRatio) / (Grading.goodRatio - Grading.greatRatio)
            return (.good, (85 - t * 35).rounded())
        } else {
            let t = min((timingRatio - Grading.goodRatio) / 2.0, 1.0)
            return (.poor, (50 * (1 - t)).rounded())
        }
    }
}
