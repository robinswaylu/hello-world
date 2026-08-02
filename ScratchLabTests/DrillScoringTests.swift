import XCTest
@testable import ScratchLab

final class DrillTimelineTests: XCTestCase {
    func testBeatDurationAndTotalDuration() {
        XCTAssertEqual(DrillTimeline.beatDuration(bpm: 120), 0.5, accuracy: 0.0001)

        let pattern = ScratchPattern(id: "t", name: "t", bpm: 120, bars: 2, strokes: [], beatLoopAsset: nil, defaultSampleAsset: "x")
        XCTAssertEqual(DrillTimeline.totalDuration(pattern: pattern), 4.0, accuracy: 0.0001)
    }
}

final class DrillScorerTests: XCTestCase {
    private func singleTargetPattern() -> ScratchPattern {
        ScratchPattern(
            id: "t",
            name: "t",
            bpm: 120,
            bars: 1,
            strokes: [TargetStroke(beatPosition: 4, direction: .forward, relativeDisplacement: nil, timingToleranceMs: 80)],
            beatLoopAsset: nil,
            defaultSampleAsset: "x"
        )
    }

    func testUpcomingBeforeWindowCloses() {
        let pattern = singleTargetPattern()
        // target time = 4 * 0.5 = 2.0s; window closes at 2.0 + 0.08*3 = 2.24s
        let statuses = DrillScorer.statuses(pattern: pattern, performed: [], elapsedTime: 1.0)
        XCTAssertEqual(statuses, [.upcoming])
    }

    func testMissedAfterWindowCloses() {
        let pattern = singleTargetPattern()
        let statuses = DrillScorer.statuses(pattern: pattern, performed: [], elapsedTime: 3.0)
        XCTAssertEqual(statuses, [.missed])
    }

    /// The amplitude grading target for this pattern - tempo-derived, not
    /// the 33⅓ playback reference.
    private var targetPeak: Double {
        PerfectRunCurve.targetPeakVelocity(for: singleTargetPattern())
    }

    func testHitWhenMatched() {
        let pattern = singleTargetPattern()
        // Peak lands exactly on the target beat at exactly on-target
        // amplitude - both axes score Perfect, so the grade is Perfect.
        let stroke = ScratchStroke(startTime: 1.9, endTime: 2.1, direction: .forward, peakVelocity: targetPeak, displacement: 0.5, peakTime: 2.0)
        let statuses = DrillScorer.statuses(pattern: pattern, performed: [stroke], elapsedTime: 2.2)

        guard case .hit(let grade, let score) = statuses[0] else {
            return XCTFail("expected a hit, got \(statuses[0])")
        }
        XCTAssertEqual(grade, .perfect)
        XCTAssertEqual(score, 100, accuracy: 0.5)
    }

    func testTimingIsMeasuredFromThePeakNotTheStrokeStart() {
        let pattern = singleTargetPattern()
        // Starts a long way before the target but peaks right on it. Under
        // start-time grading this was badly early; the dot marks the
        // moment to be at full speed, so it's a Perfect.
        let stroke = ScratchStroke(startTime: 1.7, endTime: 2.3, direction: .forward, peakVelocity: targetPeak, displacement: 0.5, peakTime: 2.0)
        let statuses = DrillScorer.statuses(pattern: pattern, performed: [stroke], elapsedTime: 2.4)

        guard case .hit(let grade, _) = statuses[0] else {
            return XCTFail("expected a hit, got \(statuses[0])")
        }
        XCTAssertEqual(grade, .perfect)
    }

    func testWrongDirectionIsGradedPoorWithLowScore() {
        let pattern = singleTargetPattern()
        let stroke = ScratchStroke(startTime: 1.9, endTime: 2.1, direction: .back, peakVelocity: targetPeak, displacement: 0.5, peakTime: 2.0)
        let statuses = DrillScorer.statuses(pattern: pattern, performed: [stroke], elapsedTime: 2.2)

        guard case .hit(let grade, let score) = statuses[0] else {
            return XCTFail("expected a hit (matched but wrong direction), got \(statuses[0])")
        }
        // Wrong direction is capped at .poor even with perfect timing - it's
        // a different move, not an imprecise version of the right one.
        XCTAssertEqual(grade, .poor)
        XCTAssertEqual(score, 20, accuracy: 0.5)
    }

