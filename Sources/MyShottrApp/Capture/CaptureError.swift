import CoreGraphics
import Foundation

enum CaptureError: Error, Equatable {
    case screenRecordingPermissionDenied
    case displayUnavailable(CGDirectDisplayID)
    case emptySelection
    case captureAlreadyInProgress
    case captureFailed(String)
    case pngEncodingFailed
}
