import AppKit
import CoreGraphics

protocol ScreenCapturePermissionProviding {
    func requireAccess() throws
}

struct ScreenCapturePermission: ScreenCapturePermissionProviding {
    private let preflight: () -> Bool
    private let request: () -> Bool
    private let openSettings: () -> Void

    init(
        preflight: @escaping () -> Bool = CGPreflightScreenCaptureAccess,
        request: @escaping () -> Bool = CGRequestScreenCaptureAccess,
        openSettings: @escaping () -> Void = Self.openScreenRecordingSettings
    ) {
        self.preflight = preflight
        self.request = request
        self.openSettings = openSettings
    }

    func requireAccess() throws {
        guard !preflight() else {
            return
        }

        guard request() else {
            openSettings()
            throw CaptureError.screenRecordingPermissionDenied
        }
    }

    private static func openScreenRecordingSettings() {
        guard let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else {
            return
        }

        NSWorkspace.shared.open(settingsURL)
    }
}