    func testPerfectTimingButWeakStrokeIsCappedByAmplitude() {
        let pattern = singleTargetPattern()
        // Timing is dead-on, but the stroke barely moved - a tenth of
        // target speed. Timing alone shouldn't earn a good grade for a
        // stroke that was never really performed.
        let stroke = ScratchStroke(startTime: 1.9, endTime: 2.1, direction: .forward, peakVelocity: targetPeak * 0.1, displacement: 0.5, peakTime: 2.0)
        let statuses = DrillScorer.statuses(pattern: pattern, performed: [stroke], elapsedTime: 2.2)

        guard case .hit(let grade, _) = statuses[0] else {
            return XCTFail("expected a hit, got \(statuses[0])")
        }
        XCTAssertEqual(grade, .poor)
    }

    func testARealisticScratchIsNoLongerPunishedOnAmplitude() {
        let pattern = singleTargetPattern()
        // Regression guard for the calibration bug: amplitude used to be
        // measured against the 33⅓ RPM *playback* reference (3.49 rad/s),
        // but real captured strokes peak around 6.5-14 rad/s. Every
        // genuine scratch therefore read as 2-4x over target and graded
        // Poor. A stroke at a realistic speed must grade well.
        let stroke = ScratchStroke(startTime: 1.9, endTime: 2.1, direction: .forward, peakVelocity: 7.0, displacement: 0.5, peakTime: 2.0)
        let statuses = DrillScorer.statuses(pattern: pattern, performed: [stroke], elapsedTime: 2.2)

        guard case .hit(let grade, _) = statuses[0] else {
            return XCTFail("expected a hit, got \(statuses[0])")
        }
        XCTAssertTrue(grade == .perfect || grade == .great, "a 7 rad/s stroke should grade well, got \(grade)")
    }

    func testWindUpBlipDoesNotStealTheTargetFromTheRealStroke() {
        let pattern = singleTargetPattern() // beat 4 @ 120bpm = 2.0s, .forward
        // A short backward wind-up flick peaking right on the target beat -
        // closer than the real stroke, but the wrong direction.
        // Direction-blind nearest-match would grade the blip and report a
        // direction failure for a stroke the player got right.
        let windUp = ScratchStroke(startTime: 1.95, endTime: 2.0, direction: .back, peakVelocity: targetPeak * 0.3, displacement: 0.05, peakTime: 2.0)
        let real = ScratchStroke(startTime: 2.0, endTime: 2.2, direction: .forward, peakVelocity: targetPeak, displacement: 0.5, peakTime: 2.05)

        let statuses = DrillScorer.statuses(pattern: pattern, performed: [windUp, real], elapsedTime: 2.3)
        guard case .hit(let grade, _) = statuses[0] else {
            return XCTFail("expected a hit, got \(statuses[0])")
        }
        XCTAssertNotEqual(grade, .poor, "the backward wind-up blip should not have been matched ahead of the real forward stroke")
    }

    func testWrongDirectionStillFailsWhenThereIsNoCorrectlyDirectedStroke() {
        let pattern = singleTargetPattern()
        // Only a backward stroke in range - the directional preference
        // must not quietly excuse a genuinely wrong-direction attempt.
        let onlyBackward = ScratchStroke(startTime: 1.9, endTime: 2.1, direction: .back, peakVelocity: targetPeak, displacement: 0.5, peakTime: 2.0)

        let statuses = DrillScorer.statuses(pattern: pattern, performed: [onlyBackward], elapsedTime: 2.3)
        guard case .hit(let grade, _) = statuses[0] else {
            return XCTFail("expected a hit, got \(statuses[0])")
        }
        XCTAssertEqual(grade, .poor)
    }

