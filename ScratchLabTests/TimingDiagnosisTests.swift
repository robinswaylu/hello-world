import XCTest
@testable import ScratchLab

final class TimingDiagnosisTests: XCTestCase {
    private let pattern = BuiltInDrills.babyScratchMedium // 90 BPM, eighths

    private var spacing: TimeInterval {
        PerfectRunCurve.gapBeats(for: pattern) * DrillTimeline.beatDuration(bpm: pattern.bpm)
    }

    private var targetPeak: Double {
        PerfectRunCurve.targetPeakVelocity(for: pattern)
    }

    /// Builds a run of strokes at `period` seconds apart, starting `offset`
    /// from the first target, alternating direction like the drill does.
    private func run(period: TimeInterval, offset: TimeInterval = 0, jitter: [TimeInterval] = [], count: Int? = nil) -> [ScratchStroke] {
        let total = count ?? pattern.strokes.count
        let firstTarget = pattern.strokes[0].beatPosition * DrillTimeline.beatDuration(bpm: pattern.bpm)
        return (0..<total).map { i in
            let wobble: TimeInterval = jitter.isEmpty ? 0 : jitter[i % jitter.count]
            let peak = firstTarget + offset + Double(i) * period + wobble
            return ScratchStroke(
                startTime: peak - 0.05,
                endTime: peak + 0.05,
                direction: i % 2 == 0 ? .forward : .back,
                peakVelocity: targetPeak,
                displacement: 0.5,
                peakTime: peak
            )
        }
    }

    private func diagnose(_ strokes: [ScratchStroke]) -> TimingDiagnosis {
        let result = PatternMatcher.match(pattern: pattern, performed: strokes)
        return TimingDiagnosis.analyze(pattern: pattern, strokes: strokes, result: result)
    }

    func testDetectsRushingAndReportsTheTempoActuallyPlayed() {
        // The real reported case: steady strokes, but ~274ms apart against
        // a 333ms grid - 90 BPM played at roughly 109.
        let diagnosis = diagnose(run(period: 0.2743))

        guard case .rushing(let bpm, let percent) = diagnosis.headline else {
            return XCTFail("expected rushing, got \(diagnosis.headline)")
        }
        XCTAssertEqual(bpm, 109, accuracy: 1.5)
        XCTAssertEqual(percent, 21.5, accuracy: 1.5)
    }

    func testRushingIsReportedEvenThoughPerStrokeErrorsWrap() {
        // The reason this measures the player's own intervals instead of
        // the matched per-target errors: those errors drift, then jump
        // when the matcher re-aligns onto a later stroke. Whatever the
        // matcher did, the diagnosis must still see a steady fast tempo.
        let strokes = run(period: 0.2743)
        let errors = PatternMatcher.match(pattern: pattern, performed: strokes)
            .strokeScores.compactMap(\.timingErrorMs)
        let jumped = zip(errors, errors.dropFirst()).contains { abs($1 - $0) > 200 }
        XCTAssertTrue(jumped, "test setup expected the matched errors to wrap")

        guard case .rushing = diagnose(strokes).headline else {
            return XCTFail("wrapped per-target errors must not defeat the tempo estimate")
        }
    }

    func testDetectsDragging() {
        let diagnosis = diagnose(run(period: spacing * 1.2))
        guard case .dragging(let bpm, let percent) = diagnosis.headline else {
            return XCTFail("expected dragging, got \(diagnosis.headline)")
        }
        XCTAssertLessThan(bpm, pattern.bpm)
        XCTAssertLessThan(percent, 0)
    }

    func testRightTempoButUnevenSpacingIsReportedAsUneven() {
        // Average period is correct; individual gaps swing well past the
        // jitter threshold. Distinguishing this from a tempo error is the
        // whole point - the two need opposite fixes.
        let diagnosis = diagnose(run(period: spacing, jitter: [0, 0.09, -0.02, 0.07, -0.08]))
        guard case .uneven(let jitterMs) = diagnosis.headline else {
            return XCTFail("expected uneven, got \(diagnosis.headline)")
        }
        XCTAssertGreaterThan(jitterMs, spacing * 1000 * 0.12)
        XCTAssertEqual(diagnosis.tempoErrorPercent ?? 99, 0, accuracy: 5)
    }

    func testSteadyCorrectTempoButConsistentlyLateIsReportedAsOffset() {
        // Exactly what an uncompensated output latency looks like.
        let diagnosis = diagnose(run(period: spacing, offset: 0.06))
        guard case .offset(let ms) = diagnosis.headline else {
            return XCTFail("expected offset, got \(diagnosis.headline)")
        }
        XCTAssertEqual(ms, 60, accuracy: 15)
    }

    func testAPerfectRunReportsSolid() {
        XCTAssertEqual(diagnose(run(period: spacing)).headline, .solid)
    }

    func testTooFewStrokesRefusesToGuess() {
        XCTAssertEqual(diagnose(run(period: spacing, count: 4)).headline, .notEnoughData)
    }

    func testWindUpBlipsAreExcludedFromTheTempoEstimate() {
        // Interleaving tiny flicks between real strokes halves every
        // measured interval - left in, a correct run would read as
        // dramatically rushing.
        var strokes = run(period: spacing)
        let flicks: [ScratchStroke] = strokes.map { stroke in
            ScratchStroke(
                startTime: stroke.peakTime - 0.17,
                endTime: stroke.peakTime - 0.15,
                direction: stroke.direction == .forward ? .back : .forward,
                peakVelocity: targetPeak * 0.1, // well under the floor
                displacement: 0.02,
                peakTime: stroke.peakTime - 0.16
            )
        }
        strokes.append(contentsOf: flicks)

        XCTAssertEqual(diagnose(strokes).headline, .solid, "low-velocity flicks must not be treated as attempts")
    }
}
