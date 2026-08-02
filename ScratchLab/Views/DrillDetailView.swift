import SwiftUI

struct DrillDetailView: View {
    let pattern: ScratchPattern
    @StateObject private var previewPlayer: DrillPreviewPlayer

    init(pattern: ScratchPattern) {
        self.pattern = pattern
        _previewPlayer = StateObject(wrappedValue: DrillPreviewPlayer(pattern: pattern))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pattern.name).font(.title2.bold())
                    Text("\(Int(pattern.bpm)) BPM · \(pattern.bars) bars · \(pattern.strokes.count) strokes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                targetCurveChart

                Button(previewPlayer.isPlaying ? "Stop Preview" : "Preview") {
                    if previewPlayer.isPlaying {
                        previewPlayer.stop()
                    } else {
                        previewPlayer.play()
                    }
                }
                .buttonStyle(.bordered)

                NavigationLink("Start Practice") {
                    PracticeView(pattern: pattern)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle(pattern.name)
        .onDisappear { previewPlayer.stop() }
    }

    /// The same reference perfect run the practice chart draws behind your
    /// live trace, shown here at full opacity so it can be studied before
    /// starting: every target on time, in the right direction, peaking
    /// exactly at its dot.
    private var targetCurveChart: some View {
        let totalBeats: Double = max(DrillTimeline.totalDuration(pattern: pattern) / DrillTimeline.beatDuration(bpm: pattern.bpm), 1)
        let perfectRun = PerfectRunCurve.points(for: pattern)
        let strokes = pattern.strokes

        func xPosition(beat: Double, width: CGFloat) -> CGFloat {
            CGFloat(beat / totalBeats) * width
        }
        func yPosition(value: Double, height: CGFloat) -> CGFloat {
            let clamped = min(max(value, -1.5), 1.5)
            return height * (1 - CGFloat((clamped + 1.5) / 3))
        }

        return VStack(alignment: .leading, spacing: 6) {
            Canvas { context, size in
                var midline = Path()
                midline.move(to: CGPoint(x: 0, y: yPosition(value: 0, height: size.height)))
                midline.addLine(to: CGPoint(x: size.width, y: yPosition(value: 0, height: size.height)))
                context.stroke(midline, with: .color(.gray.opacity(0.3)), lineWidth: 1)

                if perfectRun.count > 1 {
                    var curve = Path()
                    for (index, point) in perfectRun.enumerated() {
                        let position = CGPoint(
                            x: xPosition(beat: point.beat, width: size.width),
                            y: yPosition(value: point.normalizedVelocity, height: size.height)
                        )
                        if index == 0 {
                            curve.move(to: position)
                        } else {
                            curve.addLine(to: position)
                        }
                    }
                    context.stroke(curve, with: .color(.teal), lineWidth: 1.5)
                }

                for stroke in strokes {
                    let center = CGPoint(
                        x: xPosition(beat: stroke.beatPosition, width: size.width),
                        y: yPosition(value: stroke.direction == .forward ? 1.0 : -1.0, height: size.height)
                    )
                    let dot = CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
                    let color: Color = stroke.direction == .forward ? .blue : .purple
                    context.fill(Path(ellipseIn: dot), with: .color(color))
                }
            }
            .frame(height: 160)

            Text("A perfect run — up = forward, down = back. Each peak reaches its dot.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
