import SwiftUI
import Charts

struct DrillResultView: View {
    let pattern: ScratchPattern
    let result: MatchResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Score: \(Int(result.overallScore))")
                    .font(.largeTitle.bold())

                Chart(Array(result.strokeScores.enumerated()), id: \.offset) { _, score in
                    BarMark(
                        x: .value("Stroke", score.targetIndex),
                        y: .value("Score", score.score)
                    )
                    .foregroundStyle(score.matched ? Color.green : Color.red)
                }
                .frame(height: 200)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(result.strokeScores.enumerated()), id: \.offset) { _, score in
                        HStack {
                            Text("Stroke \(score.targetIndex + 1)")
                            Spacer()
                            if score.matched {
                                Text("\(Int(score.score))  ·  \(score.directionCorrect ? "✓ dir" : "✗ dir")  ·  \(timingText(score.timingErrorMs))")
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

    private func timingText(_ ms: Double?) -> String {
        guard let ms else { return "" }
        return String(format: "%+.0fms", ms)
    }
}
