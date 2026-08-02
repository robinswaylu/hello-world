import AVFoundation

/// Drives the scratch sample voice from an external rate signal (typically
/// the smoothed velocity ratio from Phase 1's BaselineEstimator +
/// VelocitySmoother). Never uses AVAudioUnitVarispeed or AVAudioPlayerNode's
/// own rate control — neither supports negative (reverse) rates — so
/// playback goes through a custom AVAudioSourceNode read-head instead (see
/// ReadHead.swift for the pure-Swift render math this wraps).
final class ScratchAudioEngine {
    /// Mutable render-thread state, isolated from the class itself so the
    /// render closure never needs to capture `self`.
    private final class RenderState {
        var readHead: ReadHead
        var previousRate: Double = 0
        var targetRate: Double = 0
        let lock = NSLock()

        init(readHead: ReadHead) {
            self.readHead = readHead
        }
    }

    private let engine = AVAudioEngine()
    private let sourceNode: AVAudioSourceNode
    private let renderState: RenderState

    private(set) var achievedIOBufferDuration: TimeInterval = 0

    init(samples: [Float], loopStart: Int = 0, loopEnd: Int? = nil, sampleRate: Double = 48_000, crossfadeFrames: Int = 220) {
        let effectiveLoopEnd = loopEnd ?? samples.count
        let crossfaded = LoopCrossfader.apply(to: samples, loopStart: loopStart, loopEnd: effectiveLoopEnd, crossfadeFrames: crossfadeFrames)
        let state = RenderState(readHead: ReadHead(samples: crossfaded, loopStart: loopStart, loopEnd: effectiveLoopEnd))
        renderState = state

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            fatalError("ScratchAudioEngine: failed to create audio format")
        }

        sourceNode = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            state.lock.lock()
            let startRate = state.previousRate
            let endRate = state.targetRate
            let output = state.readHead.render(frameCount: Int(frameCount), startRate: startRate, endRate: endRate)
            state.previousRate = endRate
            state.lock.unlock()

            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in buffers {
                let bufferPointer = UnsafeMutableBufferPointer<Float>(buffer)
                for frame in 0..<Int(frameCount) {
                    bufferPointer[frame] = output[frame]
                }
            }
            return noErr
        }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
    }

    func start() throws {
        try configureSession()
        try engine.start()
        achievedIOBufferDuration = AVAudioSession.sharedInstance().ioBufferDuration
    }

    func stop() {
        engine.stop()
    }

    func setRate(_ rate: Double) {
        renderState.lock.lock()
        renderState.targetRate = rate
        renderState.lock.unlock()
    }

    private func configureSession() throws {
        // Shared with PracticeSession, which has to activate the session
        // earlier than this (before taking its timing anchor) so it can
        // read a valid output latency. Idempotent either way.
        AudioSessionSetup.activate()
    }
}
