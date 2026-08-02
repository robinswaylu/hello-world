import Foundation

/// Persists the detected orientation (see OrientationCalibrator) across app
/// launches, and always re-detects it fresh at the start of every live
/// capture session (see ScratchController/PracticeSession) rather than
/// relying solely on the one-time onboarding step.
///
/// Deliberately stores the *orientation*, not a derived sign number: a
/// stored raw multiplier would go stale the moment the sign convention in
/// OrientationCalibrator ever changes again, silently reapplying an
/// outdated correction. Storing the orientation and deriving the
/// multiplier fresh every read means a future convention fix takes effect
/// immediately, with no manual recalibration required.
enum CalibrationStore {
    private static let key = "calibratedScreenOrientation"

    static var orientation: ScreenOrientation {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let value = ScreenOrientation(rawValue: raw) else {
                return .screenUp // uncalibrated default
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }

    static var signMultiplier: Double {
        OrientationCalibrator.signMultiplier(for: orientation)
    }
}
