# ARCHITECTURE.md — Ruxel

## Three worlds

1. **World A — `Packages/EditorCore` (Swift, Foundation only).**
   Builds and tests on Linux (`swift test`). Contains: `RetouchState`
   (Codable models: faces, body, skin, makeup, brush strokes), landmark
   types, warp math (falloff, anisotropic scale, translate, pinch),
   displacement-field math, brush stamping math, mask/color math (sRGB,
   Display P3, Lab), slider -> physical-amount mapping with per-tool safe
   limits, export tiling math (tiles + halo), generic History (undo/redo),
   One-Euro filter (for video later), and a CPU REFERENCE implementation
   (Float buffers) of every shader algorithm. The Python QA harness
   (`tools/qa_harness.py`) is the executable copy of that reference math —
   if Swift and Python ever disagree, the Python reference is the arbiter
   until a test pins the case.
2. **World B — the iOS app (`App/`).** Engine (Metal render graph, Vision
   analysis, ImageIO import/export) / Services / UI (SwiftUI + UIKit for
   the canvas). MVVM, protocols at boundaries (e.g. `FaceLandmarkProviding`
   so warp math can be tested with mock landmarks, no Vision needed).
3. **World C — `tools/` (Python).** QA harness: landmarks via mediapipe
   (or a synthetic grid fallback) on public-domain portraits, CPU
   reference renders to `docs/qa/`, numeric checks (Jacobian, mask
   coverage).

Photo-first, video-ready: the retouch pipeline is a pure function
`(input texture, params, analysis) -> output texture`. Phase 2 will call
it per video frame; do NOT build video now.

## Render graph — ORDER RULE (very important)

1. `source` -> 2. **SOURCE-SPACE retouch** (skin, wrinkles, acne, shine,
   dark circles, teeth, eye enhance, makeup, color brush — all use source
   landmarks and masks) -> 3. **GEOMETRY LAST** (face + body + head warps
   + liquify strokes via one displacement field; background lock) ->
   4. `output` (P3 -> drawable or export).

All passes in ONE command buffer. A dirty-flag graph caches stage
results: dragging a geometry slider re-runs only stage 3; dragging a
skin slider re-runs stages 2+3. Skip neutral stages.

## Warp engine

- One displacement field texture (`rg16Float`) at about half proxy
  resolution (warps are smooth; bilinear upsampling is enough).
- Sliders become WarpOps (type, center, radius, axes, amount) evaluated
  in a compute pass looping over the ops — **cap 64 ops**.
- Brush dabs are stamped into the same field. The model stores sliders +
  strokes in normalized coordinates, so export REPLAYS them analytically
  at full resolution (resolution independent, WYSIWYG). Bicubic
  (Catmull-Rom) sampling at export.
- Inverse mapping: output pixel `p` samples the source at `p + D(p)`.
- **No fold-over:** for the SUMMED displacement of all active ops on a
  dense grid, the Jacobian determinant of `p + D(p)` must stay > 0.05
  everywhere. Slider limits are clamped until it does. Zero sliders =
  exactly zero displacement. Radii are in units of inter-pupil distance
  (IPD) so results are independent of face size and image resolution.
- Falloff: smoothstep, 1 at centre, 0 at/after radius, zero slope at
  both ends. `scaleDisplacement` is defined in `tools/qa_harness.py`.

## Color

- Work in **Display P3**, `rgba16Float` intermediates.
- Blur/frequency ops in gamma-encoded space, color corrections in Lab.
- Convert once, never mix. Tag the output with the right ICC profile.
- Skin smoothing is frequency separation: low = edge-preserving blur,
  `smoothed = low + (src - low) * textureKeep`, blended by the feathered
  skin mask times strength — texture is kept, never plastic skin.

## Performance budgets (non-negotiable: "no lag")

- Slider-to-pixel under 16 ms (8 ms on ProMotion); 60/120 fps pinch/pan;
  cold launch under 1.5 s.
- ADAPTIVE RESOLUTION: ~1.5 MP while a finger is down, full proxy when
  idle, full-res only on export.
- Render on demand (MTKView paused + setNeedsDisplay). No CPU readback
  in the interactive path. Texture pool. Vision and decoding off the main
  thread. Analysis cached on disk.
- Zoom to 800% with crisp re-render of the visible tile. Full-res export
  is TILE-BASED (tiles ~2048 px + halo = kernel radius + max
  displacement), so 48 MP photos never need huge textures.
