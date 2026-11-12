import SwiftUI
import PhotosUI

// HomeView — project grid + import hero button + empty state.
// What: shows saved projects with thumbnails; import starts a new project.
// Inputs-outputs: taps -> onOpen(project) / onImport(); errors shown in Arabic.
// Threading: @MainActor SwiftUI view; ProjectStore is an @EnvironmentObject.
struct HomeView: View {
    @EnvironmentObject private var projectStore: ProjectStore
    var onOpen: (ProjectInfo) -> Void
    var onImport: () -> Void

    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    importHero
                    if projectStore.projects.isEmpty {
                        emptyState
                    } else {
                        projectGrid
                    }
                }
                .padding()
            }
            .navigationTitle(Text("home.title"))
            .alert(
                Text("error.title"),
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { shown in if shown == false { errorMessage = nil } }
                ),
                actions: { Button("common.ok") { errorMessage = nil } },
                message: { Text(errorMessage ?? "") }
            )
        }
    }

    private var importHero: some View {
        Button(action: onImport) {
            HStack {
                Image(systemName: "photo.badge.plus")
                    .font(.title2)
                Text("home.import")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .adaptiveGlass(in: RoundedRectangle(cornerRadius: 20), interactive: true)
        .accessibilityLabel(Text("home.import"))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("home.empty.title")
                .font(.headline)
            Text("home.empty.body")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var projectGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            ForEach(projectStore.projects) { project in
                Button(action: { onOpen(project) }) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let thumbnail = project.thumbnail {
                            Image(uiImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 160)
                                .clipped()
                                .cornerRadius(16)
                        } else {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.secondary.opacity(0.2))
                                .frame(height: 160)
                                .overlay(Image(systemName: "photo").font(.title))
                        }
                        Text(project.modifiedAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("home.openProject"))
            }
        }
    }
}

// OnboardingView — three screens shown on first launch.
struct OnboardingView: View {
    @Binding var isPresented: Bool

    private let pages: [(title: String, body: String, image: String)] = [
        ("onboarding.1.title", "onboarding.1.body", "face.smiling"),
        ("onboarding.2.title", "onboarding.2.body", "wand.and.stars"),
        ("onboarding.3.title", "onboarding.3.body", "square.and.arrow.up")
    ]

    var body: some View {
        TabView {
            ForEach(pages.indices, id: \.self) { index in
                VStack(spacing: 16) {
                    Image(systemName: pages[index].image)
                        .font(.system(size: 64))
                    Text(pages[index].title)
                        .font(.title2.bold())
                    Text(pages[index].body)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    if index == pages.count - 1 {
                        Button("onboarding.start") { isPresented = true }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 16)
                    }
                }
            }
        }
        .tabViewStyle(.page)
    }
}

// PhotoPickerSheet — PHPicker wrapper used by ContentView for import.
struct PhotoPickerSheet: UIViewControllerRepresentable {
    var onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        let picker = PHPickerViewController(
            configuration: PhotoImportService.pickerConfiguration())
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var onPick: (URL?) -> Void

        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let result = results.first else { onPick(nil); return }
            Task {
                do {
                    let dir = FileManager.default.temporaryDirectory
                    let url = try await PhotoImportService().loadPhoto(from: result, into: dir)
                    onPick(url)
                } catch {
                    onPick(nil)
                }
            }
        }
    }
}
