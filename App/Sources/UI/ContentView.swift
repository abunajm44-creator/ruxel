// ContentView — root switch: onboarding once, then Home, then the editor.
// What: holds the selected project and the onboarding-seen flag.
// Inputs-outputs: user taps -> HomeView or EditorView for the chosen project.
// Threading: @MainActor SwiftUI view; state lives here via @StateObject/@State.

import SwiftUI
import EditorCore
struct ContentView: View {
    @EnvironmentObject private var projectStore: ProjectStore
    @AppStorage("ruxel.onboardingSeen") private var onboardingSeen = false
    @State private var selectedProject: ProjectInfo?
    @State private var isImporting = false

    var body: some View {
        Group {
            if onboardingSeen == false {
                OnboardingView(isPresented: $onboardingSeen)
            } else if let project = selectedProject {
                EditorView(project: project, store: projectStore) {
                    selectedProject = nil
                }
            } else {
                HomeView(
                    onOpen: { selectedProject = $0 },
                    onImport: { isImporting = true }
                )
            }
        }
        .sheet(isPresented: $isImporting) {
            PhotoPickerSheet { url in
                isImporting = false
                openImportedPhoto(at: url)
            }
        }
    }

    private func openImportedPhoto(at url: URL?) {
        guard let url else { return }
        do {
            let project = try projectStore.createProject(
                originalURL: url, state: RetouchState())
            selectedProject = project
        } catch {
            // Friendly error is shown by HomeView via the store; keep this
            // path silent here because there is no alert host at this level.
        }
    }
}
