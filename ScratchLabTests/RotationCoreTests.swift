import XCTest
@testable import ScratchLab

final class BaselineEstimatorTests: XCTestCase {
    func testLocksMotorOffOnSteadyNearZeroSignal() {
        let estimator = BaselineEstimator(windowSize: 10, lockSpreadTolerance: 0.15)
        var state: PlatterState = .unknown
        for i in 0..<10 {
            let noise = (i % 2 == 0) ? 0.01 : -0.01
            state = estimator.ingest(noise)
        }
        XCTAssertEqual(state, .motorOff)
        XCTAssertTrue(estimator.isLocked)
    }

    func testLocksRPM33OnSteadySpin() {
        let estimator = BaselineEstimator(windowSize: 10, lockSpreadTolerance: 0.15)
        let target = BaselineEstimator.angularVelocity(forRPM: BaselineEstimator.rpm33)
        var state: PlatterState = .unknown
        for i in 0..<10 {
            let noise = (i % 2 == 0) ? 0.02 : -0.02
            state = estimator.ingest(target + noise)
        }
        XCTAssertEqual(state, .rpm33)
    }

    func testLocksRPM45OnSteadySpin() {
        let estimator = BaselineEstimator(windowSize: 10, lockSpreadTolerance: 0.15)
        let target = BaselineEstimator.angularVelocity(forRPM: BaselineEstimator.rpm45)
        var state: PlatterState = .unknown
        for i in 0..<10 {
            state = estimator.ingest(target)
        }
        XCTAssertEqual(state, .rpm45)
    }

    func testStaysUnknownWhileSpreadIsWide() {
        let estimator = BaselineEstimator(windowSize: 10, lockSpreadTolerance: 0.15)
        var state: PlatterState = .unknown
        for i in 0..<10 {
            state = estimator.ingest(Double(i) * 0.5) // ramps far beyond the tolerance
        }
        XCTAssertEqual(state, .unknown)
        XCTAssertFalse(estimator.isLocked)
    }

    func testZeroOffsetCorrectsMotorOffBiasDrift() {
        let estimator = BaselineEstimator(windowSize: 10, lockSpreadTolerance: 0.15)
        for _ in 0..<10 {
            estimator.ingest(0.05) // constant gyro bias while platter is actually still
        }
        XCTAssertEqual(estimator.lockedState, .motorOff)
        XCTAssertEqual(estimator.correctedVelocity(0.05), 0, accuracy: 0.0001)
    }
}

final class VelocitySmootherTests: XCTestCase {
    func testFirstSamplePassesThroughUnchanged() {
        var smoother = VelocitySmoother()
        XCTAssertEqual(smoother.process(5.0, timestamp: 0), 5.0, accuracy: 0.0001)
    }

    func testConvergesTowardAStepWithinFewSamples() {
        var smoother = VelocitySmoother(lowPassAlpha: 0.6, maxSlewPerSecond: 1000)
        _ = smoother.process(0, timestamp: 0)
        var value: Double = 0
        for i in 1...10 {
            value = smoother.process(10, timestamp: Double(i) * 0.01)
        }
        XCTAssertEqual(value, 10, accuracy: 0.1)
    }

    func testSlewLimitBoundsTheFirstStepOfALargeJump() {
        var smoother = VelocitySmoother(lowPassAlpha: 1.0, maxSlewPerSecond: 100)
        _ = smoother.process(0, timestamp: 0)
        // dt = 0.01s, max delta = 100 * 0.01 = 1.0, even though alpha=1 would otherwise jump straight to 50
        let value = smoother.process(50, timestamp: 0.01)
        XCTAssertEqual(value, 1.0, accuracy: 0.0001)
    }
}

final class GestureSegmenterTests: XCTestCase {
    func testIgnoresNoiseBelowStartThreshold() {
        let segmenter = GestureSegmenter(startThreshold: 0.3, stopThreshold: 0.1, debounceInterval: 0.03)
        let samples = (0..<20).map { (timestamp: Double($0) * 0.01, velocity: 0.05) }
        XCTAssertTrue(segmenter.segment(samples).isEmpty)
    }

    func testSingleStrokeUpAndBackDownIsOneStroke() {
        let segmenter = GestureSegmenter(startThreshold: 0.3, stopThreshold: 0.1, debounceInterval: 0.03)
        var samples: [(timestamp: TimeInterval, velocity: Double)] = []
        var t = 0.0
        for v in stride(from: 0.0, through: 2.0, by: 0.2) {
            samples.append((t, v)); t += 0.01
        }
        for v in stride(from: 2.0, through: 0.0, by: -0.2) {
            samples.append((t, v)); t += 0.01
        }
        // hold near zero past the debounce window so the stroke actually closes
        for _ in 0..<5 {
            samples.append((t, 0.0)); t += 0.01
        }

        let strokes = segmenter.segment(samples)
        XCTAssertEqual(strokes.count, 1)
        XCTAssertEqual(strokes[0].direction, .forward)
        XCTAssertEqual(strokes[0].peakVelocity, 2.0, accuracy: 0.0001)
    }

