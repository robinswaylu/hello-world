import AVFoundation

/// Loads bundled audio files into mono Float32 buffers at the engine's
/// fixed sample rate, converting sample rate/channel count as needed via
/// AVAudioConverter.
enum SampleLibrary {
    static let engineSampleRate = 48_000.0

    enum LoadError: Error {
        case fileNotFound
        case conversionSetupFailed
        case conversionFailed
    }

    static func loadMono(resource: String, withExtension ext: String) throws -> [Float] {
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            throw LoadError.fileNotFound
        }

        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat

        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw LoadError.conversionSetupFailed
        }
        try file.read(into: sourceBuffer)

        guard let monoFormat = AVAudioFormat(standardFormatWithSampleRate: engineSampleRate, channels: 1),
              let converter = AVAudioConverter(from: sourceFormat, to: monoFormat) else {
            throw LoadError.conversionSetupFailed
        }

        let ratio = engineSampleRate / sourceFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(sourceBuffer.frameLength) * ratio) + 1024
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: outputCapacity) else {
            throw LoadError.conversionSetupFailed
        }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if suppliedInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }
        if status == .error {
            throw conversionError ?? LoadError.conversionFailed
        }

        guard let channelData = outputBuffer.floatChannelData else {
            throw LoadError.conversionSetupFailed
        }
        return Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
    }
}

/// The scratch voice's default sample: the real (licensed) scratch sample
/// if it's bundled and loads successfully, falling back to the
/// programmatic sine sweep otherwise so the engine never has nothing to
/// play.
enum ScratchSampleProvider {
    static func loadDefaultSample() -> [Float] {
        do {
            return try SampleLibrary.loadMono(resource: "scratch-sentence", withExtension: "wav")
        } catch {
            return SineSweepGenerator.generate(
                startFrequency: 440,
                endFrequency: 880,
                duration: 1.0,
                sampleRate: SampleLibrary.engineSampleRate
            )
        }
    }
}
