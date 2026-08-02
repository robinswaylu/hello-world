import SwiftUI
import SwiftData

@main
struct ScratchLabApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                Phase2View()
                    .tabItem { Label("Scratch", systemImage: "waveform") }
                DrillListView()
                    .tabItem { Label("Drills", systemImage: "list.bullet") }
                Phase0View()
                    .tabItem { Label("Diagnostics", systemImage: "gauge") }
            }
        }
        .modelContainer(for: DrillResult.self)
    }
}
