import Foundation

enum BrowserCaptureMode: String, Codable {
    case visibleViewport
    case fullPage
}

struct NativeCaptureMessage: Codable {
    let protocolVersion: Int
    let type: String
    let captureMode: BrowserCaptureMode
    let mimeType: String
    let dataBase64: String
}

enum NativeHostErrorCode: String, Codable {
    case invalidMessage = "INVALID_MESSAGE"
    case unsupportedCaptureMode = "UNSUPPORTED_CAPTURE_MODE"
    case invalidImage = "INVALID_IMAGE"
    case imageTooLarge = "IMAGE_TOO_LARGE"
    case stagingFailed = "STAGING_FAILED"
    case appActivationFailed = "APP_ACTIVATION_FAILED"
}

struct NativeHostReply: Codable, Equatable {
    let ok: Bool
    let captureId: UUID?
    let code: NativeHostErrorCode?
}

protocol HostCaptureStaging {
    func stage(pngData: Data) throws -> UUID
}
