import CoreGraphics
import Foundation

enum CaptureError: Error, Equatable {
    case screenRecordingPermissionDenied
    case displayUnavailable(CGDirectDisplayID)
    case emptySelection
    case captureAlreadyInProgress
    case screenCaptureKitFailed
    case pngEncodingFailed
}

enum CaptureWorkflowError: Error, Equatable {
    case selectionFailed
    case projectCreationFailed
    case windowPresenterUnavailable
    case windowPresentationFailed
}
