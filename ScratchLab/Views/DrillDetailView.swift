import SwiftUI
import Charts

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

    private var targetCurveChart: some View {
        Chart(Array(pattern.strokes.enumerated()), id: \.offset) { _, stroke in
            PointMark(
                x: .value("Beat", stroke.beatPosition),
                y: .value("Direction", stroke.direction == .forward ? 1.0 : -1.0)
            )
            .foregroundStyle(stroke.direction == .forward ? Color.blue : Color.purple)
        }
        .chartYScale(domain: -1.5...1.5)
        .chartYAxisLabel("forward / back")
        .frame(height: 160)
    }
}
