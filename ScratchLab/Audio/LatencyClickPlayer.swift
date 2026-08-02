import AVFoundation

/// Plays a short click whenever velocity crosses a threshold, so the user can
/// feel gyro-to-audio latency on real hardware (Phase 0's latency probe).
final class LatencyClickPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var clickBuffer: AVAudioPCMBuffer?

    private let thresholdRadPerSec: Double
    private let cooldown: TimeInterval = 0.25
    private var lastTriggerTime: TimeInterval = 0
    private var isArmed = false

    init(thresholdRadPerSec: Double = 1.0) {
        self.thresholdRadPerSec = thresholdRadPerSec
        configureSession()
        buildClickBuffer()

        engine.attach(player)
        if let clickBuffer {
            engine.connect(player, to: engine.mainMixerNode, format: clickBuffer.format)
        }
        try? engine.start()
    }

    func setArmed(_ armed: Bool) {
        isArmed = armed
    }

    func evaluate(velocity: Double, timestamp: TimeInterval) {
        guard isArmed else { return }
        guard abs(velocity) >= thresholdRadPerSec else { return }
        guard timestamp - lastTriggerTime >= cooldown else { return }
        lastTriggerTime = timestamp
        triggerClick()
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setPreferredIOBufferDuration(0.005)
        try? session.setActive(true)
    }

    private func buildClickBuffer() {
        let sampleRate = 48_000.0
        let duration = 0.01
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        let channel = buffer.floatChannelData![0]
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let envelope = 1.0 - (t / duration)
            channel[frame] = Float(sin(2 * .pi * 1000 * t) * envelope)
        }
        clickBuffer = buffer
    }

    private func triggerClick() {
        guard let clickBuffer else { return }
        player.scheduleBuffer(clickBuffer, at: nil, options: .interrupts)
        if !player.isPlaying {
            player.play()
        }
    }
}
