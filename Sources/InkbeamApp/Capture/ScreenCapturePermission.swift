import CoreGraphics

protocol ScreenCapturePermissionProviding {
    func requireAccess() throws
}

struct ScreenCapturePermission: ScreenCapturePermissionProviding {
    private let preflight: () -> Bool
    private let request: () -> Bool

    init(
        preflight: @escaping () -> Bool = CGPreflightScreenCaptureAccess,
        request: @escaping () -> Bool = CGRequestScreenCaptureAccess
    ) {
        self.preflight = preflight
        self.request = request
    }

    func requireAccess() throws {
        guard !preflight() else {
            return
        }

        guard request() else {
            throw CaptureError.screenRecordingPermissionDenied
        }
    }
}
