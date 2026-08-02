import SwiftUI
import SwiftData
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

    // A Swift Charts `Chart` used to draw this, re-diffed at ~33Hz - an
    // Instruments trace during a laggy drill showed the framework's
    // internal generic value-witness machinery (swift_retain/release,
    // multiPayloadEnum init/copy/destroy, ClosedRange<>.Index copies) was
    // responsible for the majority of all sampled CPU time, dwarfing
    // everything in this app's own code combined. That overhead comes from
    // Charts building/diffing a declarative view per mark per frame - it's
    // inherent to the framework, not fixable by optimizing our own scoring
    // or segmentation code (which is why none of those earlier fixes, or
    // switching Debug/Release, changed the laggy feel at all). A `Canvas`
    // draws the same picture by stroking/filling paths directly against a
    // `GraphicsContext` with no per-datapoint view objects at all, so this
    // is a straight, immediate-mode redraw instead of a view-tree diff.
    private var overlayChart: some View {
        let beatDuration = DrillTimeline.beatDuration(bpm: session.pattern.bpm)
        let reference = BaselineEstimator.angularVelocity(forRPM: BaselineEstimator.rpm33)
        let totalBeats = max(DrillTimeline.totalDuration(pattern: session.pattern) / beatDuration, 1)
        let targets = Array(zip(session.pattern.strokes, session.statuses))
        let liveSamples = session.liveSamples

        func xPosition(beat: Double, width: CGFloat) -> CGFloat {
            CGFloat(beat / totalBeats) * width
        }
        func yPosition(value: Double, height: CGFloat) -> CGFloat {
            let clamped = min(max(value, -2), 2)
            return height * (1 - CGFloat((clamped + 2) / 4))
        }

        return Canvas { context, size in
            if liveSamples.count > 1 {
                var path = Path()
                for (index, sample) in liveSamples.enumerated() {
                    let point = CGPoint(
                        x: xPosition(beat: sample.timestamp / beatDuration, width: size.width),
                        y: yPosition(value: sample.velocity / reference, height: size.height)
                    )
                    if index == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
                context.stroke(path, with: .color(.gray), lineWidth: 1.5)
            }

            for (stroke, status) in targets {
                let center = CGPoint(
                    x: xPosition(beat: stroke.beatPosition, width: size.width),
                    y: yPosition(value: stroke.direction == .forward ? 1.0 : -1.0, height: size.height)
                )
                let dot = CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: dot), with: .color(color(for: status)))
            }
        }
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
