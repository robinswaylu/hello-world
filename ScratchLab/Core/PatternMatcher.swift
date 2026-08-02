import Foundation

struct StrokeScore {
    let targetIndex: Int
    let matched: Bool
    let timingErrorMs: Double?
    let directionCorrect: Bool
    let displacementOk: Bool
    let score: Double // 0-100
}

struct MatchResult {
    let strokeScores: [StrokeScore]
    let overallScore: Double // 0-100
}

/// Scores a performed sequence of strokes against a target ScratchPattern:
/// timing against the beat grid, direction, and displacement consistency.
/// A target stroke with no plausible match (nothing performed within 3x its
/// timing tolerance) scores 0 and is left unmatched.
enum PatternMatcher {
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
                scores.append(StrokeScore(targetIndex: targetIndex, matched: false, timingErrorMs: nil, directionCorrect: false, displacementOk: false, score: 0))
                continue
            }
            usedPerformedIndices.insert(performedIndex)

            let timingErrorMs = (stroke.startTime - targetTime) * 1000.0
            let timingScore = max(0, 1 - abs(timingErrorMs) / target.timingToleranceMs)
            let directionCorrect = stroke.direction == target.direction

            let displacementOk: Bool
            if let range = target.relativeDisplacement {
                displacementOk = range.contains(abs(stroke.displacement))
            } else {
                displacementOk = true
            }

            let score = timingScore * 60 + (directionCorrect ? 30 : 0) + (displacementOk ? 10 : 0)
            scores.append(StrokeScore(targetIndex: targetIndex, matched: true, timingErrorMs: timingErrorMs, directionCorrect: directionCorrect, displacementOk: displacementOk, score: score))
        }

        let overall = scores.isEmpty ? 0 : scores.map(\.score).reduce(0, +) / Double(scores.count)
        return MatchResult(strokeScores: scores, overallScore: overall)
    }
}
