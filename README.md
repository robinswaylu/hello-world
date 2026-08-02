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
  avoid clicks and a Bluetooth-route warning. Ships with a generated
  440→880Hz sine sweep as the placeholder tone (real licensed scratch
  samples are a follow-up content task, not something this repo can
  source on its own). This is the new default **Scratch** tab; Phase 0's
  harness is still there under **Diagnostics**.
- **Phase 3**: the drill player (`ScratchLab/Drill/`) — a **Drills** tab
  listing built-in `ScratchPattern`s (baby scratch at 80 and 120 BPM),
  a detail screen with a target-pattern chart and an audio preview, and
  a practice mode: countdown → live capture/audio/metronome → a
  Guitar-Hero-style overlay chart (target strokes vs. your live velocity
  curve) with live hit/miss status → an end screen with a per-stroke score
  breakdown, using Phase 1's `PatternMatcher`. Results persist via
  SwiftData so the drill list shows your best score per drill.

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

1. Switch to the **Drills** tab.
2. Tap a drill (e.g. "Baby Scratch (80 BPM)") to open its detail screen.
   Tap **Preview** to hear a rough demo of the target pattern.
3. Tap **Start Practice**. A 3-2-1 countdown runs, then the drill
   auto-starts: a metronome click keeps time, live audio scratches as you
   move the platter (same engine as the Scratch tab), and the chart shows
   target strokes (gray = upcoming, green = hit, red = missed) with your
   live velocity curve overlaid.
4. The drill auto-stops once its bars are up and shows a score breakdown.
   Backing out and reopening the drill shows your best score in the list.

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
    PatternMatcher.swift     Scores performed strokes against a ScratchPattern
    ReadHead.swift           Phase 2's fractional read-head + rate ramping
    LoopCrossfader.swift     Bakes a click-free crossfade into the loop point
    SineSweepGenerator.swift Placeholder tone generator
    DrillTimeline.swift      Beat grid -> wall-clock seconds
    DrillScorer.swift        Live hit/upcoming/missed status per target stroke
  Audio/
    LatencyClickPlayer.swift    Phase 0's click-on-threshold probe
    ScratchAudioEngine.swift    AVAudioSourceNode wrapping ReadHead
    BluetoothRouteMonitor.swift Detects BT output, drives the warning
    ScratchController.swift     Wires Core Motion -> Phase 1 -> ScratchAudioEngine
    Metronome.swift             Beat click during practice
    DrillPreviewPlayer.swift    Rough audio preview of a drill's target pattern
  Drill/
    BuiltInDrills.swift      Built-in ScratchPattern content
    DrillResult.swift        SwiftData @Model for persisted scores
    PracticeSession.swift    Countdown -> live capture/scoring -> persistence
  Utilities/CSVExporter.swift     CSV formatting + temp-file export
  Views/                     Phase0View, Phase2View, VelocityChartView, ShareSheet,
                             DrillListView, DrillDetailView, PracticeView, DrillResultView
ScratchLabTests/             Unit tests for the pure-Swift pieces
```
