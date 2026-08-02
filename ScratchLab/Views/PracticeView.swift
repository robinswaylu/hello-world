import SwiftUI
import SwiftData
import Charts
import UIKit

struct PracticeView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var session: PracticeSession
    @AppStorage("hapticsEnabled") private var hapticsEnabled = false
    @State private var popupJudgement: Judgement?
    @State private var streakPulse = false

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
        .onChange(of: session.latestJudgement) { _, newValue in
            handleNewJudgement(newValue)
        }
        .onChange(of: session.streak) { _, _ in
            pulseStreak()
        }
        .overlay(alignment: .top) {
            if let popupJudgement {
                Text(label(for: popupJudgement.grade))
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(color(forGrade: popupJudgement.grade))
                    .shadow(radius: 4)
                    .padding(.top, 24)
                    .transition(.scale(scale: 1.4).combined(with: .opacity))
                    .id(popupJudgement.id)
            }
        }
    }

    @MainActor
    private func handleNewJudgement(_ judgement: Judgement?) {
        guard let judgement else { return }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) {
            popupJudgement = judgement
        }
        let id = judgement.id
        Task {
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard popupJudgement?.id == id else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                popupJudgement = nil
            }
        }

        guard hapticsEnabled else { return }
        switch judgement.grade {
        case .perfect, .great:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .good:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .poor, .missed:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    @MainActor
    private func pulseStreak() {
        guard session.streak > 0 else { return }
        streakPulse = true
        Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            streakPulse = false
        }
    }

    private var runningContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(String(format: "%.1fs elapsed", session.elapsedTime))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                streakBadge
            }
            overlayChart
            hitMissSummary
        }
    }

    private var streakBadge: some View {
        HStack(spacing: 4) {
            Text("\(session.streak)")
                .font(.system(size: 22, weight: .black, design: .rounded))
            Text("streak")
                .font(.caption)
        }
        .foregroundStyle(session.streak > 0 ? Color.orange : Color.secondary)
        .scaleEffect(streakPulse ? 1.3 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.4), value: streakPulse)
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
        case .hit(let grade, _): return color(forGrade: grade)
        case .missed: return color(forGrade: .missed)
        }
    }

    private func color(forGrade grade: StrokeGrade) -> Color {
        switch grade {
        case .perfect: return Color.yellow
        case .great: return Color.green
        case .good: return Color.cyan
        case .poor: return Color.orange
        case .missed: return Color.red
        }
    }

    private func label(for grade: StrokeGrade) -> String {
        switch grade {
        case .perfect: return "PERFECT!"
        case .great: return "GREAT"
        case .good: return "GOOD"
        case .poor: return "POOR"
        case .missed: return "MISSED"
        }
    }

    private var hitMissSummary: some View {
        var counts: [StrokeGrade: Int] = [:]
        for status in session.statuses {
            switch status {
            case .hit(let grade, _): counts[grade, default: 0] += 1
            case .missed: counts[.missed, default: 0] += 1
            case .upcoming: break
            }
        }
        let upcoming = session.statuses.count - counts.values.reduce(0, +)

        return Text("Perfect \(counts[.perfect] ?? 0) · Great \(counts[.great] ?? 0) · Good \(counts[.good] ?? 0) · Poor \(counts[.poor] ?? 0) · Missed \(counts[.missed] ?? 0) · \(upcoming) upcoming")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
