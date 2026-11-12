// ProjectStore — project persistence: original file + state.json + analysis cache.
// What: create / load / autosave (atomic) / list projects with thumbnails.
// Inputs-outputs: RetouchState <-> state.json on disk; crash recovery via autosave.
// Threading: file work on a background queue; published list read on @MainActor.

import Foundation
import UIKit
import EditorCore
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [ProjectInfo] = []

    private let projectsDirectory: URL
    private let fileManager = FileManager.default
    private let workQueue = DispatchQueue(
        label: "com.abunajm44creator.ruxel.projects", qos: .utility)

    init(projectsDirectory: URL? = nil) {
        if let directory = projectsDirectory {
            self.projectsDirectory = directory
        } else {
            let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            self.projectsDirectory = (documents ?? fileManager.temporaryDirectory)
                .appendingPathComponent("Projects", isDirectory: true)
        }
        try? fileManager.createDirectory(
            at: self.projectsDirectory, withIntermediateDirectories: true)
        refresh()
    }

    /// Creates a project folder for an imported original and saves the initial state.
    func createProject(originalURL: URL, state: RetouchState) throws -> ProjectInfo {
        let id = UUID()
        let folder = projectsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let storedOriginal = folder.appendingPathComponent("original")
            .appendingPathExtension(originalURL.pathExtension)
        try fileManager.copyItem(at: originalURL, to: storedOriginal)
        try saveState(state, projectID: id)
        let info = ProjectInfo(
            id: id, folder: folder, originalURL: storedOriginal,
            modifiedAt: Date(), thumbnail: nil)
        refresh()
        return info
    }

    /// Autosave after every change: atomic write, so a crash never corrupts state.
    func saveState(_ state: RetouchState, projectID: UUID) throws {
        let folder = projectsDirectory.appendingPathComponent(projectID.uuidString, isDirectory: true)
        let url = folder.appendingPathComponent("state.json")
        let data = try JSONEncoder().encode(state)
        try data.write(to: url, options: .atomic)
    }

    /// Autosaves the app extras (P5/P6 tool state; face/skin sliders live
    /// in EditorCore state.json now and are NOT stored here anymore).
    func saveExtras(_ extras: ExtraAdjustments, projectID: UUID) throws {
        let folder = projectsDirectory.appendingPathComponent(projectID.uuidString, isDirectory: true)
        let url = folder.appendingPathComponent("extras.json")
        let data = try JSONEncoder().encode(extras)
        try data.write(to: url, options: .atomic)
    }

    /// Loads extras.json; returns defaults when the project predates extras.
    func loadExtras(projectID: UUID) -> ExtraAdjustments {
        let url = projectsDirectory.appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent("extras.json")
        guard let data = try? Data(contentsOf: url),
              let extras = try? JSONDecoder().decode(ExtraAdjustments.self, from: data) else {
            return ExtraAdjustments()
        }
        return extras
    }

    /// Migrates a pre-migration extras.json (old app-side slider store)
    /// into `state` once: legacy face/skin values copy into the primary
    /// face / skin, the state is re-saved, and extras.json is rewritten
    /// from `extras` (current P5/P6 fields only) so the legacy face keys
    /// are dropped without losing newer extras. No-op when the file is
    /// absent or holds no legacy values. Called from EditorViewModel.init
    /// after loading state + extras.
    func migrateLegacyExtras(into state: inout RetouchState, extras: ExtraAdjustments, projectID: UUID) {
        let folder = projectsDirectory.appendingPathComponent(projectID.uuidString, isDirectory: true)
        let url = folder.appendingPathComponent("extras.json")
        guard let data = try? Data(contentsOf: url),
              let legacy = try? JSONDecoder().decode(LegacyExtras.self, from: data),
              legacy.hasMigratableValues else {
            return
        }
        legacy.apply(to: &state)
        try? saveState(state, projectID: projectID)
        try? saveExtras(extras, projectID: projectID)
    }

    /// Loads state.json; throws AppError.projectCorrupted when it cannot be read.
    func loadState(projectID: UUID) throws -> RetouchState {
        let url = projectsDirectory.appendingPathComponent(projectID.uuidString, isDirectory: true)
            .appendingPathComponent("state.json")
        guard let data = try? Data(contentsOf: url) else {
            throw AppError.projectCorrupted
        }
        do {
            return try JSONDecoder().decode(RetouchState.self, from: data)
        } catch {
            throw AppError.projectCorrupted
        }
    }

    /// Deletes a whole project folder (recoverable only via the system trash, if any).
    func deleteProject(_ info: ProjectInfo) throws {
        try fileManager.removeItem(at: info.folder)
        refresh()
    }

    /// Re-reads the projects directory (crash recovery: any folder with an
    /// original + state.json is a valid project, even if the app died mid-save).
    func refresh() {
        workQueue.async { [weak self] in
            guard let self else { return }
            let folders = (try? self.fileManager.contentsOfDirectory(
                at: self.projectsDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles])) ?? []
            var infos: [ProjectInfo] = []
            for folder in folders {
                guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
                let contents = (try? self.fileManager.contentsOfDirectory(
                    atPath: folder.path)) ?? []
                guard contents.contains(where: { $0.hasPrefix("original") }),
                      contents.contains("state.json") else { continue }
                let original = folder.appendingPathComponent(
                    contents.first(where: { $0.hasPrefix("original") }) ?? "original")
                let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))
                    .flatMap { $0.contentModificationDate } ?? Date.distantPast
                infos.append(ProjectInfo(
                    id: id, folder: folder, originalURL: original,
                    modifiedAt: modified, thumbnail: nil))
            }
            let sorted = infos.sorted { $0.modifiedAt > $1.modifiedAt }
            Task { @MainActor in self.projects = sorted }
        }
    }
}

// ProjectInfo — one row in the home project grid.
struct ProjectInfo: Identifiable, Equatable, Sendable {
    var id: UUID
    var folder: URL
    var originalURL: URL
    var modifiedAt: Date
    var thumbnail: UIImage?
}
