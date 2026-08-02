import Foundation

/// Persists the one-time orientation calibration result (see
/// OrientationCalibrator) across app launches.
enum CalibrationStore {
    private static let key = "orientationSignMultiplier"

    static var signMultiplier: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: key)
            return stored == 0 ? OrientationCalibrator.signMultiplier(for: .screenUp) : stored
        }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }
}
