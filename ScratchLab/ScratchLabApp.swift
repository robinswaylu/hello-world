import SwiftUI
import SwiftData

@main
struct ScratchLabApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    MainTabView()
                } else {
                    OnboardingView()
                }
            }
            .preferredColorScheme(.dark)
        }
        .modelContainer(for: DrillResult.self)
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            Phase2View()
                .tabItem { Label("Scratch", systemImage: "waveform") }
            DrillListView()
                .tabItem { Label("Drills", systemImage: "list.bullet") }
            Phase0View()
                .tabItem { Label("Diagnostics", systemImage: "gauge") }
        }
    }
}
