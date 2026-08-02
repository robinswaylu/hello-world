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
///
/// Two things keep this responsive as a drill goes on, which it wasn't
/// before:
/// - `GestureSegmenter` is fed incrementally (`ingest`, O(1) per sample)
///   instead of being handed the whole growing sample buffer to rescan
///   from scratch every single sample (O(n) per call, O(n^2) over a
///   session) - that rescan was the main reason things got laggier the
///   longer a drill ran.
/// - The displayed sample history (`liveSamples`) is capped to a rolling
///   window instead of growing for the whole drill, so chart render cost
///   stays constant instead of increasing over time.
///
/// The audio-critical path (rate calculation, `audioEngine.setRate`) and
/// the scoring path (segmentation, judgement detection) still run on every
/// single motion sample (~100Hz) - that precision matters for both how
/// responsive the scratch sounds and how accurately strokes are timed.
/// Only the `@Published` UI-facing properties are throttled, since
/// rendering competes for the same main thread the audio path needs.
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
    private var segmenter = GestureSegmenter()

    private var streamTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var startTimestamp: TimeInterval?
    private let totalDuration: TimeInterval
    private let beatDuration: TimeInterval

    // Full-rate internal state (never throttled) - segmentation and
    // judgement detection both need every sample to stay accurate.
    private var completedStrokes: [ScratchStroke] = []
    private var lastComputedStatuses: [TargetStrokeStatus]

    // Rolling window for the chart display only - bounded regardless of
    // how long the drill runs, unlike the strokes/statuses above which
    // need the drill's full history to score correctly.
    private var rawLiveSamples: [(timestamp: TimeInterval, velocity: Double)] = []
    private let displayWindowSeconds: TimeInterval = 5

    private var uiSampleCounter = 0
    private let uiUpdateStride = 3 // ~33Hz UI refresh at 100Hz capture

    init(pattern: ScratchPattern, rotationStream: RotationStream = RotationStream()) {
        self.pattern = pattern
        self.rotationStream = rotationStream
        self.audioEngine = ScratchAudioEngine(
            samples: ScratchSampleProvider.loadDefaultSample(),
            sampleRate: SampleLibrary.engineSampleRate
        )
        self.totalDuration = DrillTimeline.totalDuration(pattern: pattern)
        self.beatDuration = DrillTimeline.beatDuration(bpm: pattern.bpm)
        let initialStatuses = pattern.strokes.map { _ in TargetStrokeStatus.upcoming }
        self.statuses = initialStatuses
        self.lastComputedStatuses = initialStatuses
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
        rawLiveSamples = []
        segmenter = GestureSegmenter()
        completedStrokes = []
        let initialStatuses = pattern.strokes.map { _ in TargetStrokeStatus.upcoming }
        statuses = initialStatuses
        lastComputedStatuses = initialStatuses
        uiSampleCounter = 0
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
            // Re-detect screen-up/down fresh every attempt from the first
            // sample's gravity reading - see ScratchController.ingest for
            // why this can't just trust a stored value from onboarding.
            CalibrationStore.orientation = OrientationCalibrator.orientation(gravityZ: sample.gravityZ)
        }
        guard let startTimestamp else { return }
        let elapsed = sample.timestamp - startTimestamp

        // Audio-critical: every sample, unthrottled. Never gate this
        // behind anything that could be slow.
        let z = sample.z * CalibrationStore.signMultiplier
        _ = baselineEstimator.ingest(z)
        let corrected = baselineEstimator.correctedVelocity(z)
        let smoothed = velocitySmoother.process(corrected, timestamp: sample.timestamp)
        let reference = BaselineEstimator.angularVelocity(forRPM: BaselineEstimator.rpm33)
        audioEngine.setRate(smoothed / reference)

        // Scoring: also every sample, but O(1) - segmenter.ingest carries
        // its in-progress-stroke state forward instead of rescanning
        // everything performed so far.
        if let completed = segmenter.ingest(timestamp: elapsed, velocity: smoothed) {
            completedStrokes.append(completed)
        }
        let strokes = segmenter.pendingStroke.map { completedStrokes + [$0] } ?? completedStrokes
        let newStatuses = DrillScorer.statuses(pattern: pattern, performed: strokes, elapsedTime: elapsed)
        applyNewJudgements(previous: lastComputedStatuses, current: newStatuses)
        lastComputedStatuses = newStatuses

        rawLiveSamples.append((timestamp: elapsed, velocity: smoothed))
        let cutoff = elapsed - displayWindowSeconds
        while let first = rawLiveSamples.first, first.timestamp < cutoff {
            rawLiveSamples.removeFirst()
        }

        let isFinalSample = elapsed >= totalDuration

        // UI-facing: throttled, since rendering is what's actually
        // expensive here, not the math above.
        uiSampleCounter += 1
        if uiSampleCounter % uiUpdateStride == 0 || isFinalSample {
            elapsedTime = elapsed
            statuses = newStatuses
            liveSamples = rawLiveSamples
        }

        if isFinalSample {
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
