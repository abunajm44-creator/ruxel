import Foundation
import EditorCore

// ExtraAdjustments — app-side adjustments EditorCore does not model.
// What: P5/P6 tool state (color brush, eraser, hair, makeup, crop, ...);
// the 32 face sliders + skin grain used to live here but moved to
// EditorCore FaceAdjustments / SkinAdjustments (2026-11-12) — do NOT
// re-add face/skin slider fields here. Old extras.json files with face
// values are migrated once by ProjectStore.migrateLegacyExtras.
// Inputs-outputs: persisted as extras.json next to state.json.
// Threading: value type; owned by the @MainActor EditorViewModel only.
struct ExtraAdjustments: Codable, Equatable, Sendable {
    // P5/P6 fields are added by the owning agent as those tools land.
    // (Face sliders + grain: EditorCore. See LegacyExtras.swift.)

    var isNeutral: Bool {
        true
    }
}

// EditorSnapshot — one undoable unit: EditorCore state + app extras together.
// What: keeps undo/redo coherent across both stores (single History stack).
// Inputs-outputs: recorded before every committed change; restored on undo/redo.
// Threading: value type; owned by the @MainActor EditorViewModel only.
struct EditorSnapshot: Equatable, Sendable {
    var state: RetouchState
    var extras: ExtraAdjustments

    init(state: RetouchState = RetouchState(), extras: ExtraAdjustments = ExtraAdjustments()) {
        self.state = state
        self.extras = extras
    }
}
