# PROGRESS.md — Ruxel

## Current milestone: P0 — in progress (started 2026-11-12)

**Status: partial.** CI workflows + QA harness are written and the harness
runs green locally. No green CI build yet (no repo exists to run CI on),
no IPA yet. Nothing is `done` until a green build produces a verified IPA.

## What is done (2026-11-12, overnight session)

- [x] Repo scaffolded locally on branch `work` (no remote — creation blocked, see below).
- [x] `.github/workflows/build.yml` — Linux EditorCore tests (pinned
  `swift:6.1.3-noble` container, verified tag) + macOS iOS build, Xcode
  selection, runner Metal capability probe, unsigned IPA packaging,
  artifact upload, release on `main` only.
- [x] `.github/workflows/sdk-probe.yml` — batched SDK header grep
  (framework + `|||`-separated regexes).
- [x] `tools/qa_harness.py` + `tools/README.md` — CPU reference renderer
  (falloff, scaleDisplacement, skin smooth blend), mediapipe with
  synthetic-grid fallback, FaceLandmarks JSON, numeric checks.
- [x] QA harness run (Einstein portrait, 384×512): 9 renders
  (face_width / eye_size / skin_smooth at -100/0/+100), exit code 0.
  Worst Jacobian determinant min = **0.364** (must stay > 0.05 — pass).
  Skin mask coverage = 0.069. Images reviewed visually: before/after look
  sane, warp is subtle at these limits. Caveat: landmarks were the
  synthetic grid (mediapipe not installed), so the face oval is
  approximate — real detected landmarks will fit better.
- [x] Top-level docs: DECISIONS, ENV, FEATURES, ARCHITECTURE, APIS,
  DEBUG_LOG, ASSETS, LESSONS, PROGRESS, MORNING_REPORT.
- [x] Swift 6.1.2 toolchain READY on Linux
  (`$HOME/tmp/swift/swift-6.1.2-RELEASE-ubuntu24.04/usr/bin`, verified
  `swift --version`).
- [x] Other agents (parallel): `App/`, `Packages/EditorCore` scaffolding,
  `project.yml`, `DESIGN.md` — not this task's scope, not verified here.

## What is pending (P0 remainder)

- [ ] Repo `ruxel` created on GitHub (BLOCKED — needs the user, see
  MORNING_REPORT.md) and local `work` branch pushed.
- [ ] First CI run on `work`: Linux `swift test` green, then macOS build green.
- [ ] Runner capability probe result recorded in ENV.md (GPU or no GPU).
- [ ] SDK probe batch 1 (Vision) run; confirmed signatures in APIS.md.
- [ ] App launches + Liquid Glass shell verified; IPA downloaded and
  verified with `unzip -l` (Payload/App.app/Info.plist + executable).
- [ ] Merge `work` -> `main` only after green; tag P0; release "latest".

## Next step

1. User (morning): the single GitHub step in MORNING_REPORT.md.
2. Then: push `work`, watch the first CI run, fix whatever is red,
   record the probe result, and close P0.

## Milestones

| Milestone | Status |
|-----------|--------|
| P0: repo + XcodeGen + EditorCore + CI + probes + shell + IPA | partial |
| P1: import, canvas, compare, undo/redo, export, projects, P3 | not done |
| P2: analysis + face reshape engine + QA images | not done |
| P3: skin engine + Auto + wrinkles/acne/shine/dark circles + teeth + eyes | not done |
| P4: body + background lock | not done |
| P5: makeup, color brush, head, lift, distortion, multi-face | partial |
| P6: eraser, hair, sparkle, 3D tab, crop/rotate, adjust, filters | partial |
| P7: polish, localization, accessibility, icon, README, Phase 2 plan | partial |

## 2026-11-12 ~05:15 — Consolidation after all 3 builders finished (coordinator)

