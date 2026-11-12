# FEATURES.md — Ruxel feature list

Status words allowed: `not done` / `partial` / `done` / `broken`.
**Rule: NEVER mark anything `done` without a green CI build, unit tests
with a CPU reference, and reviewed QA images.** P0 items are `partial`
until CI is green — everything else is `not done`.

Note on sources: the 19-tool list below is taken from the task brief's
reading of the 7 reference screenshots. The screenshots themselves were
not available in this session, so this list has NOT been independently
re-verified against them yet — re-check it against the screenshots before
treating the details (tab names, option lists) as final. Source
`my-image` = seen in the reference screenshots; `baseline` = standard
retouch-app capability expected even if not in the screenshots.

## The 19 tools (from the reference screenshots)

| # | Feature | Source | Priority | Status |
|---|---------|--------|----------|--------|
| 1 | Sparkle brushes (creative glow/glitter brushes) | my-image | P4 | partial — render pass BUILT 2026-11-12 (overlay blend kernel + photo-space rasterizer; glow/glitter/star stamps); needs a green CI build to claim more |
| 2 | Teeth (whitening) | my-image | P2 | not done |
| 3 | Auto (one-tap auto retouch) | my-image | P1 | partial — one-tap preset exists (smoothing 45 / texture 70 / shine 50 / wrinkle 40); the shine/wrinkle parts have no engine yet |
| 4 | Makeup | my-image | P2 | partial — UI ready (5 regions, color picker, intensity, matte/satin/glossy) wired to EditorCore MakeupAdjustments; Lab luminance-preserving blend + render-graph makeup pass NOT built, so nothing appears on the photo yet |
| 5 | Face reshape | my-image | P1 | partial — warp engine built (32 sliders, faceWarpOps); DIRECTION BUG FIXED 2026-11-12: translate + pinch ops were inverted (backward-map sign) — nose lift moved the nose DOWN. Fixed in WarpMath + Metal + BrushEngine, proven by rendered-motion unit tests; needs a green CI build |
| 6 | Slim | my-image | P2 | partial — body warp engine built (horizontal pinch capsules); the pinch direction was inverted with the same bug, fixed 2026-11-12; needs a green CI build |
| 7 | Body sculpt | my-image | P2 | partial — body warp engine built (waist pinch, hips scale, leg translate, shoulders, neck); translate/pinch directions fixed 2026-11-12; needs a green CI build |
| 8 | Smoothing | my-image | P1 | partial — live smoothing WORKS since 2026-11-12: the view model builds the skin-mask texture (person mask AND face oval) after analysis, so the stage-2 blend has a real mask; export does the full version (likelihood + feather + grain) |
| 9 | Skin (tone / glow) | my-image | P1 | partial — smoothing + grain live (see #8); tone/glow sliders have no dedicated engine yet |
| 10 | Wrinkles (removal) | my-image | P2 | not done |
| 11 | Lift / tighten | my-image | P3 | partial — engine BUILT 2026-11-12 (headLiftWarpOps: lift = upward translate at the jaw, tighten = pinch at face center; live + export + debug overlay share one helper); needs a green CI build |
| 12 | Color brush (paint brush) | my-image | P3 | partial — render pass BUILT 2026-11-12 (overlay blend kernel + photo-space rasterizer; strokes move with the warp because the blend runs in source space); intensity defaults to 100 so paint is visible; needs a green CI build |
| 13 | Acne (removal) | my-image | P2 | not done |
| 14 | Shine (removal) | my-image | P2 | not done |
| 15 | Head (size / shape) | my-image | P3 | partial — engine BUILT 2026-11-12 (headLiftWarpOps: radial + horizontal scale about the face center, IPD-based radii); needs a green CI build |
| 16 | Eyes (enhance) | my-image | P2 | not done |
| 17 | Dark circles (removal) | my-image | P2 | not done |
| 18 | Hair (hairstyles) | my-image | P4 | partial — UI built (recolor/volume/flyaway) but DISABLED: no hair mask exists (AnalysisService requests no AVSemanticSegmentationMatte); honest "unavailable" message shown; engine NOT built |
| 19 | Object eraser | my-image | P4 | partial — mask UI works (paint mask, size, clear); PatchMatch inpainting engine NOT built; Apply is deliberately DISABLED and the UI says so — never presented as working removal |

## Face tool tabs and sub-options

| Feature | Source | Priority | Status |
|---------|--------|----------|--------|
| Face tabs: 3D / Face / Brows / Eyes / Nose / Lips | my-image | P1 (Face/Eyes/Nose/Lips/Brows), P4 (3D tab) | partial — Face/Eyes/Nose/Lips/Brows tabs drive the warp engine (32 sliders, direction fixed 2026-11-12); 3D tab sliders drive yaw/pitch/roll attenuation in the same engine; on-device behavior pending the user's test |
| Eyes options: size, height, width, length, distance, puffy eyes | my-image | P1 | not done |
| Nose options: size, lift, ala, root, bridge, tip | my-image | P1 | not done |
| Lips options: size, width, thickness, smile, position, M-shape | my-image | P1 | not done |
| Brows options: height, distance, thickness, angle, length, shape | my-image | P1 | not done |
| Face options: width, jaw, chin, cheekbones, temples, forehead height, face length, V-shape | my-image | P1 | not done |
| Multi-face selector (scope chip General / Left / Right) | my-image | P3 | partial — face picker chip (Face 1/2/3...) appears when >1 face has adjustments; scope chip now applies to the SELECTED face and FaceToolView sliders target it; caveat: analysis does not populate state.faces, so the picker only lists faces that already have adjustments — a face-count signal from AnalysisService is still needed for picker-before-edit |

## Common controls and app shell

| Feature | Source | Priority | Status |
|---------|--------|----------|--------|
| Compare (hold to see original) | my-image | P1 | partial — long-press compare renders the neutral state AND neutral extras; on-device behavior pending the user's test |
| Undo / redo (history) | my-image | P1 | partial — snapshot history (one undo step per drag/stroke) + Cancel/Apply semantics wired; on-device behavior pending the user's test |
| Export (HEIC/JPEG/PNG, P3 + EXIF) | my-image | P1 | partial — tile-based full-res CPU export (skin + warp + color grade + overlay + head/lift + crop post-process); on-device behavior pending the user's test |
| Background lock toggle | my-image | P2 | partial — warp field multiplied by the person mask when on; on-device behavior pending the user's test |
| Distortion correction toggle (greyed out when not applicable) | my-image | P3 | partial — toggle + "?" help popover + strength slider (0...100) in the editor; greyed out when no face or body is found (hasFaceOrBody) |
| Manual / Auto brush modes: Classic / Fast / Restore, size 5 stops | my-image | P2 | partial — brush engine built (Catmull-Rom, dab spacing, push/restore); push direction FIXED 2026-11-12 (was inverted: dragging right moved content left); on-device behavior pending the user's test |
| Bipolar sliders -100..100 with centre detent | my-image | P1 | partial — BipolarSlider component with detent + haptic tick; on-device behavior pending the user's test |
| Project manager + auto-save + crash recovery | baseline | P1 | partial — ProjectStore (state + extras, autosave, legacy migration) + committed-snapshot cancel; project grid exists; on-device behavior pending the user's test |
| Import (PHPicker, HEIC/JPEG/PNG, Live Photo still, orientation) | baseline | P1 | partial — PHPicker import + proxy build; on-device behavior pending the user's test |
| Metal canvas (pinch/pan/zoom to 800%) | baseline | P1 | partial — MTKView canvas with pinch/pan/double-tap/long-press compare; render graph stages 2/2.5/3/3.5 + dirty flags; on-device behavior pending the user's test |
| Liquid Glass shell (home + empty editor), iOS 26 glass with iOS 16 fallback | baseline | P0 | partial — ships in build-8 (green CI); on-device launch pending the user's test |
| Diagnostics overlay + in-app copy-log | baseline | P2 | not done |
| Arabic + English localization, VoiceOver labels | baseline | P7 | partial — 227 keys in ar + en, identical sets (verified by script); every new control has a VoiceOver label; BipolarSlider hit area raised to 44pt; back button raised to 44pt; ships in build-8 (green CI) |
| App icon (original, generated programmatically) | baseline | P7 | partial — generated by tools/generate_icon.py (Pillow): original gradient + pixel-face motif, 8 sizes (40–1024px) + Contents.json; visually checked at 1024px; not yet seen on a real device home screen |
| Paint overlay (shared color/erase/sparkle surface) | baseline | P5/P6 | partial — PaintCanvasView + PaintOverlayView: pan painting, normalized strokes, one undo step per stroke, clear buttons; strokes are rasterized into photo space by OverlayBuilder (photo rect from canvas size), so the render + export sample them directly; painting also pauses canvas pinch/pan while a paint tool is open |

## Baseline extras

| Feature | Source | Priority | Status |
|---------|--------|----------|--------|
| Crop / rotate | baseline | P6 | partial — render pass BUILT 2026-11-12 (UV rotate + aspect crop in the live colorGrade kernel; centered crop + rotation post-process in export; rotated export corners are black, live preview edge-stretches them); needs a green CI build |
| Basic adjust (exposure, contrast, saturation, warmth) | baseline | P6 | partial — render pass BUILT 2026-11-12 (colorGrade kernel + CPU export mirror, one canonical math in EditorCore ColorGrade with 13 unit tests); needs a green CI build |
| Filters | baseline | P6 | partial — render pass BUILT 2026-11-12 (6 presets as fixed slider mixes folded into the grade, scaled by intensity; mono desaturates); needs a green CI build |

## Milestones (each builds green and ships a verified IPA)

- **P0 — DONE (2026-11-12):** repo + XcodeGen + EditorCore + CI + shell + IPA verified. Release "Build 8" (tag build-8): complete bundle (executable + Assets.car + AppIcon + en/ar Localizable.strings), verified by `unzip -l`, delivered to the user's laptop Desktop + chat.
- **P1:** import, Metal canvas (pinch/pan/zoom), compare, undo/redo, export, project manager, Display P3 + orientation done right. Code built; green in CI (builds #3–#8 compile); on-device behavior pending the user's test.
- **P2:** analysis (faces, person mask) + debug overlays + face reshape engine with Eyes/Nose/Lips/Brows/Face tabs + QA harness images. Engine built; warp direction bug fixed 2026-11-12 (see #5); on-device behavior pending the user's test.
- **P3:** skin engine (mask, smoothing, texture) + Auto + Skin + Smooth + wrinkles/acne/shine/dark circles + teeth + eye enhance. Smoothing + grain live; wrinkles/acne/shine/dark circles/teeth/eyes have no engine yet (not done).
- **P4:** body (pose, slim, sculpt, manual brush Classic/Fast/Restore) + background lock. Engine built; brush push direction fixed 2026-11-12; on-device behavior pending the user's test.
- **P5:** makeup, color brush, head, lift and tighten, distortion correction, multi-face selector. Color brush + head + lift engines BUILT 2026-11-12 (need green CI); makeup pass NOT built; distortion + multi-face UI wired.
- **P6:** object eraser, hair (experimental), sparkle brushes, 3D tab, crop/rotate, basic adjust, filters. Sparkle + crop/rotate + basic adjust + filters engines BUILT 2026-11-12 (need green CI); eraser inpainting NOT built (honest stub); hair disabled (no mask); 3D attenuation works through the face warp ops.
- **P7:** polish — localization, accessibility, performance pass, icon, README (Arabic + English), final FEATURES.md, Phase 2 (video) plan in ARCHITECTURE.md. Partial: icon + README + localization (227 keys) + a11y pass done; CI debug step removed 2026-11-12; performance pass + final audit still pending.

## P5–P7 status (2026-11-12, this session)

- **P5: partial.** Color brush, head and lift now have real render-engine
  passes (overlay blend kernel, headLiftWarpOps); makeup still has UI +
  stored state only — its Lab blend pass is NOT built.
- **P6: partial.** Sparkle, crop/rotate, basic adjust and filters now
  have real render-engine passes (colorGrade kernel + CPU export
  mirror). Eraser mask UI works but inpainting is NOT built and Apply
  is disabled (honest stub). Hair is built but fully disabled (no hair
  mask). 3D tab sliders drive the face warp attenuation (built).
- **P7: partial.** Icon generated + README written + ARCHITECTURE Phase 2
  plan expanded + localization at 227 keys + accessibility pass on new
  controls + CI debug step removed. Still missing: performance pass,
  final audit, green CI build for the new passes (nothing here is
  `done` until CI is green).
