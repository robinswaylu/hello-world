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

    static func signMultiplier(for orientation: ScreenOrientation) -> Double {
        orientation == .screenUp ? 1.0 : -1.0
    }
}
