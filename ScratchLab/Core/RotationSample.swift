import Foundation

/// A single timestamped Z angular-velocity reading (rad/s), the only axis
/// the scratch model cares about, plus the gravity vector's Z component
/// (G's) for orientation calibration. `gravityZ` is 0 when unavailable
/// (the raw-gyro fallback path has no gravity data), which
/// OrientationCalibrator treats as screen-up.
struct RotationSample {
    let timestamp: TimeInterval
    let z: Double
    let gravityZ: Double
}
