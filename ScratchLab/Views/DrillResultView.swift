import SwiftUI
import Charts

struct DrillResultView: View {
    let pattern: ScratchPattern
    let result: MatchResult
    let bestStreak: Int
    let onReplay: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Score: \(Int(result.overallScore))")
                    .font(.largeTitle.bold())

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
