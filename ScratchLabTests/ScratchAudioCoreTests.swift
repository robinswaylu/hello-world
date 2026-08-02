import XCTest
@testable import ScratchLab

final class ReadHeadTests: XCTestCase {
    func testForwardUnitRateReadsSamplesInOrder() {
        let samples: [Float] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
        var head = ReadHead(samples: samples, loopStart: 0, loopEnd: samples.count, startPosition: 0)
        let output = head.render(frameCount: 5, startRate: 1, endRate: 1)
        XCTAssertEqual(output, [0, 1, 2, 3, 4])
    }

    func testNegativeRateReadsBackward() {
        let samples: [Float] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
        var head = ReadHead(samples: samples, loopStart: 0, loopEnd: samples.count, startPosition: 5)
        let output = head.render(frameCount: 5, startRate: -1, endRate: -1)
        XCTAssertEqual(output, [5, 4, 3, 2, 1])
    }

    func testLoopWrapsForwardAtTheBoundary() {
        let samples: [Float] = [0, 1, 2, 3]
        var head = ReadHead(samples: samples, loopStart: 0, loopEnd: 4, startPosition: 2)
        let output = head.render(frameCount: 6, startRate: 1, endRate: 1)
        XCTAssertEqual(output, [2, 3, 0, 1, 2, 3])
    }

    func testFractionalRateInterpolatesLinearly() {
        let samples: [Float] = [0, 10]
        var head = ReadHead(samples: samples, loopStart: 0, loopEnd: 2, startPosition: 0)
        let output = head.render(frameCount: 3, startRate: 0.5, endRate: 0.5)
        XCTAssertEqual(output, [0, 5, 10])
    }

    func testRenderRampsRateGraduallyAcrossTheBuffer() {
        let samples = (0...50).map { Float($0) }
        var head = ReadHead(samples: samples, loopStart: 0, loopEnd: samples.count, startPosition: 0)
        let output = head.render(frameCount: 4, startRate: 0, endRate: 3)

        XCTAssertEqual(output.count, 4)
        // A naive jump straight to rate 3 for the whole buffer would read
        // close to samples[9] (0+3+3+3) by the last frame; ramping from a
        // standing start should cover noticeably less ground than that...
        XCTAssertLessThan(output.last!, 9)
        // ...but still more than a flat rate-0 hold, which would read 0
        // every frame.
        XCTAssertGreaterThan(output.last!, 0)
        // Both the sample data and the ramp are monotonic increasing, so
        // the output should never decrease frame-to-frame.
        for i in 1..<output.count {
            XCTAssertGreaterThanOrEqual(output[i], output[i - 1])
        }
    }
}

final class LoopCrossfaderTests: XCTestCase {
    func testCrossfadeBlendsTailTowardHead() {
        let samples: [Float] = [0, 0, 0, 0, 10, 10, 10, 10]
        let result = LoopCrossfader.apply(to: samples, loopStart: 0, loopEnd: 8, crossfadeFrames: 4)

        XCTAssertEqual(Array(result[0..<4]), [0, 0, 0, 0], "head should be untouched")
        XCTAssertEqual(result[7], samples[0], accuracy: 0.01, "last tail sample should land close to the head's first sample")
        XCTAssertLessThan(result[7], samples[7], "tail should be pulled down from its original value")
        XCTAssertGreaterThan(result[4], result[7], "should fade monotonically toward the head value")
    }

    func testCrossfadeIsANoOpWhenFramesIsZero() {
        let samples: [Float] = [1, 2, 3, 4]
        let result = LoopCrossfader.apply(to: samples, loopStart: 0, loopEnd: 4, crossfadeFrames: 0)
        XCTAssertEqual(result, samples)
    }
}

final class SineSweepGeneratorTests: XCTestCase {
    func testGeneratesExpectedFrameCount() {
        let samples = SineSweepGenerator.generate(startFrequency: 440, endFrequency: 880, duration: 1.0, sampleRate: 48_000)
        XCTAssertEqual(samples.count, 48_000)
    }

    func testOutputStaysWithinValidAmplitudeRange() {
        let samples = SineSweepGenerator.generate(startFrequency: 440, endFrequency: 880, duration: 0.5, sampleRate: 48_000)
        XCTAssertTrue(samples.allSatisfy { $0 >= -1.0 && $0 <= 1.0 })
    }

    func testFrequencyIncreasesOverTheSweep() {
        let samples = SineSweepGenerator.generate(startFrequency: 220, endFrequency: 880, duration: 1.0, sampleRate: 48_000)
        let mid = samples.count / 2
        let firstHalfCrossings = zeroCrossings(Array(samples[0..<mid]))
        let secondHalfCrossings = zeroCrossings(Array(samples[mid...]))
        XCTAssertGreaterThan(secondHalfCrossings, firstHalfCrossings)
    }

    private func zeroCrossings(_ samples: [Float]) -> Int {
        var count = 0
        for i in 1..<samples.count where (samples[i - 1] < 0) != (samples[i] < 0) {
            count += 1
        }
        return count
    }
}
