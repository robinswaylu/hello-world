import Foundation
import SwiftData

enum PracticePhase: Equatable {
    case countdown(Int)
    case running
    case finished
}

/// Drives one practice attempt: countdown, live motion capture through
/// Phase 1's signal core, live audio through Phase 2's engine, a metronome
/// for tempo reference, live scoring against the target pattern, and
/// persisting the final result. Auto-starts after the countdown and
/// auto-stops once the pattern's duration has elapsed.
@MainActor
final class PracticeSession: ObservableObject {
    @Published private(set) var phase: PracticePhase = .countdown(3)
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var statuses: [TargetStrokeStatus]
    @Published private(set) var liveSamples: [(timestamp: TimeInterval, velocity: Double)] = []
    @Published private(set) var finalResult: MatchResult?

    let pattern: ScratchPattern

    private let rotationStream: RotationStream
    private let audioEngine: ScratchAudioEngine
    private let metronome = Metronome()
    private let baselineEstimator = BaselineEstimator()
    private var velocitySmoother = VelocitySmoother()
    private let segmenter = GestureSegmenter()

    private var streamTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var startTimestamp: TimeInterval?
    private let totalDuration: TimeInterval

    init(pattern: ScratchPattern, rotationStream: RotationStream = RotationStream()) {
        self.pattern = pattern
        self.rotationStream = rotationStream
        self.audioEngine = ScratchAudioEngine(
            samples: SineSweepGenerator.generate(startFrequency: 440, endFrequency: 880, duration: 1.0, sampleRate: 48_000),
            sampleRate: 48_000
        )
        self.totalDuration = DrillTimeline.totalDuration(pattern: pattern)
        self.statuses = pattern.strokes.map { _ in .upcoming }
    }

    func start(modelContext: ModelContext) {
        stop()
        countdownTask = Task {
            for count in stride(from: 3, through: 1, by: -1) {
                phase = .countdown(count)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard !Task.isCancelled else { return }
            beginRun(modelContext: modelContext)
        }
    }

    func stop() {
        countdownTask?.cancel()
        countdownTask = nil
        rotationStream.stop()
        streamTask?.cancel()
        streamTask = nil
        metronome.stop()
        audioEngine.stop()
    }

    private func beginRun(modelContext: ModelContext) {
        phase = .running
        startTimestamp = nil
        elapsedTime = 0
        liveSamples = []
        try? audioEngine.start()
        metronome.start(bpm: pattern.bpm)

        streamTask = Task {
            for await sample in rotationStream.samples() {
                ingest(sample, modelContext: modelContext)
            }
        }
    }

    private func ingest(_ sample: RotationSample, modelContext: ModelContext) {
        if startTimestamp == nil {
            startTimestamp = sample.timestamp
        }
        guard let startTimestamp else { return }
        let elapsed = sample.timestamp - startTimestamp
        elapsedTime = elapsed

        _ = baselineEstimator.ingest(sample.z)
        let corrected = baselineEstimator.correctedVelocity(sample.z)
        let smoothed = velocitySmoother.process(corrected, timestamp: sample.timestamp)
        let reference = BaselineEstimator.angularVelocity(forRPM: BaselineEstimator.rpm33)
        audioEngine.setRate(smoothed / reference)

        liveSamples.append((timestamp: elapsed, velocity: smoothed))
        let strokes = segmenter.segment(liveSamples)
        statuses = DrillScorer.statuses(pattern: pattern, performed: strokes, elapsedTime: elapsed)

        if elapsed >= totalDuration {
            finish(strokes: strokes, modelContext: modelContext)
        }
    }

    private func finish(strokes: [ScratchStroke], modelContext: ModelContext) {
        let result = PatternMatcher.match(pattern: pattern, performed: strokes)
        finalResult = result
        phase = .finished
        stop()

        let record = DrillResult(drillID: pattern.id, date: Date(), overallScore: result.overallScore)
        modelContext.insert(record)
        try? modelContext.save()
    }
}
