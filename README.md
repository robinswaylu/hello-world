# ScratchLab

An iOS app that turns an iPhone into a self-contained scratch-DJ training
instrument. See the full product spec for the complete phase plan.

This repo currently contains:

- **Phase 0**: the validation harness used to confirm the physical
  assumptions (gyro headroom, achievable sample rate, audio latency) before
  the rest of the app is built. On-device testing confirmed a clean ~100Hz
  sample rate, a near-zero motor-off baseline, and no gyro clipping even
  under aggressive scratch strokes (peak observed: ~824°/s, well under the
  gyro's ±2000°/s range).
- **Phase 1**: the pure-Swift rotation signal core (`ScratchLab/Core/`) —
  platter-state detection, velocity smoothing, stroke segmentation, and
  pattern scoring — unit-tested including against a real captured scratch
  burst from Phase 0 testing.
- **Phase 2**: the scratch audio engine (`ScratchLab/Audio/`) — a custom
  `AVAudioSourceNode` read-head that plays a sample forward/reverse at
  whatever rate Phase 1's signal core reports, with a loop crossfade to
  avoid clicks and a Bluetooth-route warning. This is the new default
  **Scratch** tab; Phase 0's harness is still there under **Diagnostics**.
- **Phase 3**: the drill player (`ScratchLab/Drill/`) — a **Drills** tab
  listing built-in `ScratchPattern`s (baby scratch at 80 and 120 BPM),
  a detail screen with a target-pattern chart and an audio preview, and
  a practice mode: countdown → live capture/audio/metronome → a
  Guitar-Hero-style overlay chart (target strokes vs. your live velocity
  curve) with live hit/miss status → an end screen with a per-stroke score
  breakdown, using Phase 1's `PatternMatcher`. Results persist via
  SwiftData so the drill list shows your best score per drill.
- **Phase 4**: content & polish. Built-in drills (see below for the current
  set); a first-launch
  onboarding flow (placement guide → a real orientation calibration step →
  audio-route check); haptic feedback on drill hit/miss, off by default
  because the phone sits on the platter during capture and vibration
  pollutes the gyro (toggle + explanation under Diagnostics); the screen
  no longer auto-locks during a drill; dark-mode-first; and a generated
  placeholder app icon.

  The calibration step is a real fix, not just onboarding UI: without it,
  a screen-down placement would read every scratch backwards (`gravity.z`
  determines screen-up vs. screen-down, per `OrientationCalibrator`), and
  the spec explicitly calls out handling that "via a calibration step, not
  assumptions."
- **Real sample content**: `ScratchLab/Sounds/scratch-sentence.wav`
  (licensed for this use) is now the engine's default scratch voice,
  loaded and converted to mono at the engine's sample rate via
  `SampleLibrary`/`AVAudioConverter`. The programmatic sine sweep
  (`SineSweepGenerator`) is kept as an automatic fallback if the bundled
  sample ever fails to load, so the engine is never silent.
- **Practice feel pass**, after watching a real recorded attempt surface
  several issues:
  - **Forward/backward were inverted.** Positive raw gyro Z (screen-up) is
    counterclockwise-from-above, which is *backward* on a real turntable
    (records spin clockwise from above during normal playback) —
    `OrientationCalibrator`'s sign convention was backwards. Fixed; this
    affects both scratch audio direction and stroke-direction scoring.
  - **Scoring was too generous.** A stroke with perfect timing but the
    *wrong direction* used to still score 70/100. Direction is now a gate,
    not a bonus — wrong direction caps a stroke at `.poor` regardless of
    timing. Correct-direction strokes are graded in rhythm-game-style bands
    (`StrokeGrade`: perfect/great/good/poor) instead of one linear scale,
    so a true, reachable 100 only happens within a tight timing window.
  - **Live judgement, streaks, haptics.** Each stroke now pops a
    PERFECT!/GREAT/GOOD/POOR/MISSED judgement the instant it's graded, a
    streak counter pulses on every consecutive good-enough hit and resets
    on a poor/missed one, and haptic feedback (still off by default) is
    graded too — a firm tap for perfect/great, lighter for good, an error
    buzz for poor/missed.
  - **Metronome now runs through the 3-2-1 countdown**, one beat per
    count, so the count-in is actually musical instead of a silent
    generic 3-second wait before the click starts.
  - **The drill preview sounded like fast-forward/rewind**, not a scratch
    — it held a constant rate for each stroke's whole duration.
    `DrillPreviewPlayer` now ramps each stroke through a half-sine
    velocity envelope (0 → peak → 0), mimicking a real hand's
    accelerate-decelerate motion.
  - **Drill list trimmed** to just the baby scratch family (80/90/120 BPM)
    while this feel is being tuned; drag/scribble/release-timing/tempo
    ladder will come back once it's right.
- **Follow-up fixes**, after testing the pass above surfaced two more
  real bugs:
  - **Direction was still reversed.** The sign fix above only changed the
    *code* that computes the calibration multiplier — it didn't touch an
    *already-stored* calibration value from before the fix, and since
    onboarding had already been completed, the app never re-prompted for
    it. `CalibrationStore` now persists the detected *orientation*
    (screen-up/down), not a derived sign number, and `ScratchController`/
    `PracticeSession` both auto-detect orientation fresh from the first
    sample's gravity reading at the start of every session — no stale
    calibration is possible anymore, and no manual recalibration is
    needed after a future sign-convention fix either.
  - **Practice mode had noticeable audio lag.** `PracticeSession` was
    publishing the growing sample history and recomputing scoring state
    on every single ~100Hz motion sample, all on the main thread — same
    thread `audioEngine.setRate()` needs promptly. Expensive chart/
    animation rendering could delay that call, making the scratch sound
    audibly lag behind the hand motion driving it. The audio and scoring
    math still run at full rate (that precision matters), but the
    `@Published` UI-facing state is now throttled and decimated to
    ~33Hz, cutting how much rendering work competes with the real-time
    audio path.
- **The real lag fix.** Throttling helped but didn't fix it — lag still
  built up over a drill and got worse the faster you scratched, which is
  the signature of a cost that *grows*, not a fixed one. The actual bug:
  `GestureSegmenter.segment()` rescanned the *entire* sample buffer from
  scratch on every single 100Hz sample — O(n) per call, O(n²) over a
  whole drill, so it got measurably slower the longer a drill ran (and
  the more strokes there were to rescan past). `GestureSegmenter` is now
  genuinely incremental: `ingest(timestamp:velocity:)` carries the
  in-progress stroke's state across calls in O(1), so per-sample cost is
  now constant regardless of how far into a drill you are (`segment(_:)`
  is kept as a one-shot convenience for tests/offline analysis, not for
  live capture). The displayed chart history is also now a rolling
  5-second window instead of the whole drill's growing history, so
  render cost stays flat too. This should also make the "grading feels
  laggy/inaccurate" complaint better, not just the audio: the same
  main-thread congestion was delaying the timestamps scoring relies on.

## Requirements

- Xcode 15 or newer
- iOS 17+ deployment target
- A physical iPhone (the simulator has no gyroscope) — Phase 0 must be run
  on real hardware, on a real turntable

## Build & Run

1. Open `ScratchLab.xcodeproj` in Xcode.
2. Select your iPhone as the run destination.
3. Under the target's Signing & Capabilities tab, set your own Team so the
   app can be signed (the placeholder bundle identifier is
   `com.scratchlab.ScratchLab` — change it if it collides with anything in
   your account).
4. Run (`Cmd+R`).

## Using the Phase 2 scratch demo

1. Open the app to the **Scratch** tab (the default).
2. If a Bluetooth output is connected you'll see a warning — switch to
   wired headphones or a speaker; BT's 100-200ms lag makes scratching feel
   broken.
3. Place the phone flat (screen up) on a record on a turntable, or a
   motor-off jog wheel.
4. Move the platter/jog by hand — you should hear the placeholder sine
   sweep scratch forward and reverse in sync with the motion, with no
   clicking at the sample's loop point and no zippering on smooth moves.
5. The readout shows the detected platter state (`motorOff`/`rpm33`/`rpm45`/
   `unknown`) and the current playback rate ratio.

## Using the Phase 3 drill player

1. Switch to the **Drills** tab. Currently just the baby scratch family:
   80/90/120 BPM.
2. Tap a drill to open its detail screen. Tap **Preview** to hear a demo
   of the target pattern (a real accelerate/decelerate scratch stroke per
   target, not just a tone).
3. Tap **Start Practice**. A metronome starts immediately and a 3-2-1
   countdown runs one beat per count, then the drill auto-starts: live
   audio scratches as you move the platter (same engine as the Scratch
   tab), and the chart shows target strokes colored by grade (gray =
   upcoming, yellow = perfect, green = great, cyan = good, orange = poor,
   red = missed) with your live velocity curve overlaid. Each stroke pops
   a judgement (PERFECT!/GREAT/GOOD/POOR/MISSED) the instant it's graded,
   and a streak counter tracks consecutive good-enough hits.
4. The drill auto-stops once its bars are up and shows a score breakdown
   with a grade per stroke. Backing out and reopening the drill shows your
   best score in the list.

## First launch (onboarding)

On first launch you'll get a 3-step flow instead of the main tabs:

1. **Placement guide** — how to sit the phone on the record.
2. **Calibration** — place the phone as you'll actually use it and tap
   Calibrate; it samples the gravity vector for ~0.3s to detect screen-up
   vs. screen-down and stores a sign correction. Re-run this any time from
   Diagnostics → **Re-run Onboarding / Recalibrate** (e.g. if you switch
   from screen-up to screen-down placement).
3. **Audio route check** — warns if Bluetooth is connected.

## Using the Phase 0 harness

1. Switch to the **Diagnostics** tab. Place the phone flat (screen up) on a record on a turntable.
2. Tap **Start Capture**. Spin the platter at 33⅓ and 45 RPM, then try some
   aggressive scratch strokes by hand.
3. Watch the live readout and chart for:
   - a clean, steady baseline at each speed
   - the clipping counter staying at 0 during normal play (clipping means the
     gyro maxed out on a fast stroke)
   - the achieved sample rate (should be close to 100 Hz on most devices)
4. Toggle **Audio latency probe** to hear a click whenever velocity crosses
   a threshold — use this to judge how much lag there is between the motion
   and the sound. Prefer wired audio output for this test; Bluetooth adds
   100–200ms of its own latency.
5. Tap **Export Session CSV** to share out the raw `timestamp,x,y,z` samples
   for later analysis (e.g. as Phase 1 test fixtures).

## Running unit tests

`Cmd+U` runs `ScratchLabTests`, which covers:

- Phase 0 logic: CSV formatting, unit conversion, clipping threshold math
- Phase 1 logic: platter-state locking, velocity smoothing, stroke
  segmentation (including a real captured scratch burst), and pattern
  scoring
- Phase 2 logic: the read-head's forward/reverse/fractional-rate math,
  rate ramping (the anti-zipper mechanism), loop crossfading, and the
  placeholder sine sweep generator
- Phase 3 logic: beat-grid timing math and live hit/upcoming/missed status
  derivation (`DrillTimeline`, `DrillScorer`)
- Phase 4 logic: screen-up/down orientation detection from the gravity
  vector (`OrientationCalibrator`)

None of this requires a device — it's all pure Swift over synthetic and
recorded data. (The AVAudioEngine/Core Motion/AVAudioSession/SwiftData
glue that wraps this logic — `RotationStream`, `ScratchAudioEngine`,
`BluetoothRouteMonitor`, `Metronome`, `PracticeSession` — is device-only
and isn't unit tested; it's thin wrapping around the tested core.)

## Project layout

```
ScratchLab/
  ScratchLabApp.swift        App entry point
  Models/
    GyroSample.swift         One motion sample + unit conversions
    Direction.swift          forward/back
    ScratchPattern.swift     ScratchPattern + TargetStroke (drill data model)
  Motion/MotionMonitor.swift Phase 0's Core Motion capture + session stats
  Core/                      Phase 1 rotation signal core
    RotationSample.swift     Z-only timestamped sample
    RotationStream.swift     Core Motion -> AsyncStream<RotationSample>
    BaselineEstimator.swift  33/45/motor-off detection + bias re-zeroing
    VelocitySmoother.swift   Low-pass + slew limiting for the audio engine
    GestureSegmenter.swift   Splits a velocity stream into ScratchStrokes
    PatternMatcher.swift     Scores performed strokes against a ScratchPattern (StrokeGrade)
    ReadHead.swift           Phase 2's fractional read-head + rate ramping
    LoopCrossfader.swift     Bakes a click-free crossfade into the loop point
    SineSweepGenerator.swift Placeholder tone generator
    DrillTimeline.swift      Beat grid -> wall-clock seconds
    DrillScorer.swift        Live hit/upcoming/missed status per target stroke
    OrientationCalibrator.swift  Screen-up/down detection from gravity.z
  Audio/
    LatencyClickPlayer.swift    Phase 0's click-on-threshold probe
    ScratchAudioEngine.swift    AVAudioSourceNode wrapping ReadHead
    BluetoothRouteMonitor.swift Detects BT output, drives the warning
    ScratchController.swift     Wires Core Motion -> Phase 1 -> ScratchAudioEngine
    Metronome.swift             Beat click during practice
    DrillPreviewPlayer.swift    Rough audio preview of a drill's target pattern
    SampleLibrary.swift         Loads/converts bundled audio -> mono Float32
  Drill/
    BuiltInDrills.swift      Built-in ScratchPattern content (baby scratch family)
    DrillResult.swift        SwiftData @Model for persisted scores
    PracticeSession.swift    Countdown -> live capture/scoring -> persistence
    CalibrationStore.swift   Persists the calibration sign correction
  Sounds/scratch-sentence.wav     The real scratch sample (licensed)
  Utilities/CSVExporter.swift     CSV formatting + temp-file export
  Views/                     Phase0View, Phase2View, VelocityChartView, ShareSheet,
                             DrillListView, DrillDetailView, PracticeView,
                             DrillResultView, OnboardingView
ScratchLabTests/             Unit tests for the pure-Swift pieces
```
