import SwiftUI

@main
struct ScratchLabApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                Phase2View()
                    .tabItem { Label("Scratch", systemImage: "waveform") }
                Phase0View()
                    .tabItem { Label("Diagnostics", systemImage: "gauge") }
            }
        }
    }
}
