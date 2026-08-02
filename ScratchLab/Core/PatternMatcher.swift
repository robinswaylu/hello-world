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
///
/// Among correct-direction strokes, two independent things are graded on
/// the same rhythm-game-style banded scale (perfect/great/good/poor), and
/// the *worse* of the two wins:
/// - Timing: how close the stroke's start is to the target's moment, as a
///   fraction of that target's own timing tolerance.
/// - Amplitude: how close the stroke's peak velocity comes to the target's
///   reference velocity (33⅓ RPM-equivalent - the same height the practice
///   chart's target marker is drawn at), as a fraction of a fixed tolerance.
/// A stroke has to land both on time *and* at the right intensity for a
/// true Perfect - nailing one while badly missing the other caps the grade
/// at whatever the missed one alone would earn, same as a wrong direction
/// caps it regardless of timing. This is what makes "the line's peak
/// visually reaches the target marker" mean the same thing as "this stroke
/// graded well" - before, the marker's height didn't affect grading at all.
enum PatternMatcher {
    enum Grading {
        static let perfectRatio = 0.15
        static let greatRatio = 0.4
        static let goodRatio = 1.0
        // How far peak velocity can drift from the reference before it's
        // as bad as being all the way out at goodRatio on the timing
        // scale - i.e. amplitudeRatio 1.0 means "50% off target".
        static let amplitudeTolerance = 0.5
    }

    private static let referenceVelocity = BaselineEstimator.angularVelocity(forRPM: BaselineEstimator.rpm33)

    static func match(pattern: ScratchPattern, performed: [ScratchStroke]) -> MatchResult {
        let beatDuration = 60.0 / pattern.bpm
        var usedPerformedIndices = Set<Int>()
        var scores: [StrokeScore] = []
        scores.reserveCapacity(pattern.strokes.count)

        for (targetIndex, target) in pattern.strokes.enumerated() {
            let targetTime = target.beatPosition * beatDuration
            let toleranceSeconds = target.timingToleranceMs / 1000.0

            // Prefer a stroke going the way this target actually asks for,
            // and only fall back to the nearest stroke of any direction
            // when there's no correctly-directed one in range at all.
            //
            // Nearest-by-time alone is fragile in exactly the situation
            // these drills create. Targets alternate forward/back, and the
            // natural wind-up flick before a stroke - plus any gyro noise
            // that crosses the segmenter's start threshold - registers as
            // its own short stroke in the *opposite* direction, landing
            // slightly closer to the target than the real stroke does.
            // Direction-blind matching hands the target that blip, so a
            // stroke the player definitely performed correctly gets
            // reported as a direction failure.
            //
            // Falling back to the nearest stroke of any direction keeps a
            // genuinely wrong-direction performance honest: if nothing
            // correctly-directed is in range, the wrong-direction stroke
            // is still matched and still capped at .poor by `grade`.
            //
            // Manual scan rather than enumerated().filter().min() - this
            // runs per target, so avoiding an intermediate array
            // allocation on every call matters when it's called often.
            let matchWindow = toleranceSeconds * 3
            var bestIndex: Int?
            var bestDistance = Double.greatestFiniteMagnitude
            var bestDirectedIndex: Int?
            var bestDirectedDistance = Double.greatestFiniteMagnitude

            for (performedIndex, stroke) in performed.enumerated() where !usedPerformedIndices.contains(performedIndex) {
                let distance = abs(stroke.startTime - targetTime)
                guard distance <= matchWindow else { continue }

                if distance < bestDistance {
                    bestDistance = distance
                    bestIndex = performedIndex
                }
                if stroke.direction == target.direction, distance < bestDirectedDistance {
                    bestDirectedDistance = distance
                    bestDirectedIndex = performedIndex
                }
            }

            guard let performedIndex = bestDirectedIndex ?? bestIndex else {
                scores.append(StrokeScore(targetIndex: targetIndex, matched: false, timingErrorMs: nil, directionCorrect: false, displacementOk: false, grade: .missed, score: 0))
                continue
            }
            usedPerformedIndices.insert(performedIndex)
            let stroke = performed[performedIndex]

            let timingErrorMs = (stroke.startTime - targetTime) * 1000.0
            let timingRatio = abs(timingErrorMs) / target.timingToleranceMs
            let amplitudeRatio = abs(stroke.peakVelocity / referenceVelocity - 1.0) / Grading.amplitudeTolerance
            let directionCorrect = stroke.direction == target.direction

            // Not currently scored (no built-in drill constrains it), but
            // kept for drills that do specify a displacement range.
            let displacementOk: Bool
            if let range = target.relativeDisplacement {
                displacementOk = range.contains(abs(stroke.displacement))
            } else {
                displacementOk = true
            }

            let (grade, score) = Self.grade(timingRatio: timingRatio, amplitudeRatio: amplitudeRatio, directionCorrect: directionCorrect)
            scores.append(StrokeScore(targetIndex: targetIndex, matched: true, timingErrorMs: timingErrorMs, directionCorrect: directionCorrect, displacementOk: displacementOk, grade: grade, score: score))
        }

        let overall = scores.isEmpty ? 0 : scores.map(\.score).reduce(0, +) / Double(scores.count)
        return MatchResult(strokeScores: scores, overallScore: overall)
    }

    private static func grade(timingRatio: Double, amplitudeRatio: Double, directionCorrect: Bool) -> (StrokeGrade, Double) {
        guard directionCorrect else {
            // Wrong direction: small consolation credit at best, decaying
            // to 0 as timing gets worse too. Amplitude doesn't matter here
            // - it's the wrong move regardless of how well-powered it was.
            let score = max(0, 20 * (1 - min(timingRatio, 1)))
            return (.poor, score.rounded())
        }

        let (timingGrade, timingScore) = bandedGrade(for: timingRatio)
        let (amplitudeGrade, amplitudeScore) = bandedGrade(for: amplitudeRatio)
        let grade = worseGrade(timingGrade, amplitudeGrade)
        let score = min(timingScore, amplitudeScore)
        return (grade, score.rounded())
    }

    /// The shared perfect/great/good/poor banding, parameterized on
    /// whatever ratio-of-tolerance is being judged - timing and amplitude
    /// both use this same shape, just against their own ratios.
    private static func bandedGrade(for ratio: Double) -> (StrokeGrade, Double) {
        if ratio <= Grading.perfectRatio {
            return (.perfect, 100)
        } else if ratio <= Grading.greatRatio {
            let t = (ratio - Grading.perfectRatio) / (Grading.greatRatio - Grading.perfectRatio)
            return (.great, 100 - t * 15)
        } else if ratio <= Grading.goodRatio {
            let t = (ratio - Grading.greatRatio) / (Grading.goodRatio - Grading.greatRatio)
            return (.good, 85 - t * 35)
        } else {
            let t = min((ratio - Grading.goodRatio) / 2.0, 1.0)
            return (.poor, 50 * (1 - t))
        }
    }

    private static let gradeRank: [StrokeGrade: Int] = [.perfect: 4, .great: 3, .good: 2, .poor: 1, .missed: 0]

    private static func worseGrade(_ a: StrokeGrade, _ b: StrokeGrade) -> StrokeGrade {
        gradeRank[a]! <= gradeRank[b]! ? a : b
    }
}
