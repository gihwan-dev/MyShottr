import AppKit
import Foundation

protocol AppActivating {
    func activateContainingApp() throws
}

enum AppActivationError: Error {
    case containingApplicationNotFound
    case activationFailed
}

struct AppActivator: AppActivating {
    private let executableURL: URL
    private let openApplication: (URL) -> Bool

    init(
        executableURL: URL = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments[0]),
        openApplication: @escaping (URL) -> Bool = {
            NSWorkspace.shared.open($0)
        }
    ) {
        self.executableURL = executableURL
        self.openApplication = openApplication
    }

    func activateContainingApp() throws {
        guard let applicationURL = containingApplicationURL() else {
            throw AppActivationError.containingApplicationNotFound
        }
        guard openApplication(applicationURL) else {
            throw AppActivationError.activationFailed
        }
    }

    private func containingApplicationURL() -> URL? {
        var candidate = executableURL.standardizedFileURL.deletingLastPathComponent()

        while true {
            let infoPlist = candidate
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Info.plist")
            if
                candidate.pathExtension == "app",
                FileManager.default.fileExists(atPath: infoPlist.path)
            {
                return candidate
            }

            let parent = candidate.deletingLastPathComponent()
            guard parent != candidate else {
                return nil
            }
            candidate = parent
        }
    }
}