- Handle memory warnings (free caches), thermal state (drop preview
  quality at `.serious`), low disk space.

## Persistence

- Project = original file + `state.json` (RetouchState) + analysis cache.
- Auto-save after every change (atomic write), crash recovery, project
  manager with thumbnails.

## Diagnostics

- Hidden debug overlay (5 taps on the version label): fps, render ms per
  stage, memory, landmarks overlay, masks overlay, field overlay; plus an
  in-app "copy log" button (logs written to a file).

## Phase 2 (video) — plan only, not built now

Video reuses the photo pipeline as a pure function
`(input texture, params, analysis) -> output texture`, called once per
video frame. Nothing in P0–P7 builds video; this section is the plan so
the photo work stays video-ready.

### Per-frame retouch pipeline reuse

- **Same render graph, same order rule.** Each frame runs the same
  stages as a photo: source -> source-space retouch (skin, makeup,
  color brush) -> geometry last (face/body/head warps via one
  displacement field, background lock) -> output. No video-specific
  shader paths: the kernels, params structs, and dirty-flag graph are
  shared, so a fix to the photo pipeline fixes video too.
- **Analysis cadence.** Vision analysis (faces, person mask, pose) is
  far more expensive than the render. Run full analysis every Nth frame
  (start with every 10th frame at 30 fps, tune by measurement) and
  **track** landmarks between analyses with `VNTrackObjectRequest`
  (VERIFY: tracker availability / accuracy on iOS 16) or by reusing the
  previous frame's landmarks with optical-flow-free prediction. The
  displacement field is smooth, so slightly stale landmarks are
  acceptable; stale skin masks are not — masks are re-derived from the
  tracked face oval when a fresh mask is unavailable.
- **Temporal smoothing with the One-Euro filter.** EditorCore already
  ships a One-Euro filter (see `Packages/EditorCore`). In Phase 2 it
  smooths the *parameter tracks* over time: landmark positions, slider
  amounts, and face pose (yaw/pitch/roll). Fast motion passes through
  (low lag), slow jitter is removed — this is what stops the retouch
  from shimmering frame to frame. One filter instance per tracked scalar;
  cutoff/min-cutoff tuned on real footage (start: minCutoff 1.0, beta
  0.05, then measure).
- **State is per-clip, not per-frame.** `RetouchState` stays the user's
  edit; per-frame analysis results are a separate, ephemeral track
  (landmarks + masks + pose per frame, cached on disk next to the clip,
  evictable). Never persist per-frame analysis inside `state.json`.

### Performance notes

- **Budget per frame at 30 fps is 33 ms, render target under 16 ms**
  (same slider-to-pixel budget as photos, now per frame). Keep the
  adaptive-resolution rule: render at ~1.5 MP while scrubbing or while
  a slider is dragged, full proxy when idle, full-res only on export.
- **Reuse, never re-allocate per frame.** The texture pool (planned in
  P7) becomes mandatory: intermediate textures, the displacement field,
  and the mask textures are pooled and reused across frames. No CPU
  readback in the playback path.
- **Thermal and battery.** Video render is sustained load: watch
  `ProcessInfo.thermalState`; at `.serious`, drop to half proxy
  resolution and skip the skin low-pass; at `.critical`, pause the
  live preview and keep audio + scrubbing. Export runs in the
  background with progress + cancel, tiled like photo export.
- **Export.** Frame-by-frame through the same graph into an
  `AVAssetWriter` pipeline (VERIFY: writer settings for P3 + HEVC on
  iOS 16); audio is passed through untouched. Tiles are unnecessary for
  video (frames are small), but the halo rule still applies to the
  displacement field at frame edges.
- **What stays out of Phase 2.** No video filters library, no
  transitions, no multi-clip timeline — Phase 2 is "retouch this clip",
  nothing more. Keyframed slider changes (different retouch at
  different times) are explicitly out of scope until the per-frame
  pipeline is proven on device.

### Risks to verify first (SDK probe, before writing video code)

- `VNTrackObjectRequest` behavior on iOS 16 for faces (drift, loss).
- `AVAssetWriter` + Metal texture input path (CVPixelBufferPool sharing).
- Whether the macOS CI runner (likely no GPU) can run even a
  smoke-test video render — if not, video correctness comes from the
  CPU reference + on-device testing only.