    func testDirectionReversalWithoutDroppingBelowStopSplitsIntoTwoStrokes() {
        let segmenter = GestureSegmenter(startThreshold: 0.3, stopThreshold: 0.1, debounceInterval: 0.03)
        var samples: [(timestamp: TimeInterval, velocity: Double)] = []
        var t = 0.0
        for v in stride(from: 0.0, through: 2.0, by: 0.2) {
            samples.append((t, v)); t += 0.01
        }
        for v in stride(from: -0.2, through: -2.0, by: -0.2) {
            samples.append((t, v)); t += 0.01
        }

        let strokes = segmenter.segment(samples)
        XCTAssertEqual(strokes.count, 2)
        XCTAssertEqual(strokes[0].direction, .forward)
        XCTAssertEqual(strokes[1].direction, .back)
    }

    func testSegmentsARealCapturedScratchBurst() {
        let segmenter = GestureSegmenter(startThreshold: 0.5, stopThreshold: 0.2, debounceInterval: 0.03)
        let strokes = segmenter.segment(RealCaptureFixture.aggressiveBurst)

        // This slice of real DDJ-REV5 gyro data is a fast back-and-forth
        // scratch burst; it should segment into several strokes, and the
        // fastest ones should be in the same ballpark as the peak we
        // measured directly from the CSV (~14.4 rad/s).
        XCTAssertGreaterThanOrEqual(strokes.count, 4)
        let fastestPeak = strokes.map(\.peakVelocity).max() ?? 0
        XCTAssertGreaterThan(fastestPeak, 10.0)
    }
}

final class PatternMatcherTests: XCTestCase {
    private func babyScratchPattern() -> ScratchPattern {
        ScratchPattern(
            id: "test-baby-scratch",
            name: "Baby Scratch",
            bpm: 120,
            bars: 1,
            strokes: [
                TargetStroke(beatPosition: 0, direction: .forward, relativeDisplacement: 0.1...1.0, timingToleranceMs: 80),
                TargetStroke(beatPosition: 0.5, direction: .back, relativeDisplacement: 0.1...1.0, timingToleranceMs: 80),
            ],
            beatLoopAsset: nil,
            defaultSampleAsset: "sine-sweep"
        )
    }

    func testPerfectPerformanceScoresNearMaximum() {
        let pattern = babyScratchPattern()
        let beatDuration = 60.0 / pattern.bpm
        let performed = [
            ScratchStroke(startTime: 0, endTime: 0.1, direction: .forward, peakVelocity: 3, displacement: 0.5),
            ScratchStroke(startTime: 0.5 * beatDuration, endTime: 0.5 * beatDuration + 0.1, direction: .back, peakVelocity: 3, displacement: 0.5),
        ]
        let result = PatternMatcher.match(pattern: pattern, performed: performed)
        XCTAssertEqual(result.overallScore, 100, accuracy: 0.5)
        XCTAssertTrue(result.strokeScores.allSatisfy(\.matched))
    }

    func testWrongDirectionIsCappedAtPoorRegardlessOfTiming() {
        let pattern = babyScratchPattern()
        let performed = [
            ScratchStroke(startTime: 0, endTime: 0.1, direction: .back, peakVelocity: 3, displacement: 0.5),
            ScratchStroke(startTime: 30, endTime: 30.1, direction: .back, peakVelocity: 3, displacement: 0.5),
        ]
        let result = PatternMatcher.match(pattern: pattern, performed: performed)
        // Perfect timing (0ms error) but wrong direction: capped at .poor
        // with only small consolation credit, not scaled down from 100.
        XCTAssertEqual(result.strokeScores[0].grade, .poor)
        XCTAssertEqual(result.strokeScores[0].score, 20, accuracy: 0.5)
    }

    func testMissingStrokeScoresZeroAndIsUnmatched() {
        let pattern = babyScratchPattern()
        let result = PatternMatcher.match(pattern: pattern, performed: [])
        XCTAssertEqual(result.overallScore, 0)
        XCTAssertTrue(result.strokeScores.allSatisfy { !$0.matched })
        XCTAssertTrue(result.strokeScores.allSatisfy { $0.grade == .missed })
    }