- Workspace MOVED `~/workspace/lamsa` → `~/workspace/ruxel` (all builders done; no writes in flight). Old `.build/` deleted — its PCH cache held the old absolute path and broke the build after the move; clean rebuild fixed it.
- **Verified by coordinator, independent re-run:** `swift test` in `Packages/EditorCore` from the new path: **56 tests, 0 failures** (Swift 6.1.2, Swift 5 language mode via `swiftLanguageVersions: [.v5]`).
- **Verified:** 50 Swift/Metal files; 25 files mention Ruxel/ruxel; remaining "Lamsa/Basma" strings are intentional history only (DECISIONS.md rows 1/14/16, NOTES-REPO-BLOCKER.md) plus generic Arabic "بلمسة واحدة" (one-tap) UI copy. `.gitignore` added (`.build/`, `build/`, `DerivedData/`, `*.ipa`).
- App builder's P0–P3 code is IN the tree (project.yml target Ruxel, Metal kernels, RenderGraph, import/export, Vision analysis, project store, full UI incl. Face/Skin/Body tools, 122-string ar+en localizations, debug overlay). Status stays **not done** per the honesty rule: no macOS CI run exists yet, so nothing is proven to compile under Xcode.
- Known gaps carried to P4–P7 work (from App builder report): EditorCore has only 10 face-slider fields vs 32 in the spec — the other 22 + skin grain live in app-side `ExtraAdjustments` (`extras.json`) until EditorCore is extended; texture pool not implemented (intermediates created per render); brush stroke stamping not wired into CanvasView touch input; full-res tile export loop not wired to the graph; debug overlay toggles are state-only (no overlay rendering); Cancel (X) = undo last change (no true discard); `skin.texture` semantics assumed "texture kept" (VERIFY: if it means texture removed, `textureKeep01` must become `1 - texture/100`).
- Next: commit this state on `work`, then P4–P7 builders (EditorCore slider extension + engine gaps; P5–P6 features; P7 polish). Repo creation still BLOCKED (MCP 403 + gh not authed) — see NOTES-REPO-BLOCKER.md.

## 2026-11-12 ~05:20–06:00 — P5–P7 (UI + polish) by the P5–P7 subagent

**Status: partial.** All P5/P6 features have UI + stored state; NONE of
them changes pixels on the photo yet — their render-graph passes are NOT
built (makeup, color brush, head warp, lift warp, sparkle, color pass,
crop pass, 3D warp, inpainting). Nothing here is `done`: no green CI
build exists for this code (no Xcode on this VM; `swiftc -parse` passes
on all 20 touched app files, which catches syntax only, NOT types).
Display name rule applied: RUXEL in ALL CAPS (README title, docs);
technical identifiers stay lowercase (`ruxel`, `com.abunajm44creator.ruxel`).

### What was built

- **New models:** `PaintStroke` (+ `PaintStrokeKind`: color/erase/sparkle,
  normalized points, persisted in extras); `ExtraAdjustments` extended
  with head, lift, 3D depth/far-side, selectedFaceIndex, crop/rotate,
  basic adjust, filter preset, hair, sparkle + color-brush + eraser
  strokes; `RetouchState` helpers `clampedFaceIndex` / `ensureFace(at:)`.
- **New UI (App/Sources/UI/):** `MakeupToolView` (5 regions, color picker,
  intensity, matte/satin/glossy — wired to EditorCore `MakeupAdjustments`),
  `ColorBrushView`, `HeadToolView`, `LiftToolView`, `ObjectEraserView`,
  `HairToolView`, `SparkleBrushView`, `CropRotateView`, `BasicAdjustView`,
  `FiltersView`, `PaintCanvasView` + `PaintOverlayView` (shared pan-paint
  surface, one undo step per stroke), `EditorBottomBar` (extracted from
  EditorView to keep it under 300 lines).
- **EditorView wiring:** all 13 new tools in the panel; paint overlay
  shown only for paint tools; distortion toggle + "?" popover kept, plus
  a strength slider (0...100) that appears while correction is on.
  Tool strip grew 19 -> 22 tools (`EditorTool` + cropRotate/basicAdjust/
  filters, appended so the 19-tool RTL order is unchanged).
- **FaceToolView:** 3D tab extended (depth + far-side attenuation sliders
  + yaw/pitch/roll attenuation note, app-side until EditorCore gains 3D
  fields); face sliders now target the SELECTED face, not always face 0.
- **Multi-face selector:** face picker chip (Face 1/2/3...) appears when
  >1 face has adjustments; scope chip (General/Left/Right) now applies to
  the selected face.
