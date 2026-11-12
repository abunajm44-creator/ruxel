// PhotoImportService — imports a picked photo and builds the proxy.
// What: PHPicker file copy + EXIF-normalized 2048px proxy via ImageIO.
// Inputs-outputs: PHPickerResult -> copied original URL + proxy CGImage.
// Threading: loadPhoto is async; proxy building runs off the main thread.

import Foundation
import PhotosUI
import UniformTypeIdentifiers
import ImageIO
import UIKit
final class PhotoImportService {
    private let fileManager = FileManager.default

    /// Copies the picked image into `dir`. The picker's temp file disappears
    /// when the callback returns, so the copy happens inside the callback.
    func loadPhoto(from result: PHPickerResult, into dir: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            // VERIFY: PHPickerViewController preferredAssetRepresentationMode = .current
            result.itemProvider.loadFileRepresentation(
                forTypeIdentifier: UTType.image.identifier
            ) { url, error in
                guard let url else {
                    continuation.resume(throwing: error ?? AppError.photoLoadFailed)
                    return
                }
                let dest = dir
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)
                do {
                    try FileManager.default.copyItem(at: url, to: dest)
                    continuation.resume(returning: dest)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Builds the interactive proxy (long edge 2048) with EXIF orientation
    /// normalized in this one place. Never decodes the full photo for preview.
    /// Supports HEIC, JPEG and PNG; a Live Photo contributes its still image.
    func makeProxy(from fileURL: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            throw AppError.photoLoadFailed
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw AppError.photoLoadFailed
        }
        return thumbnail
    }

    /// Returns the UTType of a file, or nil when it cannot be determined.
    func imageType(of fileURL: URL) -> UTType? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let type = CGImageSourceGetType(source) else { return nil }
        return UTType(type as String)
    }

    /// A PHPicker configuration for photos only, current representation.
    static func pickerConfiguration() -> PHPickerConfiguration {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        // VERIFY: PHPickerConfiguration.preferredAssetRepresentationMode = .current
        configuration.preferredAssetRepresentationMode = .current
        return configuration
    }
}
