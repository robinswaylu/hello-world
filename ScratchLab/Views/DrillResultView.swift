import SwiftUI
import Charts

struct DrillResultView: View {
    let pattern: ScratchPattern
    let result: MatchResult
    let bestStreak: Int
    let diagnosis: TimingDiagnosis?
    let onReplay: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Score: \(Int(result.overallScore))")
                    .font(.largeTitle.bold())

                diagnosisCard
                longestStreak
                gradeSummary

                Button("Replay", action: onReplay)
                    .buttonStyle(.borderedProminent)

                Chart(Array(result.strokeScores.enumerated()), id: \.offset) { _, score in
                    BarMark(
                        x: .value("Stroke", score.targetIndex),
                        y: .value("Score", score.score)
                    )
                    .foregroundStyle(color(for: score.grade))
                }
                .frame(height: 200)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(result.strokeScores.enumerated()), id: \.offset) { _, score in
                        HStack {
                            Text("Stroke \(score.targetIndex + 1)")
                            Spacer()
                            if score.matched {
                                Text("\(label(for: score.grade)) \(Int(score.score))  ·  \(score.directionCorrect ? "✓ dir" : "✗ dir")  ·  \(timingText(score.timingErrorMs))")
                                    .foregroundStyle(color(for: score.grade))
                            } else {
                                Text("Missed").foregroundStyle(.red)
                            }
                        }
                        .font(.footnote)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Result")
    }

    /// The one line that says *why* the score came out how it did. A column
    /// of per-stroke millisecond errors can't distinguish "steady at the
    /// wrong tempo" from "erratic at the right one", and those need
    /// opposite fixes.
    @ViewBuilder
    private var diagnosisCard: some View {
        if let diagnosis, diagnosis.headline != .notEnoughData {
            VStack(alignment: .leading, spacing: 6) {
                Text(diagnosisTitle(diagnosis.headline))
                    .font(.headline)
                    .foregroundStyle(diagnosisColor(diagnosis.headline))
                Text(diagnosisDetail(diagnosis))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(diagnosisColor(diagnosis.headline).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func diagnosisTitle(_ headline: TimingDiagnosis.Headline) -> String {
        switch headline {
        case .rushing: return "You're rushing"
        case .dragging: return "You're dragging"
        case .uneven: return "Your timing is uneven"
        case .offset(let ms): return ms > 0 ? "You're consistently late" : "You're consistently early"
        case .solid: return "Solid timing"
        case .notEnoughData: return ""
        }
    }

    private func diagnosisColor(_ headline: TimingDiagnosis.Headline) -> Color {
        switch headline {
        case .solid: return .green
        case .rushing, .dragging: return .orange
        case .uneven, .offset: return .cyan
        case .notEnoughData: return .secondary
        }
    }

    private func diagnosisDetail(_ diagnosis: TimingDiagnosis) -> String {
        let jitter = diagnosis.jitterMs.map { String(format: "±%.0fms", $0) } ?? "—"
        switch diagnosis.headline {
        case .rushing(let bpm, let percent), .dragging(let bpm, let percent):
            let steadiness = (diagnosis.jitterMs ?? 0) < 0.12 * expectedSpacingMs
                ? "Your strokes are evenly spaced (\(jitter)) — the tempo is what's off, not your control."
                : "Your spacing also wanders (\(jitter)), so work on evenness alongside the tempo."
            return String(format: "Playing at about %.0f BPM against a %.0f BPM drill (%+.0f%%). ", bpm, pattern.bpm, percent) + steadiness
        case .uneven:
            return "The tempo is right on average, but the gaps between strokes vary by \(jitter). Try a slower drill and focus on even spacing."
        case .offset(let ms):
            return String(format: "Right tempo and steady, but every stroke sits about %.0fms %@ the beat.", abs(ms), ms > 0 ? "after" : "before")
        case .solid:
            return "Right tempo, evenly spaced (\(jitter)), and sitting on the beat."
        case .notEnoughData:
            return ""
        }
    }

    private var expectedSpacingMs: Double {
        PerfectRunCurve.gapBeats(for: pattern) * DrillTimeline.beatDuration(bpm: pattern.bpm) * 1000
    }

    /// The best run of consecutive Good-or-better strokes in this attempt.
    /// Styled like the live badge during practice so it reads as the same
    /// number you were watching climb.
    private var longestStreak: some View {
        HStack(spacing: 8) {
            Text("Longest streak")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(bestStreak)")
                .font(.system(size: 22, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(bestStreak > 0 ? Color.orange : Color.secondary)
            Text("of \(result.strokeScores.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var gradeSummary: some View {
        var counts: [StrokeGrade: Int] = [:]
        for score in result.strokeScores {
            counts[score.grade, default: 0] += 1
        }
        return Text("Perfect \(counts[.perfect] ?? 0) · Great \(counts[.great] ?? 0) · Good \(counts[.good] ?? 0) · Poor \(counts[.poor] ?? 0) · Missed \(counts[.missed] ?? 0)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private func color(for grade: StrokeGrade) -> Color {
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
        case .perfect: return "Perfect"
        case .great: return "Great"
        case .good: return "Good"
        case .poor: return "Poor"
        case .missed: return "Missed"
        }
    }

    private func timingText(_ ms: Double?) -> String {
        guard let ms else { return "" }
        return String(format: "%+.0fms", ms)
    }
}
