import Foundation

enum PlatterState: Equatable {
    case motorOff
    case rpm33
    case rpm45
    case unknown
}

/// Detects which known platter state (33⅓, 45, or motor-off) the incoming
/// rotation matches, using a rolling median so momentary scratch strokes
/// don't throw off the read. Re-zeroes gyro bias drift once a motor-off
/// baseline locks (baseline ≈ 0 is a valid, expected lock).
final class BaselineEstimator {
    static let rpm33 = 33.0 + 1.0 / 3.0
    static let rpm45 = 45.0

    static func angularVelocity(forRPM rpm: Double) -> Double {
        rpm * 2 * .pi / 60.0
    }

    private let windowSize: Int
    private let lockSpreadTolerance: Double
    private var window: [Double] = []

    private(set) var zeroOffset: Double = 0
    private(set) var isLocked = false
    private(set) var lockedState: PlatterState = .unknown

    init(windowSize: Int = 30, lockSpreadTolerance: Double = 0.15) {
        self.windowSize = windowSize
        self.lockSpreadTolerance = lockSpreadTolerance
    }

    @discardableResult
    func ingest(_ z: Double) -> PlatterState {
        window.append(z)
        if window.count > windowSize {
            window.removeFirst()
        }
        guard window.count == windowSize else { return lockedState }

        let spread = window.max()! - window.min()!
        guard spread <= lockSpreadTolerance else {
            isLocked = false
            lockedState = .unknown
            return lockedState
        }

        let median = Self.median(window)
        lockedState = Self.classify(median: median)
        isLocked = true
        if lockedState == .motorOff {
            zeroOffset = median
        }
        return lockedState
    }

    func correctedVelocity(_ z: Double) -> Double {
        z - zeroOffset
    }

    private static func classify(median: Double) -> PlatterState {
        let candidates: [(PlatterState, Double)] = [
            (.motorOff, 0),
            (.rpm33, angularVelocity(forRPM: rpm33)),
            (.rpm45, angularVelocity(forRPM: rpm45)),
        ]
        let magnitude = abs(median)
        return candidates.min { abs(magnitude - $0.1) < abs(magnitude - $1.1) }!.0
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