- **Object eraser is an HONEST stub:** mask painting + clear work; Apply
  is deliberately disabled and the UI + FEATURES.md say the PatchMatch
  inpainting engine is not built. Never presented as working removal.
- **Hair is gated off:** no hair mask exists (AnalysisService requests no
  AVSemanticSegmentationMatte), so all hair controls are disabled with an
  honest message.
- **Localization:** 122 -> 192 keys, ar + en sets identical (verified by
  script); every new control has a VoiceOver label; BipolarSlider hit
  area raised to 44pt; back button raised to 44pt.
- **Icon:** `tools/generate_icon.py` (Pillow) — original gradient +
  pixel-face motif, 8 sizes (40–1024px) + Contents.json; visually checked
  at 1024px. No text in the icon.
- **Docs:** `README.md` (Arabic + English, RUXEL title, sideload install,
  build, privacy); `ARCHITECTURE.md` Phase 2 plan expanded (per-frame
  pipeline reuse, One-Euro role, analysis cadence, performance notes);
  `ASSETS.md` icon section; `FEATURES.md` updated honestly (partial /
  not done per feature, with the engine-pending caveat on each row).

### Known gaps / things the next agent must know

- **No render passes exist yet** for makeup, color brush, head, lift,
  sparkle, basic adjust, filters, crop, 3D, or inpainting. The UI stores
  values + autosaves; the engine must consume `state.makeup`,
  `extras.*Strokes`, `extras.headSize/headShape/lift/tighten/threeD*`,
  `extras.exposure/contrast/saturation/warmth`, `extras.filterPreset`,
  `extras.cropRotation/cropAspect`.
- **Paint strokes are normalized to the OVERLAY bounds, not the photo
  rect** — the canvas exposes no photo rect yet. The engine must remap
  them once it does. Painting also pauses canvas pinch/pan while a paint
  tool is open.
- **Distortion grey-out is face-only:** no body-found signal exists in
  the view model; the gate is `hasFace` (help text still says face/body).
- **Multi-face picker only lists faces that already have adjustments:**
  analysis does not populate `state.faces`, so the picker cannot show
  faces before the user edits one. Needs a face-count signal from
  AnalysisService -> view model.
- **Undo granularity:** a color-pick session (ColorPicker has no
  begin/end events) can merge with a following slider drag into one undo
  step. Cosmetic; fix by snapshotting on picker focus if it matters.
- **VERIFY (no Xcode here):** `UIColor(Color)` initializer, ColorPicker
  labels, `Menu` + `Picker` in the bottom bar, `Glass` fallback paths —
  all standard APIs but uncompiled. First CI build will prove them.
