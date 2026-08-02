import Foundation

struct GyroSample: Identifiable {
    let id = UUID()
    let timestamp: TimeInterval
    let x: Double
    let y: Double
    let z: Double

    var zDegPerSec: Double { z * 180.0 / .pi }
    var zRPM: Double { (z * 60.0) / (2 * .pi) }
}