    func testDisplacementOutOfRangeIsRecordedButDoesNotAffectScore() {
        let pattern = babyScratchPattern()
        let performed = [
            ScratchStroke(startTime: 0, endTime: 0.1, direction: .forward, peakVelocity: 3, displacement: 5.0),
            ScratchStroke(startTime: 30, endTime: 30.1, direction: .back, peakVelocity: 3, displacement: 0.5),
        ]
        let result = PatternMatcher.match(pattern: pattern, performed: performed)
        // Displacement isn't part of the score (no built-in drill currently
        // constrains it) - perfect timing + correct direction is still 100.
        XCTAssertFalse(result.strokeScores[0].displacementOk)
        XCTAssertEqual(result.strokeScores[0].grade, .perfect)
        XCTAssertEqual(result.strokeScores[0].score, 100, accuracy: 0.5)
    }
}

/// A ~1.2s slice of real Z angular-velocity data captured from the Phase 0
/// harness on a DDJ-REV5 jog wheel (motor-off mode): a fast, oscillating
/// scratch burst. Timestamps are seconds relative to the start of the slice.
private enum RealCaptureFixture {
    static let aggressiveBurst: [(timestamp: TimeInterval, velocity: Double)] = [
        (0.0, -10.5373), (0.00998, -9.0187), (0.01995, -7.4106), (0.02993, -5.4774), (0.03991, -3.2186), (0.04989, -0.527), (0.05987, 2.012), (0.06984, 4.3859), (0.07982, 6.7729), (0.0898, 8.6219), (0.09978, 9.8357), (0.10976, 10.7331), (0.11973, 11.1745), (0.12971, 11.1824), (0.13969, 10.5115), (0.14967, 8.7709), (0.15964, 5.6396), (0.16962, 1.53), (0.1796, -2.0741), (0.18958, -4.8077), (0.19956, -7.5122), (0.20953, -9.6005), (0.21951, -10.8019), (0.22949, -11.4276), (0.23947, -11.4436), (0.24944, -11.1631), (0.25942, -10.4655), (0.2694, -9.3805), (0.27938, -7.9074), (0.28936, -5.8062), (0.29933, -3.2303), (0.30931, 0.0159), (0.31929, 2.5829), (0.32927, 4.893), (0.33925, 7.4764), (0.34922, 9.8043), (0.3592, 11.7397), (0.36918, 13.3511), (0.37916, 14.3854), (0.38913, 14.3837), (0.39911, 13.2348), (0.40909, 10.2879), (0.41907, 4.8353), (0.42905, -1.0925), (0.43902, -4.7079), (0.449, -7.7123), (0.45898, -9.9333), (0.46896, -11.2998), (0.47894, -11.697), (0.48891, -11.2296), (0.49889, -10.6052), (0.50887, -9.6893), (0.51885, -8.2037), (0.52882, -6.4437), (0.5388, -4.2783), (0.54878, -1.6603), (0.55876, 1.1106), (0.56874, 2.9003), (0.57871, 4.6794), (0.58869, 6.168), (0.59867, 7.3962), (0.60865, 8.4572), (0.61862, 9.2023), (0.6286, 9.5602), (0.63858, 9.4455), (0.64856, 8.8923), (0.65853, 7.7274), (0.66851, 5.7701), (0.67849, 3.5015), (0.68847, 0.831), (0.69845, -1.2426), (0.70842, -2.7073), (0.7184, -4.0962), (0.72838, -5.2983), (0.73836, -6.2127), (0.74834, -6.8437), (0.75831, -7.2558), (0.76829, -7.5444), (0.77827, -7.7658), (0.78825, -7.799), (0.79822, -7.6079), (0.8082, -7.2241), (0.81818, -6.7829), (0.82816, -6.2263), (0.83814, -5.5799), (0.84811, -4.7996), (0.85809, -3.9234), (0.86807, -2.8609), (0.87805, -1.6462), (0.88802, -0.3234), (0.898, 0.7494), (0.90798, 1.5649), (0.91796, 2.3584), (0.92794, 3.1539), (0.93791, 3.8819), (0.94789, 4.5452), (0.95787, 5.1114), (0.96785, 5.6158), (0.97782, 6.0234), (0.9878, 6.2911), (0.99778, 6.4435), (1.00776, 6.5179), (1.01774, 6.4961), (1.02771, 6.3567), (1.03769, 6.0451), (1.04767, 5.6445), (1.05765, 5.2714), (1.06762, 4.8984), (1.0776, 4.5823), (1.08758, 4.3081), (1.09756, 4.0203), (1.10754, 3.7603), (1.11751, 3.4834), (1.12749, 3.252), (1.13747, 3.1147), (1.14745, 3.0416), (1.15743, 3.0511), (1.1674, 3.0178), (1.17738, 2.9188), (1.18736, 2.7882), (1.19734, 2.6702),
    ]
}
