import XCTest
@testable import ScratchLab

final class OrientationCalibratorTests: XCTestCase {
    func testPositiveGravityZMeansScreenDown() {
        XCTAssertEqual(OrientationCalibrator.orientation(gravityZ: 0.9), .screenDown)
    }

    func testNegativeGravityZMeansScreenUp() {
        XCTAssertEqual(OrientationCalibrator.orientation(gravityZ: -0.9), .screenUp)
    }

    func testZeroGravityZDefaultsToScreenUp() {
        // Matches RotationSample's convention: gravityZ == 0 means "no
        // gravity data available" (raw-gyro fallback), which should default
        // to the more common screen-up placement rather than flip signs.
        XCTAssertEqual(OrientationCalibrator.orientation(gravityZ: 0), .screenUp)
    }

    func testSignMultiplierMatchesOrientation() {
        // Screen-up: positive rotationRate.z is counterclockwise-from-above,
        // which is backward on a real (clockwise-from-above) turntable, so
        // it needs a negative multiplier to match our "positive = forward"
        // convention. Screen-down is the opposite correction.
        XCTAssertEqual(OrientationCalibrator.signMultiplier(for: .screenUp), -1.0)
        XCTAssertEqual(OrientationCalibrator.signMultiplier(for: .screenDown), 1.0)
    }
}
