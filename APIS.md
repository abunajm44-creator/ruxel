# APIS.md — Apple APIs used (or planned) by Ruxel

**Zero-guess rule:** nothing here is trusted from memory. Every entry
must be verified against the real iOS SDK with the `sdk-probe` workflow
before code depends on it. Status `to verify via SDK probe` means exactly
that — do not write the call until the probe confirms the signature.

| Type | Signature (as currently believed — VERIFY) | Min iOS | Status |
|------|----------------------------------------------|---------|--------|
| Metal | `MTLCreateSystemDefaultDevice() -> MTLDevice?` | 8.0 | to verify via SDK probe |
| Metal | `MTLDevice.makeComputePipelineState(function:) throws -> MTLComputePipelineState` | 8.0 | to verify via SDK probe |
| Metal | `MTLDevice.makeDefaultLibrary() -> MTLLibrary?` | 8.0 | to verify via SDK probe |
| Metal | `MTLCommandQueue.makeCommandBuffer() -> MTLCommandBuffer?` | 8.0 | to verify via SDK probe |
| PhotosUI | `PHPickerViewController` / `PHPickerConfiguration` | 14.0 | to verify via SDK probe |
| PhotosUI | `PHPickerResult.itemProvider.loadFileRepresentation(forTypeIdentifier:completionHandler:)` | 14.0 | to verify via SDK probe |
| Vision | `VNDetectFaceLandmarksRequest` (contours, eyes, brows, nose, lips, pupils) | 11.0 | to verify via SDK probe |
| Vision | `VNFaceLandmarkRegion2D` (normalized points) | 11.0 | to verify via SDK probe |
| Vision | `VNGeneratePersonSegmentationRequest` (`.accurate`) | 15.0 | to verify via SDK probe |
| Vision | `VNGenerateForegroundInstanceMaskRequest` (per-person masks) | 17.0 | to verify via SDK probe (gate with `if #available`) |
| Vision | `VNDetectHumanBodyPoseRequest` (joints + confidence) | 14.0 | to verify via SDK probe |
| ImageIO | `CGImageSourceCreateThumbnailAtIndex(_:_:_:_:) -> CGImage?` | 4.0 | to verify via SDK probe |
| ImageIO | `kCGImageSourceCreateThumbnailWithTransform`, `kCGImageSourceThumbnailMaxPixelSize` | 4.0 | to verify via SDK probe |
| SwiftUI | `View.glassEffect(_:in:)` / `Glass.regular`, `Glass.tint(_:)`, `Glass.interactive()` | 26.0 | to verify via SDK probe (gate with `if #available`, `.ultraThinMaterial` fallback) |
| SwiftUI | `GlassEffectContainer` / `glassEffectID(_:in:)` | 26.0 | to verify via SDK probe |

## Probe batches already planned

Batch 1 (Vision): `VNDetectFaceLandmarksRequest|||VNFaceLandmarkRegion2D|||VNGeneratePersonSegmentationRequest|||VNDetectHumanBodyPoseRequest`
Batch 2 (Metal): `MTLCreateSystemDefaultDevice|||makeComputePipelineState|||makeDefaultLibrary`
Batch 3 (PhotosUI/ImageIO): `PHPickerViewController|||loadFileRepresentation|||CGImageSourceCreateThumbnailAtIndex`
Batch 4 (Glass, iOS 26): `glassEffect|||struct Glass|||GlassEffectContainer`

Run via the `sdk-probe` workflow (Actions → sdk-probe → Run workflow),
one batch per run, and record the confirmed signatures here.
