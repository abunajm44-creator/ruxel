import Foundation

// AppErrors — typed, user-facing errors with Arabic messages for the UI.
// What: one error enum per layer; every case carries a friendly Arabic string.
// Inputs-outputs: thrown by services; the UI shows localizedDescription.
// Threading: value types; safe to pass across threads.
enum AppError: LocalizedError {
    case photoAccessDenied
    case photoLoadFailed
    case unsupportedFormat
    case exportFailed
    case saveFailed
    case analysisUnavailable
    case noFaceFound
    case projectCorrupted
    case diskFull
    case cancelled

    var errorDescription: String? {
        switch self {
        case .photoAccessDenied:
            return "لا يمكن الوصول إلى الصور. فعّل الإذن من الإعدادات ثم حاول مجدداً."
        case .photoLoadFailed:
            return "تعذّر تحميل هذه الصورة. جرّب صورة أخرى."
        case .unsupportedFormat:
            return "صيغة هذه الصورة غير مدعومة. جرّب JPEG أو HEIC أو PNG."
        case .exportFailed:
            return "تعذّر تصدير الصورة. تحقّق من المساحة المتوفرة وحاول مجدداً."
        case .saveFailed:
            return "تعذّر حفظ المشروع. تحقّق من المساحة المتوفرة وحاول مجدداً."
        case .analysisUnavailable:
            return "تعذّر تحليل الصورة الآن. يمكنك المتابعة بالأدوات اليدوية."
        case .noFaceFound:
            return "لم نعثر على وجه في هذه الصورة. أدوات الوجه متوقفة، والأدوات اليدوية ما زالت تعمل."
        case .projectCorrupted:
            return "ملف المشروع تالف ولا يمكن فتحه."
        case .diskFull:
            return "لا توجد مساحة كافية على الجهاز."
        case .cancelled:
            return "تم الإلغاء."
        }
    }

    /// English counterpart, used where the UI is in English.
    var englishDescription: String {
        switch self {
        case .photoAccessDenied:
            return "Photos access is denied. Enable it in Settings and try again."
        case .photoLoadFailed:
            return "This photo could not be loaded. Try another photo."
        case .unsupportedFormat:
            return "This image format is not supported. Try JPEG, HEIC or PNG."
        case .exportFailed:
            return "Export failed. Check free space and try again."
        case .saveFailed:
            return "The project could not be saved. Check free space and try again."
        case .analysisUnavailable:
            return "Analysis is unavailable right now. Manual tools still work."
        case .noFaceFound:
            return "No face was found in this photo. Face tools are disabled; manual tools still work."
        case .projectCorrupted:
            return "This project file is damaged and cannot be opened."
        case .diskFull:
            return "There is not enough free space on this device."
        case .cancelled:
            return "Cancelled."
        }
    }
}
