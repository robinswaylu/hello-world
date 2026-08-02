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
    @Published private(set) var finalDiagnosis: TimingDiagnosis?
    @Published private(set) var streak: Int = 0
    @Published private(set) var bestStreak: Int = 0
    @Published private(set) var latestJudgement: Judgement?
    @Published private(set) var beatTick: Int = 0
    @Published private(set) var isDownbeatTick: Bool = true

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
    //
    // Two stroke lists, not one: `allCompletedStrokes` is the complete,
    // unbounded history, needed once at the end for the final score.
    // `recentCompletedStrokes` is a time-bounded window used for the live
    // per-sample matching instead - real gyro noise near the segmenter's
    // thresholds can register far more strokes than a pattern's target
    // count, and PatternMatcher's cost scales with how many performed
    // strokes it searches, so an ever-growing candidate pool is exactly
    // why full re-matches (whenever one does fire) kept getting slower
    // over the course of a drill. A stroke more than a couple hundred ms
    // stale can never match any *future* target anyway (targets are
    // spaced well under a second apart with a tight tolerance window), so
    // dropping old, aged-out candidates from the live search pool can't
    // change any matching outcome - only bound the work involved in it.
    private var allCompletedStrokes: [ScratchStroke] = []
    private var recentCompletedStrokes: [ScratchStroke] = []
    private let strokeRetentionSeconds: TimeInterval = 3
    private var lastComputedStatuses: [TargetStrokeStatus]
    private var hasCalibratedThisRun = false

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

        // One anchor for the click, the count-in, and the scoring grid.
        //
        // This is what actually phase-locks the metronome to the targets.
        // The grid used to start from whenever CoreMotion's first sample
        // happened to arrive after the countdown, while the click started
        // when this method was called - two independent anchors separated
        // by the count-in, `audioEngine.start()`, and CoreMotion's spin-up
        // time, none of it measured. Whatever that gap came out to on a
        // given run became a fixed offset applied to every target in the
        // drill, so "play exactly on the click" didn't reliably score
        // well. CMDeviceMotion timestamps share systemUptime's base, so a
        // grid start expressed in this clock is directly comparable to
        // them.
        // Activate the session before anything else so the latency read
        // below is valid - it reports 0 on an inactive session.
        AudioSessionSetup.activate()
        let outputLatency = AudioSessionSetup.outputLatency

        // `anchor` is when tick 0 is *scheduled*; `heardAnchor` is when it
        // actually reaches the player's ears. Everything the player reacts
        // to - the clicks, the countdown - is on the heard timeline, and
        // their motion follows what they hear, so the scoring grid has to
        // sit on that timeline too. Gyro timestamps carry no such delay,
        // so without this offset a player following the click perfectly
        // reads as systematically late by the whole output latency: a
        // grading band on wired output, two or more over Bluetooth.
        let anchor = ProcessInfo.processInfo.systemUptime
        let heardAnchor = anchor + outputLatency
        let runStart = heardAnchor + Double(Self.countdownBeats) * beatDuration

        // onTick fires from the metronome's own tick loop, not the main
        // actor, so the visual pulse this drives has to hop back.
        metronome.onTick = { [weak self] isDownbeat in
            Task { @MainActor in
                self?.beatTick += 1
                self?.isDownbeatTick = isDownbeat
            }
        }
        // Subdivide to the drill's own stroke spacing so every stroke has
        // a click, whether it's on eighths or double-time sixteenths.
        let subdivisionsPerBeat = Int((1.0 / PerfectRunCurve.gapBeats(for: pattern)).rounded())
        metronome.start(bpm: pattern.bpm, anchor: anchor, subdivisionsPerBeat: subdivisionsPerBeat)
        UIApplication.shared.isIdleTimerDisabled = true

        countdownTask = Task {
            for count in stride(from: Self.countdownBeats, through: 1, by: -1) {
                phase = .countdown(count)
                // Absolute deadline per step, same reason as the
                // metronome's: chained fixed sleeps accumulate their own
                // overhead and would walk the count-in off the click.
                let due = anchor + Double(Self.countdownBeats - count + 1) * beatDuration
                let delay = due - ProcessInfo.processInfo.systemUptime
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
            guard !Task.isCancelled else { return }
            beginRun(modelContext: modelContext, runStart: runStart)
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

    /// Beats of "3, 2, 1" count-in before the drill's own timeline starts.
    private static let countdownBeats = 3

    private func beginRun(modelContext: ModelContext, runStart: TimeInterval) {
        phase = .running
        // Fixed up front from the shared anchor rather than taken from the
        // first sample to arrive, so CoreMotion's spin-up latency can't
        // shift the whole grid off the click. The empty lead-in bar gives
        // capture four beats of margin to be running by the time the first
        // target is due.
        startTimestamp = runStart
        hasCalibratedThisRun = false
        elapsedTime = 0
        liveSamples = []
        rawLiveSamples = []
        segmenter = GestureSegmenter()
        allCompletedStrokes = []
        recentCompletedStrokes = []
        let initialStatuses = pattern.strokes.map { _ in TargetStrokeStatus.upcoming }
        statuses = initialStatuses
        lastComputedStatuses = initialStatuses
        uiSampleCounter = 0
        streak = 0
        bestStreak = 0
        latestJudgement = nil // clear the previous attempt's popup trigger, if replaying
        try? audioEngine.start()

        streamTask = Task {
            for await sample in rotationStream.samples() {
                ingest(sample, modelContext: modelContext)
            }
        }
    }

    private func ingest(_ sample: RotationSample, modelContext: ModelContext) {
        // The stream's AsyncStream can have samples already buffered past the
        // moment `finish()` first fires - `stop()` calls `continuation.finish()`,
        // which stops *new* samples from being added but still drains whatever
        // was already queued. Without this guard, every one of those leftover
        // buffered samples would re-run the full ingest pipeline (and, since
        // elapsed only grows, re-trigger `isFinalSample` and call `finish()`
        // again) after the drill already ended - wasted CPU at best, and at
        // worst a duplicate `DrillResult` insert per leftover sample.
        guard phase == .running else { return }
        if !hasCalibratedThisRun {
            hasCalibratedThisRun = true
            // Re-detect screen-up/down fresh every attempt from the first
            // sample's gravity reading - see ScratchController.ingest for
            // why this can't just trust a stored value from onboarding.
            // (Only the calibration keys off the first sample now; the
            // grid's start time comes from the shared anchor instead.)
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
        var performedDidChange = false
        if let completed = segmenter.ingest(timestamp: elapsed, velocity: smoothed) {
            allCompletedStrokes.append(completed)
            recentCompletedStrokes.append(completed)
            let strokeCutoff = elapsed - strokeRetentionSeconds
            recentCompletedStrokes.removeAll { $0.startTime < strokeCutoff }
            performedDidChange = true
        }
        // Only *completed* strokes are graded live. Including the
        // in-progress stroke here meant a target got graded the moment a
        // stroke started overlapping it, using whatever fraction of the
        // peak velocity had happened so far - which amplitude grading
        // reads as a badly under-powered stroke and scores Poor. And
        // because a resolved status is never re-graded, that early wrong
        // grade stuck: the popup said POOR and the streak reset, while
        // the result screen (which scores completed strokes) showed the
        // real, much better grade for the same stroke. A stroke's peak
        // isn't knowable until it's over, so the judgement now waits.

        // Which strokes have been performed only changes a couple dozen
        // times over a whole drill - re-running PatternMatcher's full,
        // allocating match on every single ~100Hz sample regardless was
        // the actual scoring-lag bug. Skip straight to the cheap
        // upcoming/missed time check on samples where nothing changed.
        let newStatuses = DrillScorer.statuses(previous: lastComputedStatuses, pattern: pattern, performed: recentCompletedStrokes, elapsedTime: elapsed, performedDidChange: performedDidChange)
        applyNewJudgements(previous: lastComputedStatuses, current: newStatuses)
        lastComputedStatuses = newStatuses

        let isFinalSample = elapsed >= totalDuration

        // UI-facing: throttled, since rendering is what's actually
        // expensive here, not the math above. `rawLiveSamples` itself is
        // now only touched on this same throttled cadence too - it used to
        // be appended/pruned every single 100Hz sample even though it's
        // only ever displayed at ~33Hz, which meant Swift Charts was
        // re-rendering up to ~500 line points a frame (a real, sustained
        // per-frame cost) when only ~167 of them were ever shown, and
        // `removeFirst()` was shifting a ~500-element array 100 times a
        // second to boot. Deciding at the throttled rate instead cuts both
        // the bookkeeping and the on-screen point count by ~3x for free -
        // the in-between samples were never visible anyway.
        uiSampleCounter += 1
        if uiSampleCounter % uiUpdateStride == 0 || isFinalSample {
            rawLiveSamples.append((timestamp: elapsed, velocity: smoothed))
            let cutoff = elapsed - displayWindowSeconds
            while let first = rawLiveSamples.first, first.timestamp < cutoff {
                rawLiveSamples.removeFirst()
            }

            elapsedTime = elapsed
            statuses = newStatuses
            liveSamples = rawLiveSamples
        }

        if isFinalSample {
            // The final score uses the complete, unbounded history - not
            // the time-bounded recentCompletedStrokes used for live
            // matching above. A stroke still in progress when the drill
            // ends is included: its peak is only partial, but counting it
            // under-powered beats dropping it entirely and scoring the
            // last target as a miss.
            let pending = segmenter.pendingStroke
            let finalStrokes = pending.map { allCompletedStrokes + [$0] } ?? allCompletedStrokes
            finish(strokes: finalStrokes, modelContext: modelContext)
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
        finalDiagnosis = TimingDiagnosis.analyze(pattern: pattern, strokes: strokes, result: result)
        phase = .finished
        stop()

        let record = DrillResult(drillID: pattern.id, date: Date(), overallScore: result.overallScore)
        modelContext.insert(record)
        try? modelContext.save()
    }
}
