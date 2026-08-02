import Foundation

/// Wires Phase 1's rotation signal core to the Phase 2 audio engine:
/// consumes the live rotation stream, locks onto the platter's baseline
/// speed, smooths the signal, and converts it to a playback-rate ratio
/// (rate = correctedVelocity / referenceVelocity, per the spec's formula)
/// that drives the scratch sample's read head.
@MainActor
final class ScratchController: ObservableObject {
    @Published private(set) var platterState: PlatterState = .unknown
    @Published private(set) var currentRate: Double = 0
    @Published private(set) var startError: String?

    private let rotationStream: RotationStream
    private let audioEngine: ScratchAudioEngine
    private let baselineEstimator = BaselineEstimator()
    private var velocitySmoother = VelocitySmoother()
    private var streamTask: Task<Void, Never>?
    private var hasCalibratedThisSession = false

    init(audioEngine: ScratchAudioEngine, rotationStream: RotationStream = RotationStream()) {
        self.audioEngine = audioEngine
        self.rotationStream = rotationStream
    }

    func start() {
        stop()
        hasCalibratedThisSession = false
        do {
            try audioEngine.start()
            startError = nil
        } catch {
            startError = "Audio engine failed to start: \(error.localizedDescription)"
        }

        streamTask = Task {
            for await sample in rotationStream.samples() {
                ingest(sample)
            }
        }
    }

    func stop() {
        rotationStream.stop()
        streamTask?.cancel()
        streamTask = nil
        audioEngine.stop()
    }

    private func ingest(_ sample: RotationSample) {
        // Re-detect screen-up/down fresh every session from the first
        // sample's gravity reading, rather than trusting whatever was
        // stored the last time onboarding's calibration step ran (which
        // goes stale the moment the phone is flipped, or the sign
        // convention itself changes in a later update).
        if !hasCalibratedThisSession {
            hasCalibratedThisSession = true
            CalibrationStore.orientation = OrientationCalibrator.orientation(gravityZ: sample.gravityZ)
        }

        let z = sample.z * CalibrationStore.signMultiplier
        platterState = baselineEstimator.ingest(z)
        let corrected = baselineEstimator.correctedVelocity(z)
        let smoothed = velocitySmoother.process(corrected, timestamp: sample.timestamp)

        let reference: Double
        switch platterState {
        case .rpm45:
            reference = BaselineEstimator.angularVelocity(forRPM: BaselineEstimator.rpm45)
        case .motorOff, .unknown, .rpm33:
            reference = BaselineEstimator.angularVelocity(forRPM: BaselineEstimator.rpm33)
        }

        let rate = smoothed / reference
        currentRate = rate
        audioEngine.setRate(rate)
    }
}