    func testAccurateAmplitudeButBadTimingIsCappedByTiming() {
        let pattern = singleTargetPattern()
        // Peak velocity is right on target, but peaks 150ms late - past
        // the widened Good band (1.6x the 80ms tolerance = 128ms) while
        // still inside the 3x-tolerance window that counts as a match at
        // all. Amplitude alone shouldn't rescue bad timing.
        let stroke = ScratchStroke(startTime: 2.05, endTime: 2.25, direction: .forward, peakVelocity: targetPeak, displacement: 0.5, peakTime: 2.15)
        let statuses = DrillScorer.statuses(pattern: pattern, performed: [stroke], elapsedTime: 2.3)

        guard case .hit(let grade, _) = statuses[0] else {
            return XCTFail("expected a hit, got \(statuses[0])")
        }
        XCTAssertEqual(grade, .poor)
    }
}

final class PerfectRunCurveTests: XCTestCase {
    private func twoStrokePattern() -> ScratchPattern {
        ScratchPattern(
            id: "t",
            name: "t",
            bpm: 120,
            bars: 1,
            strokes: [
                TargetStroke(beatPosition: 0, direction: .forward, relativeDisplacement: nil, timingToleranceMs: 100),
                TargetStroke(beatPosition: 0.5, direction: .back, relativeDisplacement: nil, timingToleranceMs: 100),
            ],
            beatLoopAsset: nil,
            defaultSampleAsset: "x"
        )
    }

    func testEachHumpPeaksExactlyOnItsTargetBeatInItsOwnDirection() {
        let points = PerfectRunCurve.points(for: twoStrokePattern())
        XCTAssertFalse(points.isEmpty)

        // Each hump is centred on its target, so the tip of the arc lands
        // exactly on that target's dot. This is the contract the practice
        // chart and peak-based timing grading are both built on: if the
        // peak drifted off the dot, "peak touches dot" would stop meaning
        // "scores Perfect".
        let atFirstTarget: [Double] = points.filter { abs($0.beat - 0) < 0.0001 }.map(\.normalizedVelocity)
        XCTAssertEqual(atFirstTarget.max() ?? 0, 1.0, accuracy: 0.001)

        let atSecondTarget: [Double] = points.filter { abs($0.beat - 0.5) < 0.0001 }.map(\.normalizedVelocity)
        XCTAssertEqual(atSecondTarget.min() ?? 0, -1.0, accuracy: 0.001)
    }

    func testTargetPeakVelocityIsTempoDerivedAndRealistic() {
        // Faster tempo means less time per stroke, so a stroke covering
        // the same platter distance has to move faster.
        let slow = PerfectRunCurve.targetPeakVelocity(for: pattern(bpm: 80))
        let fast = PerfectRunCurve.targetPeakVelocity(for: pattern(bpm: 120))
        XCTAssertGreaterThan(fast, slow)

        // And both must sit in the range real captured scratches actually
        // reach (~6.5-14 rad/s), not down at the 3.49 rad/s 33⅓ playback
        // reference that made every genuine stroke grade Poor.
        XCTAssertGreaterThan(slow, 3.5)
        XCTAssertLessThan(fast, 14.0)
    }

    private func pattern(bpm: Double) -> ScratchPattern {
        ScratchPattern(
            id: "t",
            name: "t",
            bpm: bpm,
            bars: 1,
            strokes: [
                TargetStroke(beatPosition: 0, direction: .forward, relativeDisplacement: nil, timingToleranceMs: 100),
                TargetStroke(beatPosition: 0.5, direction: .back, relativeDisplacement: nil, timingToleranceMs: 100),
            ],
            beatLoopAsset: nil,
            defaultSampleAsset: "x"
        )
    }

    func testCurveNeverOvershootsOnTargetAmplitude() {
        let points = PerfectRunCurve.points(for: twoStrokePattern())
        // Overshooting would draw the ghost above its own dots, which
        // would make the thing it's meant to demonstrate wrong.
        XCTAssertTrue(points.allSatisfy { abs($0.normalizedVelocity) <= 1.0001 })
    }

