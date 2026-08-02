import Foundation

/// A rough audio preview of a drill pattern: steps through the target
/// strokes and drives the scratch engine's rate to match their direction
/// and timing, so a player can hear roughly what the drill should sound
/// like before attempting it (there's no separately recorded demo audio).
@MainActor
final class DrillPreviewPlayer: ObservableObject {
    @Published private(set) var isPlaying = false

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
                audioEngine.setRate(stroke.direction == .forward ? 1.5 : -1.5)

                let holdDuration: TimeInterval
                if index + 1 < strokes.count {
                    holdDuration = (strokes[index + 1].beatPosition - stroke.beatPosition) * beatDuration
                } else {
                    holdDuration = beatDuration * 0.5
                }
                try? await Task.sleep(nanoseconds: UInt64(max(holdDuration, 0.01) * 1_000_000_000))
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
}
