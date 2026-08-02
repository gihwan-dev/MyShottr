import AppKit
import Foundation

protocol AppActivating {
    func activateContainingApp(captureID: UUID) async throws
}

enum AppActivationError: Error {
    case containingApplicationNotFound
    case activationFailed
}

struct AppActivator: AppActivating {
    private let executableURL: URL
    private let runningApplicationURLs: () -> [URL]
    private let launchApplication: (URL) async -> Bool
    private let postCaptureReady: (UUID) -> Void

    init(
        executableURL: URL = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments[0]),
        runningApplicationURLs: @escaping () -> [URL] = {
            NSWorkspace.shared.runningApplications.compactMap {
                runningApplication in
                guard !runningApplication.isTerminated else {
                    return nil
                }
                return runningApplication.bundleURL
            }
        },
        launchApplication: @escaping (URL) async -> Bool = { applicationURL in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.createsNewApplicationInstance = false
            configuration.allowsRunningApplicationSubstitution = false

            return await withCheckedContinuation { continuation in
                NSWorkspace.shared.openApplication(
                    at: applicationURL,
                    configuration: configuration
                ) { runningApplication, error in
                    continuation.resume(
                        returning: runningApplication != nil && error == nil
                    )
                }
            }
        },
        postCaptureReady: @escaping (UUID) -> Void = { captureID in
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("com.myshottr.captureReady"),
                object: captureID.uuidString,
                userInfo: nil,
                deliverImmediately: true
            )
        }
    ) {
        self.executableURL = executableURL
        self.runningApplicationURLs = runningApplicationURLs
        self.launchApplication = launchApplication
        self.postCaptureReady = postCaptureReady
    }

    func activateContainingApp(captureID: UUID) async throws {
        guard let applicationURL = containingApplicationURL() else {
            throw AppActivationError.containingApplicationNotFound
        }
        if !applicationIsRunning(at: applicationURL) {
            guard await launchApplication(applicationURL) else {
                throw AppActivationError.activationFailed
            }
        }
        postCaptureReady(captureID)
    }

    private func applicationIsRunning(at applicationURL: URL) -> Bool {
        let expectedURL = canonicalURL(applicationURL)
        return runningApplicationURLs().contains {
            canonicalURL($0) == expectedURL
        }
    }

    private func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
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
