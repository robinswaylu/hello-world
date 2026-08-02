import CoreMotion
import Combine

/// Phase 0 diagnostic capture: reads Z-axis angular velocity at the highest rate
/// the device will give us, and tracks the stats the validation harness needs
/// (session min/max, achieved sample rate, gyro clipping).
@MainActor
final class MotionMonitor: ObservableObject {
    /// Typical iPhone gyro full-scale range is ±2000 deg/s.
    static let gyroFullScaleRadPerSec = 2000.0 * .pi / 180.0
    static let clippingThresholdFraction = 0.97

    @Published private(set) var isCapturing = false
    @Published private(set) var currentZ: Double = 0
    @Published private(set) var sessionMin: Double = 0
    @Published private(set) var sessionMax: Double = 0
    @Published private(set) var achievedSampleRateHz: Double = 0
    @Published private(set) var clippingCount: Int = 0
    @Published private(set) var recentSamples: [GyroSample] = []
    @Published private(set) var allSamples: [GyroSample] = []
    @Published private(set) var usingRawGyroFallback = false
    @Published private(set) var lastError: String?

    private let motionManager = CMMotionManager()
    // Ask for faster than any current iPhone supports; Core Motion clamps to
    // the hardware max, and achievedSampleRateHz reports what we actually got.
    private let desiredUpdateInterval = 1.0 / 200.0
    private var rateWindowTimestamps: [TimeInterval] = []
    private let rateWindowSize = 50
    private let chartWindowSeconds: TimeInterval = 5

    func start() {
        guard !isCapturing else { return }
        reset()
        isCapturing = true

        if motionManager.isDeviceMotionAvailable {
            usingRawGyroFallback = false
            motionManager.deviceMotionUpdateInterval = desiredUpdateInterval
            motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, error in
                guard let self else { return }
                if let error {
                    self.lastError = error.localizedDescription
                    return
                }
                guard let motion else { return }
                self.ingest(x: motion.rotationRate.x, y: motion.rotationRate.y, z: motion.rotationRate.z, timestamp: motion.timestamp)
            }
        } else if motionManager.isGyroAvailable {
            usingRawGyroFallback = true
            motionManager.gyroUpdateInterval = desiredUpdateInterval
            motionManager.startGyroUpdates(to: .main) { [weak self] data, error in
                guard let self else { return }
                if let error {
                    self.lastError = error.localizedDescription
                    return
                }
                guard let data else { return }
                self.ingest(x: data.rotationRate.x, y: data.rotationRate.y, z: data.rotationRate.z, timestamp: data.timestamp)
            }
        } else {
            lastError = "No gyroscope available on this device."
            isCapturing = false
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        motionManager.stopGyroUpdates()
        isCapturing = false
    }

    func reset() {
        currentZ = 0
        sessionMin = 0
        sessionMax = 0
        achievedSampleRateHz = 0
        clippingCount = 0
        recentSamples.removeAll()
        allSamples.removeAll()
        rateWindowTimestamps.removeAll()
        lastError = nil
    }

    private func ingest(x: Double, y: Double, z: Double, timestamp: TimeInterval) {
        let sample = GyroSample(timestamp: timestamp, x: x, y: y, z: z)

        currentZ = z
        sessionMin = min(sessionMin, z)
        sessionMax = max(sessionMax, z)
        if abs(z) >= Self.gyroFullScaleRadPerSec * Self.clippingThresholdFraction {
            clippingCount += 1
        }

        allSamples.append(sample)
        recentSamples.append(sample)
        let cutoff = timestamp - chartWindowSeconds
        while let first = recentSamples.first, first.timestamp < cutoff {
            recentSamples.removeFirst()
        }

        rateWindowTimestamps.append(timestamp)
        if rateWindowTimestamps.count > rateWindowSize {
            rateWindowTimestamps.removeFirst()
        }
        if rateWindowTimestamps.count >= 2, let first = rateWindowTimestamps.first, let last = rateWindowTimestamps.last {
            let span = last - first
            if span > 0 {
                achievedSampleRateHz = Double(rateWindowTimestamps.count - 1) / span
            }
        }
    }
}
