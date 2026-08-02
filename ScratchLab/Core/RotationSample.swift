import Foundation

/// A single timestamped Z angular-velocity reading (rad/s), the only axis
/// the scratch model cares about.
struct RotationSample {
    let timestamp: TimeInterval
    let z: Double
}
