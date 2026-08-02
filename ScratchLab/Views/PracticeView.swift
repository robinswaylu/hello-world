import SwiftUI
import SwiftData
import UIKit

struct PracticeView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var session: PracticeSession
    @AppStorage("hapticsEnabled") private var hapticsEnabled = false
    @State private var popupJudgement: Judgement?
    @State private var streakPulse = false
    @State private var metronomeLit = false

    init(pattern: ScratchPattern) {
        _session = StateObject(wrappedValue: PracticeSession(pattern: pattern))
    }

    var body: some View {
        Group {
            switch session.phase {
            case .countdown(let count):
                VStack(spacing: 20) {
                    Text("\(count)")
                        .font(.system(size: 72, weight: .bold))
                    if let firstDirection = session.pattern.strokes.first?.direction {
                        firstStrokeArrow(for: firstDirection)
                    }
                    metronomeLight
                }
            case .running:
                runningContent
            case .finished:
                if let result = session.finalResult {
                    DrillResultView(pattern: session.pattern, result: result, bestStreak: session.bestStreak) {
                        session.start(modelContext: modelContext)
                    }
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
        .onChange(of: session.beatTick) { _, _ in
            pulseMetronomeLight()
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

    // The metronome already ticks audibly through the countdown and the
    // run; this just gives that same beat a visual pulse too, since a
    // click alone is easy to lose track of over background/game audio.
    @MainActor
    private func pulseMetronomeLight() {
        metronomeLit = true
        Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            metronomeLit = false
        }
    }

    private var metronomeLight: some View {
        Circle()
            .fill(metronomeLit ? Color.cyan : Color.cyan.opacity(0.2))
            .frame(width: 14, height: 14)
            .animation(.easeOut(duration: 0.08), value: metronomeLit)
    }

    // Shown only during the countdown - the first target has no lead-in
    // stroke to telegraph its direction the way every later one does, so
    // this is the only warning you get before it's live.
    private func firstStrokeArrow(for direction: Direction) -> some View {
        Image(systemName: direction == .forward ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
            .font(.system(size: 40))
            .foregroundStyle(direction == .forward ? Color.blue : Color.purple)
    }

    private var runningContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text(String(format: "%.1fs", session.elapsedTime))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                metronomeLight
                Spacer()
                strokeCounter
                streakBadge
            }
            overlayChart
            Text("Dashed line = a perfect run")
                .font(.caption2)
                .foregroundStyle(.secondary)
            hitMissSummary
        }
    }

    /// How many targets have been graded so far, out of the pattern's
    /// total - a target stays uncounted until its timing window closes,
    /// so this tracks progress through the drill rather than just how
    /// many strokes you've physically made.
    private var strokeCounter: some View {
        var resolved = 0
        for status in session.statuses where status != .upcoming {
            resolved += 1
        }
        return HStack(spacing: 4) {
            Text("\(resolved)/\(session.statuses.count)")
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
            Text("strokes")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
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
    // Each target is drawn as a single dot at a fixed height (+1/-1 for
    // forward/back) - the same height PatternMatcher now actually grades
    // your stroke's peak velocity against (see PatternMatcher's amplitude
    // scoring). So "the line's peak visually reaches the dot, at the right
    // time" now really is what earns a Perfect/Great grade, instead of the
    // dot's height being pure decoration the way it was before amplitude
    // was added to the scorer.
    private var overlayChart: some View {
        let beatDuration = DrillTimeline.beatDuration(bpm: session.pattern.bpm)
        // Normalized against the amplitude target grading uses, so y = ±1
        // is exactly "on-target peak" and the target dots sit there.
        let reference = max(PerfectRunCurve.targetPeakVelocity(for: session.pattern), 0.001)
        let totalBeats = max(DrillTimeline.totalDuration(pattern: session.pattern) / beatDuration, 1)
        let targets = Array(zip(session.pattern.strokes, session.statuses))
        let liveSamples = session.liveSamples
        let barSeparators = barSeparatorBeats(for: session.pattern)
        let perfectRun = PerfectRunCurve.points(for: session.pattern)

        // Show only the back half of the empty lead-in bar. The full bar
        // still runs (it's the settle-in time before the first stroke is
        // due) but rendering all of it spends a fifth of the chart's width
        // on blank space; halving it hands that width back to the bars
        // that actually have strokes in them.
        let firstTargetBeat: Double = session.pattern.strokes.first?.beatPosition ?? 0
        let displayStartBeat: Double = firstTargetBeat / 2
        let visibleBeats: Double = max(totalBeats - displayStartBeat, 1)

        func xPosition(beat: Double, width: CGFloat) -> CGFloat {
            CGFloat((beat - displayStartBeat) / visibleBeats) * width
        }
        func yPosition(value: Double, height: CGFloat) -> CGFloat {
            let clamped = min(max(value, -2), 2)
            return height * (1 - CGFloat((clamped + 2) / 4))
        }

        return Canvas { context, size in
            // Bar separators, so the strokes read as bars of eight rather
            // than one undifferentiated row of dots.
            var barLines = Path()
            for beat in barSeparators {
                let x = xPosition(beat: beat, width: size.width)
                barLines.move(to: CGPoint(x: x, y: 0))
                barLines.addLine(to: CGPoint(x: x, y: size.height))
            }
            context.stroke(barLines, with: .color(.gray.opacity(0.3)), lineWidth: 1)

            // The reference perfect run, behind everything else: every
            // target on time, in the right direction, peaking exactly at
            // its dot. This is the shape to aim at - your live trace
            // tracing over it is what a 100 looks like.
            if perfectRun.count > 1 {
                var ghost = Path()
                for (index, point) in perfectRun.enumerated() {
                    let position = CGPoint(
                        x: xPosition(beat: point.beat, width: size.width),
                        y: yPosition(value: point.normalizedVelocity, height: size.height)
                    )
                    if index == 0 {
                        ghost.move(to: position)
                    } else {
                        ghost.addLine(to: position)
                    }
                }
                context.stroke(
                    ghost,
                    with: .color(.white.opacity(0.25)),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
            }

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
                let dot = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
                context.fill(Path(ellipseIn: dot), with: .color(color(for: status)))
            }
        }
        .frame(height: 220)
    }

    /// Where each bar separator goes, in beats: exactly halfway between
    /// the last target of one bar and the first target of the next.
    ///
    /// Taking the midpoint of the two dots that straddle the boundary is
    /// what actually centres the line. Drawing it at the bar boundary
    /// puts it on top of a dot (targets sit on an even subdivision of the
    /// bar), and backing off by a fixed half-stroke only centres where a
    /// dot really does precede the boundary - which isn't true at the end
    /// of the empty lead-in bar, where there's no preceding dot at all
    /// and the line just floats in open space.
    private func barSeparatorBeats(for pattern: ScratchPattern) -> [Double] {
        let positions: [Double] = pattern.strokes.map(\.beatPosition)
        guard positions.count > 1 else { return [] }

        let beatsPerBar: Double = DrillTimeline.beatsPerBar
        var separators: [Double] = []
        for index in 1..<positions.count {
            let previous: Double = positions[index - 1]
            let current: Double = positions[index]
            let previousBar: Int = Int(floor(previous / beatsPerBar))
            let currentBar: Int = Int(floor(current / beatsPerBar))
            if currentBar != previousBar {
                separators.append((previous + current) / 2)
            }
        }
        return separators
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
