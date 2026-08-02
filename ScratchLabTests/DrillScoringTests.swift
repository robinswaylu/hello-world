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

        guard case .hit(let score) = statuses[0] else {
            return XCTFail("expected a hit, got \(statuses[0])")
        }
        XCTAssertEqual(score, 100, accuracy: 0.5)
    }

    func testWrongDirectionStillCountsAsHitWithLowerScore() {
        let pattern = singleTargetPattern()
        let stroke = ScratchStroke(startTime: 2.0, endTime: 2.1, direction: .back, peakVelocity: 3, displacement: 0.5)
        let statuses = DrillScorer.statuses(pattern: pattern, performed: [stroke], elapsedTime: 2.05)

        guard case .hit(let score) = statuses[0] else {
            return XCTFail("expected a hit (matched but wrong direction), got \(statuses[0])")
        }
        XCTAssertEqual(score, 70, accuracy: 0.5)
    }
}
