import SwiftUI
import SwiftData
import Charts

struct PracticeView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var session: PracticeSession

    init(pattern: ScratchPattern) {
        _session = StateObject(wrappedValue: PracticeSession(pattern: pattern))
    }

    var body: some View {
        Group {
            switch session.phase {
            case .countdown(let count):
                Text("\(count)")
                    .font(.system(size: 72, weight: .bold))
            case .running:
                runningContent
            case .finished:
                if let result = session.finalResult {
                    DrillResultView(pattern: session.pattern, result: result)
                }
            }
        }
        .padding()
        .navigationTitle(session.pattern.name)
        .navigationBarBackButtonHidden(session.phase == .running)
        .onAppear { session.start(modelContext: modelContext) }
        .onDisappear { session.stop() }
    }

    private var runningContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(format: "%.1fs elapsed", session.elapsedTime))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            overlayChart
            hitMissSummary
        }
    }

    private var overlayChart: some View {
        let beatDuration = DrillTimeline.beatDuration(bpm: session.pattern.bpm)
        let reference = BaselineEstimator.angularVelocity(forRPM: BaselineEstimator.rpm33)

        return Chart {
            ForEach(Array(zip(session.pattern.strokes, session.statuses).enumerated()), id: \.offset) { _, pair in
                let (stroke, status) = pair
                PointMark(
                    x: .value("Beat", stroke.beatPosition),
                    y: .value("Direction", stroke.direction == .forward ? 1.0 : -1.0)
                )
                .foregroundStyle(color(for: status))
            }
            ForEach(session.liveSamples, id: \.timestamp) { sample in
                LineMark(
                    x: .value("Beat", sample.timestamp / beatDuration),
                    y: .value("Velocity", sample.velocity / reference)
                )
                .foregroundStyle(.gray)
            }
        }
        .chartYScale(domain: -2...2)
        .frame(height: 220)
    }

    private func color(for status: TargetStrokeStatus) -> Color {
        switch status {
        case .upcoming: return Color.gray.opacity(0.4)
        case .hit: return Color.green
        case .missed: return Color.red
        }
    }

    private var hitMissSummary: some View {
        let hits = session.statuses.filter { if case .hit = $0 { return true }; return false }.count
        let misses = session.statuses.filter { if case .missed = $0 { return true }; return false }.count
        let upcoming = session.statuses.count - hits - misses
        return Text("\(hits) hit · \(misses) missed · \(upcoming) upcoming")
            .font(.subheadline)
    }
}
