import Foundation

/// A rough audio preview of a drill pattern: steps through the target
/// strokes and drives the scratch engine's rate to match their direction
/// and timing, so a player can hear roughly what the drill should sound
/// like before attempting it (there's no separately recorded demo audio).
///
/// Each stroke ramps the rate through a half-sine envelope (0 -> peak -> 0)
/// rather than holding a constant rate for the stroke's duration - a real
/// scratch stroke accelerates and decelerates, it doesn't snap to a speed
/// and hold it, and a constant-rate hold just sounds like fast-forward/
/// rewind through the sample rather than a scratch.
@MainActor
final class DrillPreviewPlayer: ObservableObject {
    @Published private(set) var isPlaying = false

    private static let peakRate = 2.0
    private static let stepInterval: TimeInterval = 0.015

    private let pattern: ScratchPattern
    private let audioEngine: ScratchAudioEngine
    private var playTask: Task<Void, Never>?

    init(pattern: ScratchPattern) {
        self.pattern = pattern
        self.audioEngine = ScratchAudioEngine(
            samples: ScratchSampleProvider.loadDefaultSample(),
            sampleRate: SampleLibrary.engineSampleRate
        )
    }

    func play() {
        stop()
        isPlaying = true
        let beatDuration = DrillTimeline.beatDuration(bpm: pattern.bpm)
        let strokes = pattern.strokes

        playTask = Task {
            try? audioEngine.start()
            for (index, stroke) in strokes.enumerated() {
                guard !Task.isCancelled else { break }

                let strokeDuration: TimeInterval
                if index + 1 < strokes.count {
                    strokeDuration = (strokes[index + 1].beatPosition - stroke.beatPosition) * beatDuration
                } else {
                    strokeDuration = beatDuration * 0.5
                }
                await performStroke(direction: stroke.direction, duration: max(strokeDuration, 0.05))
            }
            audioEngine.setRate(0)
            audioEngine.stop()
            isPlaying = false
        }
    }

    func stop() {
        playTask?.cancel()
        playTask = nil
        audioEngine.setRate(0)
        audioEngine.stop()
        isPlaying = false
    }

    private func performStroke(direction: Direction, duration: TimeInterval) async {
        let sign = direction == .forward ? 1.0 : -1.0
        let steps = max(Int(duration / Self.stepInterval), 1)

        for step in 0..<steps {
            guard !Task.isCancelled else { return }
            let t = Double(step) / Double(steps)
            let envelope = sin(.pi * t) // 0 -> 1 -> 0 across the stroke
            audioEngine.setRate(sign * Self.peakRate * envelope)
            try? await Task.sleep(nanoseconds: UInt64(Self.stepInterval * 1_000_000_000))
        }
    }
}