- **EditorCore tests currently RED from the parallel agent's in-flight
  work (NOT this task's files — EditorCore untouched here):** 99 tests,
  2 failures: `WarpMathTests.testNoFoldOverFullMaxSliderSet` (Jacobian
  -13.60) and `...Negative` (-5.53) — the summed displacement at full
  max sliders folds over. Route to the EditorCore agent; slider limits
  or warp-op amounts need clamping before the head/lift/3D engine lands.
- **Performance pass (P7) NOT done:** no profiling, no texture-pool
  work, no animation polish in this session. Final audit still pending.

## P4 + engine gaps — EditorCore agent (2026-11-12, session 4f437284)

**EditorCore tests: 111, 0 failures** (`swift test`, Swift 6.1.2 Linux). The
two Jacobian failures the P5–P7 agent reported (99 tests, 2 failures,
min det −13.60 / −5.53) are FIXED at root cause — see DEBUG_LOG.md.
That note above is now stale; do not re-route it.

### Done + tested (EditorCore)
- `FaceAdjustments` extended to all 32 spec sliders + `yaw/pitch/rollAttenuation`
  (0...1, one-way); `SkinAdjustments.grain`; `BrushStroke.size` default 0.05
  (normalized diameter). Codable backward-compatible (`decodeIfPresent`).
  SliderMapping caps for every new slider.
- Jacobian fix: translate ops are now IPD-relative (eye/brow translates
  used raw 0.12–0.15 amounts with ~0.08–0.13 IPD radii → single-op det ≈ −1);
  `brushPushGain` 0.5 → 0.15; `dabSpacing` 0.25 × diameter; slider caps tuned
  down (eyeLength/eyeSpacing 0.15→0.10, chinLength 0.25→0.10, jawSize
  0.30→0.25, faceLength 0.25→0.20, bodySlim 0.35→0.30, etc.); leg length
  is one shin-midpoint translate per leg (factor 0.10, radius 0.5) instead
  of 4 knee/ankle translates. Measured 41×41 grid: full max set +0.215 /
  −0.099 (threshold > 0.05); face-only +0.386 / −0.228.
- `skin.texture` DECIDED: **texture KEPT** (100 = full detail preserved).
  Evidence: Metal param is named `textureKeep`, CPU reference + QA harness
  agree, Auto sets texture 70. `textureKeep01 = texture/100` was already
  correct; no code change, decision documented in code + DEBUG_LOG.md.
- New EditorCore: `FaceWarpOps.swift` (face ops, yaw/pitch/roll attenuation,
  max 56 ops), `BodyWarpOps.swift` (pose capsules, slim pinch, waist/hips/
  legLength/shoulders/neck, `distortionWarpOp`), `BrushEngine.swift`
  (dabs, Catmull-Rom smoothing, push/restore stamping, `stampDabTile`),
  `SkinMaskBuilder.swift` (face oval, person-mask resampling, combined
  skin mask). `WarpMath`: `farSideAttenuationFactor`, `applyBackgroundLock`,
  `displacementFieldGrid`, `tileDisplacementField` (pixel-center sampling;
  tile field == crop of the full field, tested), `maxDisplacementMagnitude`.
  Also fixed `grainNoise` Int32 overflow trap (wrapping UInt32 arithmetic).

### Done, app code (UNCOMPILED — needs macOS CI)
- FaceToolView migrated to `FaceAdjustments` key paths; Ala now maps to
  `noseAla` (was wrongly `noseWidth`); eyeAngle/eyePosition/chinWidth
  sliders added; 3D tab has one-way 0...100 attenuation sliders. Skin
  grain now uses `state.skin.grain`. Localization keys added (en + ar).
- `ExtraAdjustments` DEVIATION: NOT deleted — the parallel agent's P5–P6
  views depend on `viewModel.extras` (`sparkleStrokes`, `headSize`,
  `lift`, `cropRotation`, `filterPreset`, ...). Face fields + grain were
  removed from it; it is now a container for the P5/P6 fields only.
  `LegacyExtras.swift` decodes old `extras.json` and migrates face/grain
  into state (state wins when non-zero); `ProjectStore` re-saves state and
  rewrites `extras.json` from current extras.
- Texture pool (`TexturePool.swift`): pooled intermediates by size/format/
  usage, refcounted; `RenderGraph` rewritten on it (releases `low` after
  blend; single-queue in-order execution makes reuse safe); memory-warning
  observer purges. `WarpFieldParams.swift`: 32-byte `WarpOpParams` /
  `BrushDabParams`; `Warp.metal` gained `buildDisplacementField` +
  `stampBrushDabs` kernels mirroring the EditorCore math.
- Brush wiring: `BrushTouchView` (coalesced touches, normalized points),
  `BodyToolView` binds brush mode/size, ViewModel brush state + stroke
  methods (one undo step per stroke, live preview). `CanvasView` now
  hosts the brush view + `DebugOverlayView` as MTKView subviews, arms the
  brush only in Body manual mode (navigation gestures disabled while
  armed), pushes landmarks/bodyPose/person-mask texture to the bridge/graph.
- Debug overlay: ViewModel `debugFieldGrid()` (16×12) + `DebugOverlayView`
  draws landmark polylines/dots, person mask at 0.35 alpha, field arrows
  (8× scaled). Toggled by the existing debug toggles.
- Cancel semantics: ViewModel `committedSnapshot`, `beginToolSession()`
  (init + tool change), `cancelEditing()` (restore + clear undo +
  autosave + re-baseline), `applyEditing()` (commit + autosave).
- Body P4: `AnalysisService` returns face landmarks + body pose + person
  mask (pixel buffer + float mask + UIImage); ViewModel stores them and
  exposes `hasFaceOrBody`; `warpOpsForCurrentState()` / `brushDabsForCurrentState()`
  feed the overlay and export.
- Export: `ExportService.exportFullResolution` — CPU tile loop (2048 +
  dynamic halo from `maxDisplacementMagnitude`, min 64), skin stage
  (tile skin mask, 5-tap blur ×1–2, `skinSmoothBlendCPU`, grain re-injection)
  then warp stage (`tileDisplacementField`, background lock, bicubic per
  channel), progress per tile + cancellation, EXIF orientation normalized
  once (output orientation set to 1). ViewModel `export()` / `cancelExport()`
  / `cleanupExportFile()` + `isExporting` / `exportProgress` /
  `exportedFileURL` for the EditorView owner to wire.

### Still needs the EditorView owner (do NOT do here)
- X button → `viewModel.cancelEditing()` (still calls `undo()`).
- Apply button → `viewModel.applyEditing()` (still calls `autosave()`).
- Distortion button → `.disabled(viewModel.hasFaceOrBody == false)`
  (the face-only grey-out note above is superseded: `hasFaceOrBody` now
  exists in the view model).
- Export button / share sheet / save-to-Photos wiring → `viewModel.export()`,
  `exportedFileURL`, `cleanupExportFile()`.

### Known gaps / unproven (needs macOS CI)
- ALL app/Metal/SwiftUI code in this session is uncompiled on Linux.
  VERIFY flags in code: Vision point origin/conversion, `maskImage` /
  `floatMask` pixel formats, `CVMetalTextureCacheCreateTextureFromImage`
  with `.r8Unorm`, `MTKTextureLoader.newTexture(URL:options:)` + SRGB key.
- Interactive skin smoothing does NOTHING until a skin-mask texture is
  built for the render graph (person mask ∩ face oval ∩ likelihood);
  export implements it on CPU. The graph passes a nil mask today.
- Export memory: input + output RGBA8 buffers + assembled Data ≈ 3×
  image size transiently (~576MB at 48MP); input is released before
  assembly. Tile float buffers are transient per tile.
- `displacementFieldGrid` samples at grid NODES (0 and 1 included);
  `tileDisplacementField` samples at pixel CENTERS — different
  conventions by design (overlay vs export); do not "unify" them.
- `RenderBridge.loadSource` runs on a background Task; `graph` may be
  nil at that point (set in updateUIView) — source texture is set when
  the bridge first draws; verify on device that the first frame is not blank.

## 2026-11-12 ~05:45 — Final consolidation (coordinator): all 5 builders done, P0–P7 as far as locally possible

- **EditorCore verified by coordinator, independent re-run: 111 tests, 0 failures** (Swift 6.1.2, Linux). Includes the full 32-slider no-fold-over Jacobian test (was failing at −13.60 during the extension; fixed by the engine agent via IPD-relative translates, brushPushGain 0.15 and tuned caps; measured +0.215 / −0.099 at full max set) and the tile-field == full-field-crop test.
- **Coordinator wiring fix (final audit):** EditorView X → `viewModel.cancelEditing()`, Apply → `viewModel.applyEditing()`, distortion gate `hasFace` → `hasFaceOrBody` (button + strength slider), new export button in the top bar (`viewModel.export()` + spinner) with a share sheet from `exportedFileURL` (ShareLink + Done → `cleanupExportFile()`). Added `editor.export` / `editor.exportDone` to both .strings files; key sets verified identical (200 lines each). `swiftc -parse` passes on the edited files (syntax only).
- **Deviations recorded:** `EditorViewModel.swift` is 431 lines (over the 300-line rule — not refactored now, to avoid breaking the wiring just fixed). Interactive skin smoothing is a no-op until a skin-mask texture is built for the render graph (export implements it on CPU). Export transient memory ≈3× image size (~576MB at 48MP). `RenderBridge.loadSource` may run before `graph` is set — verify the first frame isn't blank on device. Paint strokes are normalized to overlay bounds, not the photo rect (engine must remap). Multi-face picker can't list faces before the user edits one (needs a face-count signal from AnalysisService). No `try!`/`fatalError`/force-unwraps in app sources (only in Swift's generated test-runner under `.build/`).
- **MORNING_REPORT.md updated** to the honest final state (feature table now partial, not "not done"; still no IPA, draft banner kept).
- **What remains (needs the user + macOS CI):** create PRIVATE repo `ruxel` (morning step), push `work`, first CI run (Linux green expected; macOS build + GPU probe + SDK probe unproven), download + `unzip -l` verify the IPA, merge to `main` only when green, tag P0–P7, release "latest". Then on-device testing and the P5/P6 render passes (makeup blend, eraser PatchMatch, hair mask).

## 2026-11-12 ~16:10 — P5/P6 render passes + warp direction fix (this session)

**EditorCore: 128 tests, 0 failures** (was 111; +13 ColorGrade, +3 direction, +1 brush).

### BUG FOUND + FIXED — warp direction was inverted (spec §7F/H)
- Proof: the samplers read the source at p + D(p) (inverse mapping, per
  spec §6 template + QA harness docstring), so rendered content moves
  OPPOSITE to the field vector. Scale's formula (-offset) already
  produced the correct backward field for "enlarge", but translate
  returned +direction and pinch returned -offset — so nose lift moved
  the nose DOWN, lip smile frowned, chin length shortened the chin,
  slim widened the body, and the push brush moved content opposite to
  the drag. None of the old tests caught it: they asserted FIELD values,
  not rendered motion.
- Fix: negated translate + pinch in WarpMath (Swift) and in
  warpOpDisplacement (Metal), and negated the push stamp in
  BrushEngine stampPushDab + stampDabTile and in the Metal
  stampBrushDabs kernel. The WarpOp direction/amount now means the
  INTENDED content motion everywhere; the displacement functions
  convert it to the backward field. The tile-field test caught a missed
  site (stampDabTile) — fixed too.
- Tests rewritten to assert RENDERED motion (bright-block centroid
  through warpImageFloatCubic): translate right/up, pinch toward
  center, scale away from center, push dab along the drag. The
  Jacobian no-fold-over tests still pass at full max sets — no cap
  retuning was needed.

### Color + paint passes built (P5/P6)
- EditorCore ColorGrade.swift: canonical grade math (exposure -> warmth
  -> contrast -> saturation -> clamp) + 6 filter presets as fixed slider
  mixes + crop rect math; FilterPreset/CropAspect moved here from the
  app (same raw values, extras.json still decodes). 13 unit tests.
- Metal: `colorGrade` kernel (grade + UV rotate + aspect crop) and
  `blendOverlay` kernel (paint in source space, so strokes warp with
  the photo — spec §7D order). ColorParams mirror (48-byte stride,
  checked at runtime).
- OverlayBuilder.swift: rasterizes color/sparkle strokes into a
  photo-space RGBA bitmap (straight alpha) via the photo rect; glow /
  glitter / star stamps; shared by live (Metal texture) and export
  (CPU bilinear sample).
- HeadLiftOps.swift: head size/shape (scale) + lift (up translate at
  jaw) + tighten (pinch) as WarpOps; shared by live field, debug
  overlay and export.
- RenderGraph: stages 2.5 (overlay blend) + 3.5 (color grade) with
  dirty flags; render(state:extras:output:); compare mode neutralizes
  extras too. ViewModel builds the live skin-mask texture (person mask
  AND face oval) after analysis — interactive smoothing is no longer a
  no-op. Intensity defaults raised 0 -> 100 (paint visible by default,
  matching the overlay preview).
- Export parity: extras + overlay + head/lift in the tile loop; color
  grade per core pixel (same EditorCore math); crop/rotate as a
  post-process (centered crop, then rotate into the bounding box;
  rotated corners are black in export, edge-stretched in live preview).
- P7 cleanup: temporary "Inspect generated project" CI debug step
  removed from build.yml (bundle listing kept).
- FEATURES.md + MORNING_REPORT.md updated to the true state; P0 is DONE
  (Build 8 verified + delivered). Still NOT built: makeup pass, eraser
  inpainting, hair mask, wrinkles/acne/shine/dark circles/teeth/eyes
  engines. Performance pass + final audit still pending.
