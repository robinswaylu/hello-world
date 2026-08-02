import Foundation

enum ScreenOrientation: Equatable {
    case screenUp
    case screenDown
}

/// Determines whether the phone is lying screen-up or screen-down from the
/// gravity vector's Z component, so the Z rotation-rate sign can be
/// corrected via an explicit calibration step rather than an assumption —
/// screen-down otherwise reads every scratch backwards.
enum OrientationCalibrator {
    static func orientation(gravityZ: Double) -> ScreenOrientation {
        gravityZ > 0 ? .screenDown : .screenUp
    }

    /// Core Motion's rotationRate.z is in the device's own frame (Z out of
    /// the screen). Screen-up on a platter, that Z axis points straight up,
    /// and by the right-hand rule a POSITIVE rotationRate.z is
    /// counterclockwise as seen by someone looking down at the platter from
    /// above. But a real record spins CLOCKWISE from above during normal
    /// forward playback — so screen-up needs a NEGATIVE multiplier to make
    /// our internal "positive = forward" convention match a real turntable.
    /// Screen-down flips the physical Z axis too, so it needs the opposite
    /// correction.
    static func signMultiplier(for orientation: ScreenOrientation) -> Double {
        orientation == .screenUp ? -1.0 : 1.0
    }
}
