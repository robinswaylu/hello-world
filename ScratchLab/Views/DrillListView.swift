import SwiftUI
import SwiftData

struct DrillListView: View {
    @Query(sort: \DrillResult.date, order: .reverse) private var results: [DrillResult]

    private var drills: [ScratchPattern] { BuiltInDrills.all }

    // Computed once per body evaluation instead of once per row - each row
    // used to do its own O(results.count) filter/map/max over the *entire*
    // results table just to find its own drill's best, which scales with
    // how many drills have ever been attempted, not just how many rows
    // there are (there are only 3 drills; `results` has no such bound).
    private var bestScoresByDrillID: [String: Double] {
        Dictionary(grouping: results, by: \.drillID)
            .compactMapValues { $0.map(\.overallScore).max() }
    }

    var body: some View {
        NavigationStack {
            List(drills, id: \.id) { drill in
                let best = bestScoresByDrillID[drill.id]
                NavigationLink(value: drill.id) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(drill.name)
                        if let best {
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
}
