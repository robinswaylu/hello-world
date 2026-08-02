# ScratchLab

An iOS app that turns an iPhone into a self-contained scratch-DJ training
instrument. See the full product spec for the complete phase plan.

This repo currently contains **Phase 0**: the validation harness used to
confirm the physical assumptions (gyro headroom, achievable sample rate,
audio latency) before the rest of the app is built.

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

## Using the Phase 0 harness

1. Place the phone flat (screen up) on a record on a turntable.
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

`Cmd+U` runs `ScratchLabTests`, which covers the pure-Swift logic
(CSV formatting, unit conversion, clipping threshold math) that doesn't
require a device.

## Project layout

```
ScratchLab/
  ScratchLabApp.swift        App entry point
  Models/GyroSample.swift    One motion sample + unit conversions
  Motion/MotionMonitor.swift Core Motion capture + session stats
  Audio/LatencyClickPlayer.swift  AVAudioEngine click-on-threshold probe
  Utilities/CSVExporter.swift     CSV formatting + temp-file export
  Views/                     Phase0View, VelocityChartView, ShareSheet
ScratchLabTests/             Unit tests for the pure-Swift pieces
```
