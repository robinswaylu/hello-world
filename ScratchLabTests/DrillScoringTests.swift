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

    func testHitWhenMatched() {
        let pattern = singleTargetPattern()
        let stroke = ScratchStroke(startTime: 2.0, endTime: 2.1, direction: .forward, peakVelocity: 3, displacement: 0.5)
        let statuses = DrillScorer.statuses(pattern: pattern, performed: [stroke], elapsedTime: 2.05)

        guard case .hit(let grade, let score) = statuses[0] else {
            return XCTFail("expected a hit, got \(statuses[0])")
        }
        XCTAssertEqual(grade, .perfect)
        XCTAssertEqual(score, 100, accuracy: 0.5)
    }

    func testWrongDirectionIsGradedPoorWithLowScore() {
        let pattern = singleTargetPattern()
        let stroke = ScratchStroke(startTime: 2.0, endTime: 2.1, direction: .back, peakVelocity: 3, displacement: 0.5)
        let statuses = DrillScorer.statuses(pattern: pattern, performed: [stroke], elapsedTime: 2.05)

        guard case .hit(let grade, let score) = statuses[0] else {
            return XCTFail("expected a hit (matched but wrong direction), got \(statuses[0])")
        }
        // Wrong direction is capped at .poor even with perfect timing - it's
        // a different move, not an imprecise version of the right one.
        XCTAssertEqual(grade, .poor)
        XCTAssertEqual(score, 20, accuracy: 0.5)
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

    func testChangedSampleRunsFullMatchAndMatchesNonIncrementalResult() {
        let pattern = twoTargetPattern()
        let stroke = ScratchStroke(startTime: 2.0, endTime: 2.1, direction: .forward, peakVelocity: 3, displacement: 0.5)
        let previous: [TargetStrokeStatus] = [.upcoming, .upcoming]

        let incremental = DrillScorer.statuses(previous: previous, pattern: pattern, performed: [stroke], elapsedTime: 2.05, performedDidChange: true)
        let full = DrillScorer.statuses(pattern: pattern, performed: [stroke], elapsedTime: 2.05)
        XCTAssertEqual(incremental, full)
    }
}