    func testCurveIsAnchoredToTheFirstTargetNotBeatZero() {
        // The built-in drills open with an empty lead-in bar, so the first
        // target sits a full bar in. The curve has to follow it - anchoring
        // at beat 0 would draw the whole ghost a bar early and out of sync
        // with the dots it's supposed to line up with.
        let pattern = ScratchPattern(
            id: "t",
            name: "t",
            bpm: 120,
            bars: 2,
            strokes: [TargetStroke(beatPosition: 4, direction: .forward, relativeDisplacement: nil, timingToleranceMs: 100)],
            beatLoopAsset: nil,
            defaultSampleAsset: "x"
        )
        let points = PerfectRunCurve.points(for: pattern)

        // Centred on beat 4, so the hump opens half a stroke before it...
        XCTAssertEqual(points.first?.beat ?? -1, 3.75, accuracy: 0.0001)

        // ...and, the part that actually matters, peaks right on it.
        let peak = points.max { abs($0.normalizedVelocity) < abs($1.normalizedVelocity) }
        XCTAssertEqual(peak?.beat ?? -1, 4, accuracy: 0.0001)
    }

    func testEmptyPatternProducesNoPoints() {
        let pattern = ScratchPattern(id: "t", name: "t", bpm: 120, bars: 1, strokes: [], beatLoopAsset: nil, defaultSampleAsset: "x")
        XCTAssertTrue(PerfectRunCurve.points(for: pattern).isEmpty)
    }
}

final class BuiltInDrillsTests: XCTestCase {
    private var doubleTime: ScratchPattern { BuiltInDrills.babyScratchDoubleTime90 }
    private var eighths: ScratchPattern { BuiltInDrills.babyScratchMedium }

    func testDoubleTimeHasTwiceTheStrokesAtHalfTheSpacing() {
        XCTAssertEqual(doubleTime.strokes.count, eighths.strokes.count * 2)
        XCTAssertEqual(PerfectRunCurve.gapBeats(for: doubleTime), 0.25, accuracy: 0.0001)
        // Same wall-clock length - it's the same tempo, just subdivided.
        XCTAssertEqual(
            DrillTimeline.totalDuration(pattern: doubleTime),
            DrillTimeline.totalDuration(pattern: eighths),
            accuracy: 0.0001
        )
    }

    func testDoubleTimeStillAlternatesDirectionFromForward() {
        for (index, stroke) in doubleTime.strokes.enumerated() {
            XCTAssertEqual(stroke.direction, index % 2 == 0 ? .forward : .back, "stroke \(index)")
        }
    }

    func testEveryDrillsMatchWindowStaysClearOfTheNextSameDirectionTarget() {
        // A target matches any stroke within 3x its tolerance. Targets
        // alternate direction, so the nearest same-direction target is two
        // slots away - if the window reached that far, direction-preferring
        // matching could grab the wrong stroke entirely. This is why the
        // double-time drill's tolerance had to shrink with its spacing
        // rather than inherit the flat 100ms.
        for pattern in BuiltInDrills.all {
            let gapSeconds = PerfectRunCurve.gapBeats(for: pattern) * DrillTimeline.beatDuration(bpm: pattern.bpm)
            let sameDirectionGap = gapSeconds * 2
            // Skip the first stroke, which is deliberately given a wider
            // window and has no preceding target to be confused with.
            for stroke in pattern.strokes.dropFirst() {
                let window = (stroke.timingToleranceMs / 1000.0) * 3
                XCTAssertLessThan(window, sameDirectionGap, "\(pattern.id) window overlaps the next same-direction target")
            }
        }
    }

    func testDoubleTimeAsksForAReachablePeakVelocity() {
        // Inheriting the eighth-note throw would demand ~10.4 rad/s here;
        // the shorter double-time throw keeps it in the same range as the
        // other drills, which is what stops amplitude from failing every
        // stroke the way the old 33 1/3 reference did.
        let peak = PerfectRunCurve.targetPeakVelocity(for: doubleTime)
        XCTAssertGreaterThan(peak, PerfectRunCurve.targetPeakVelocity(for: eighths))
        XCTAssertLessThan(peak, 8.0)
    }

