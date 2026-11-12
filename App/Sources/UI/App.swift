import SwiftUI

// RuxelApp — the app entry point (@main).
// What: owns the ProjectStore, shows ContentView, sets the RTL-friendly locale.
// Inputs-outputs: launch -> ContentView with the shared project store.
// Threading: SwiftUI app lifecycle; runs on the main actor.
@main
struct RuxelApp: App {
    @StateObject private var projectStore = ProjectStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(projectStore)
        }
    }
}
