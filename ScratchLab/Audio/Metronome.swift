import AVFoundation

/// Plays a click on every beat and a softer, lower one on each off-beat
/// "and", giving a tempo reference during practice. There's no bundled
/// beat-loop audio asset yet (see ScratchPattern.beatLoopAsset) — this is
/// the stand-in for it.
///
/// Eighth notes rather than quarter notes because the drills put a stroke
/// on every eighth: with a quarter-note click only the forward strokes had
/// a sound to hit and every back stroke had to be subdivided by feel,
/// which is exactly where rushing creeps in.
final class Metronome {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var accentBuffer: AVAudioPCMBuffer?
    private var offbeatBuffer: AVAudioPCMBuffer?
    private var tickTask: Task<Void, Never>?

    /// Fires on every tick - `true` on the beat, `false` on the off-beat
    /// "and" - so a view can drive a visual indicator in sync with the
    /// click. Called from this instance's own tick loop, not the main
    /// actor; callers that touch UI state need to hop back themselves.
    var onTick: ((Bool) -> Void)?

    init() {
        accentBuffer = Self.makeClick(frequency: 1500, amplitude: 1.0)
        offbeatBuffer = Self.makeClick(frequency: 1000, amplitude: 0.4)
        engine.attach(player)
        if let accentBuffer {
            engine.connect(player, to: engine.mainMixerNode, format: accentBuffer.format)
        }
        try? engine.start()
    }

    /// Starts ticking eighth notes from `anchor`, a `systemUptime` value.
    ///
    /// Every tick is scheduled against an absolute deadline derived from
    /// `anchor`, never by sleeping one interval at a time in a loop. A
    /// chained-sleep loop adds its own scheduling overhead on every
    /// iteration, so the click drifts progressively later and separates
    /// from the grid the drill actually scores against - tens of
    /// milliseconds over a full drill, which is a whole grading band. With
    /// an absolute deadline each tick self-corrects instead of inheriting
    /// the error of the one before it.
    ///
    /// Taking `anchor` from the caller rather than reading the clock here
    /// is what phase-locks the click to the scoring grid: `PracticeSession`
    /// derives both from the same value.
    func start(bpm: Double, anchor: TimeInterval) {
        stop()
        let interval = (60.0 / bpm) / 2

        tickTask = Task { [weak self] in
            var index = 0
            while !Task.isCancelled {
                let due = anchor + Double(index) * interval
                let delay = due - ProcessInfo.processInfo.systemUptime

                // More than a whole interval late (app was suspended, the
                // thread was starved): that click's moment has passed, so
                // skip it rather than firing a burst to catch up.
                if delay < -interval {
                    index += 1
                    continue
                }
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                guard !Task.isCancelled else { return }

                self?.tick(isDownbeat: index % 2 == 0)
                index += 1
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func tick(isDownbeat: Bool) {
        onTick?(isDownbeat)
        guard let buffer = isDownbeat ? accentBuffer : offbeatBuffer else { return }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying {
            player.play()
        }
    }

    private static func makeClick(frequency: Double, amplitude: Double) -> AVAudioPCMBuffer? {
        let sampleRate = 48_000.0
        let duration = 0.02
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        let channel = buffer.floatChannelData![0]
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let envelope = 1.0 - (t / duration)
            channel[frame] = Float(sin(2 * .pi * frequency * t) * envelope * amplitude)
        }
        return buffer
    }
}
