import AVFoundation

/// Plays a short click on every beat, giving the user a tempo reference
/// during practice. There's no bundled beat-loop audio asset yet (see
/// ScratchPattern.beatLoopAsset) — this is the stand-in for it.
final class Metronome {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var clickBuffer: AVAudioPCMBuffer?
    private var tickTask: Task<Void, Never>?

    init() {
        buildClickBuffer()
        engine.attach(player)
        if let clickBuffer {
            engine.connect(player, to: engine.mainMixerNode, format: clickBuffer.format)
        }
        try? engine.start()
    }

    func start(bpm: Double) {
        stop()
        let beatDuration = 60.0 / bpm
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(nanoseconds: UInt64(beatDuration * 1_000_000_000))
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func tick() {
        guard let clickBuffer else { return }
        player.scheduleBuffer(clickBuffer, at: nil, options: .interrupts)
        if !player.isPlaying {
            player.play()
        }
    }

    private func buildClickBuffer() {
        let sampleRate = 48_000.0
        let duration = 0.02
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        let channel = buffer.floatChannelData![0]
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let envelope = 1.0 - (t / duration)
            channel[frame] = Float(sin(2 * .pi * 1500 * t) * envelope)
        }
        clickBuffer = buffer
    }
}
