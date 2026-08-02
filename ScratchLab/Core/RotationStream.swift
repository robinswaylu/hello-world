import CoreMotion
import Foundation

/// Thin Core Motion wrapper that yields Z angular-velocity samples as an
/// AsyncStream. Prefers device motion (bias-corrected); falls back to raw
/// gyro if device motion isn't available.
final class RotationStream {
    private let motionManager: CMMotionManager
    private let updateInterval: TimeInterval
    private var continuation: AsyncStream<RotationSample>.Continuation?

    init(motionManager: CMMotionManager = CMMotionManager(), updateInterval: TimeInterval = 1.0 / 200.0) {
        self.motionManager = motionManager
        self.updateInterval = updateInterval
    }

    func samples() -> AsyncStream<RotationSample> {
        AsyncStream { continuation in
            self.continuation = continuation

            if motionManager.isDeviceMotionAvailable {
                motionManager.deviceMotionUpdateInterval = updateInterval
                motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { motion, _ in
                    guard let motion else { return }
                    continuation.yield(RotationSample(timestamp: motion.timestamp, z: motion.rotationRate.z))
                }
            } else if motionManager.isGyroAvailable {
                motionManager.gyroUpdateInterval = updateInterval
                motionManager.startGyroUpdates(to: .main) { data, _ in
                    guard let data else { return }
                    continuation.yield(RotationSample(timestamp: data.timestamp, z: data.rotationRate.z))
                }
            } else {
                continuation.finish()
            }

            continuation.onTermination = { [motionManager] _ in
                motionManager.stopDeviceMotionUpdates()
                motionManager.stopGyroUpdates()
            }
        }
    }

    /// Ends the stream: stops Core Motion updates and lets any active
    /// `for await` loop over `samples()` exit on its own. Cancelling the
    /// consuming Task alone does NOT do this — AsyncStream doesn't poll
    /// for task cancellation, so without this the capture (and whatever
    /// keeps consuming it) would silently keep running in the background.
    func stop() {
        continuation?.finish()
        continuation = nil
    }
}