    func testDrillIDsAreUnique() {
        let ids = BuiltInDrills.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "drill ids must be unique - best scores are keyed on them")
    }
}

final class DrillScorerIncrementalTests: XCTestCase {
    private func twoTargetPattern() -> ScratchPattern {
        ScratchPattern(
            id: "t",
            name: "t",
            bpm: 120,
            bars: 1,
            strokes: [
                TargetStroke(beatPosition: 4, direction: .forward, relativeDisplacement: nil, timingToleranceMs: 80),
                TargetStroke(beatPosition: 8, direction: .back, relativeDisplacement: nil, timingToleranceMs: 80),
            ],
            beatLoopAsset: nil,
            defaultSampleAsset: "x"
        )
    }

    func testUnchangedSampleDoesNotRetroactivelyAlterAlreadyResolvedStatuses() {
        let pattern = twoTargetPattern()
        let stroke = ScratchStroke(startTime: 2.0, endTime: 2.1, direction: .forward, peakVelocity: 3, displacement: 0.5)
        let previous = DrillScorer.statuses(pattern: pattern, performed: [stroke], elapsedTime: 2.05)
        guard case .hit = previous[0] else {
            return XCTFail("test setup expected target 0 to already be a hit")
        }

        // performedDidChange: false - even though we pass a different
        // (empty) performed list, the cheap path must trust `previous`
        // for anything already resolved rather than re-matching.
        let result = DrillScorer.statuses(previous: previous, pattern: pattern, performed: [], elapsedTime: 2.06, performedDidChange: false)
        XCTAssertEqual(result[0], previous[0])
    }

    func testUnchangedSampleStillFlipsUpcomingToMissedOnTime() {
        let pattern = twoTargetPattern()
        let previous: [TargetStrokeStatus] = [.upcoming, .upcoming]

        // target 1's time = 8 * 0.5 = 4.0s; window closes at 4.0 + 0.08*3 = 4.24s
        let result = DrillScorer.statuses(previous: previous, pattern: pattern, performed: [], elapsedTime: 5.0, performedDidChange: false)
        XCTAssertEqual(result, [.missed, .missed])
    }

    func testResolvedStatusSurvivesItsStrokeAgingOutOfTheLiveWindow() {
        let pattern = twoTargetPattern()
        let stroke = ScratchStroke(startTime: 1.95, endTime: 2.05, direction: .forward, peakVelocity: 6.9, displacement: 0.5, peakTime: 2.0)
        let resolved = DrillScorer.statuses(pattern: pattern, performed: [stroke], elapsedTime: 2.1)
        guard case .hit = resolved[0] else {
            return XCTFail("test setup expected target 0 to be a hit")
        }

        // Live matching runs against a rolling window, so a few seconds
        // later that stroke is gone from `performed` entirely and a
        // re-match finds nothing for target 0. Its timing window closed
        // long ago, so without explicit protection it would come back
        // `.missed` - the graded dot would silently turn red.
        let later = DrillScorer.statuses(previous: resolved, pattern: pattern, performed: [], elapsedTime: 6.0, performedDidChange: true)
        XCTAssertEqual(later[0], resolved[0], "a graded target must keep its grade after its stroke ages out of the live window")
    }

    func testChangedSampleRunsFullMatchAndMatchesNonIncrementalResult() {
        let pattern = twoTargetPattern()
        let stroke = ScratchStroke(startTime: 2.0, endTime: 2.1, direction: .forward, peakVelocity: 3, displacement: 0.5)
        let previous: [TargetStrokeStatus] = [.upcoming, .upcoming]

        let incremental = DrillScorer.statuses(previous: previous, pattern: pattern, performed: [stroke], elapsedTime: 2.05, performedDidChange: true)
        let full = DrillScorer.statuses(pattern: pattern, performed: [stroke], elapsedTime: 2.05)
        XCTAssertEqual(incremental, full)
    }
}
