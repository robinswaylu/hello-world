import SwiftUI
import SwiftData

struct DrillListView: View {
    @Query(sort: \DrillResult.date, order: .reverse) private var results: [DrillResult]

    private var drills: [ScratchPattern] { BuiltInDrills.all }

    var body: some View {
        NavigationStack {
            List(drills, id: \.id) { drill in
                NavigationLink(value: drill.id) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(drill.name)
                        if let best = bestScore(for: drill) {
                            Text("Best: \(Int(best))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Not attempted yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Drills")
            .navigationDestination(for: String.self) { drillID in
                if let drill = drills.first(where: { $0.id == drillID }) {
                    DrillDetailView(pattern: drill)
                }
            }
        }
    }

    private func bestScore(for drill: ScratchPattern) -> Double? {
        results.filter { $0.drillID == drill.id }.map(\.overallScore).max()
    }
}
