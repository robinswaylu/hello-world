import Foundation
import SwiftData
import UIKit

enum PracticePhase: Equatable {
    case countdown(Int)
    case running
    case finished
}

/// A single stroke's judgement as it happens, tagged with a unique id so
/// the UI can retrigger a popup/haptic even for repeated grades in a row.
struct Judgement: Equatable {
    let grade: StrokeGrade
    let id: UUID
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
    @Published private(set) var streak: Int = 0
    @Published private(set) var bestStreak: Int = 0
    @Published private(set) var latestJudgement: Judgement?

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
    private let beatDuration: TimeInterval

    init(pattern: ScratchPattern, rotationStream: RotationStream = RotationStream()) {
        self.pattern = pattern
        self.rotationStream = rotationStream
        self.audioEngine = ScratchAudioEngine(
            samples: ScratchSampleProvider.loadDefaultSample(),
            sampleRate: SampleLibrary.engineSampleRate
        )
        self.totalDuration = DrillTimeline.totalDuration(pattern: pattern)
        self.beatDuration = DrillTimeline.beatDuration(bpm: pattern.bpm)
        self.statuses = pattern.strokes.map { _ in .upcoming }
    }

    func start(modelContext: ModelContext) {
        stop()
        // Metronome runs through the count-in too, and each countdown step
        // takes one beat, so "3, 2, 1" actually lands on the click instead
        // of an arbitrary fixed second.
        metronome.start(bpm: pattern.bpm)
        UIApplication.shared.isIdleTimerDisabled = true

        countdownTask = Task {
            for count in stride(from: 3, through: 1, by: -1) {
                phase = .countdown(count)
                try? await Task.sleep(nanoseconds: UInt64(beatDuration * 1_000_000_000))
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
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func beginRun(modelContext: ModelContext) {
        phase = .running
        startTimestamp = nil
        elapsedTime = 0
        liveSamples = []
        streak = 0
        bestStreak = 0
        try? audioEngine.start()

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

        let z = sample.z * CalibrationStore.signMultiplier
        _ = baselineEstimator.ingest(z)
        let corrected = baselineEstimator.correctedVelocity(z)
        let smoothed = velocitySmoother.process(corrected, timestamp: sample.timestamp)
        let reference = BaselineEstimator.angularVelocity(forRPM: BaselineEstimator.rpm33)
        audioEngine.setRate(smoothed / reference)

        liveSamples.append((timestamp: elapsed, velocity: smoothed))
        let strokes = segmenter.segment(liveSamples)
        let newStatuses = DrillScorer.statuses(pattern: pattern, performed: strokes, elapsedTime: elapsed)
        applyNewJudgements(previous: statuses, current: newStatuses)
        statuses = newStatuses

        if elapsed >= totalDuration {
            finish(strokes: strokes, modelContext: modelContext)
        }
    }

    /// A target only just now stopped being `.upcoming` - that's the moment
    /// to update the streak and surface a judgement for the UI to react to
    /// (popup text, haptic), rather than re-firing on every sample while it
    /// stays in the same resolved state.
    private func applyNewJudgements(previous: [TargetStrokeStatus], current: [TargetStrokeStatus]) {
        for index in current.indices {
            let previousStatus = index < previous.count ? previous[index] : .upcoming
            guard previousStatus == .upcoming, current[index] != .upcoming else { continue }

            let grade: StrokeGrade
            switch current[index] {
            case .hit(let hitGrade, _): grade = hitGrade
            case .missed: grade = .missed
            case .upcoming: continue
            }

            switch grade {
            case .perfect, .great, .good:
                streak += 1
                bestStreak = max(bestStreak, streak)
            case .poor, .missed:
                streak = 0
            }
            latestJudgement = Judgement(grade: grade, id: UUID())
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
