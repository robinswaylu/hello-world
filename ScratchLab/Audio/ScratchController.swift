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

    init(audioEngine: ScratchAudioEngine, rotationStream: RotationStream = RotationStream()) {
        self.audioEngine = audioEngine
        self.rotationStream = rotationStream
    }

    func start() {
        stop()
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
        streamTask?.cancel()
        streamTask = nil
        audioEngine.stop()
    }

    private func ingest(_ sample: RotationSample) {
        platterState = baselineEstimator.ingest(sample.z)
        let corrected = baselineEstimator.correctedVelocity(sample.z)
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
