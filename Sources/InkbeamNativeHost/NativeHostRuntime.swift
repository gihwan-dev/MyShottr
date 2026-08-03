import Foundation

#if DEBUG
enum NativeHostTestEnvironment {
    static let inboxPathKey = "INKBEAM_NATIVE_HOST_TEST_INBOX"
    static let appPathKey = "INKBEAM_NATIVE_HOST_TEST_APP_PATH"
    static let notificationKey = "INKBEAM_NATIVE_HOST_TEST_NOTIFICATION"
}

struct NativeHostTestConfiguration: Equatable {
    let inboxURL: URL
    let applicationURL: URL
    let notification: Notification.Name
}

private struct NativeHostTestActivator: AppActivating {
    let applicationURL: URL
    let notification: Notification.Name

    func activateContainingApp(captureID: UUID) async throws {
        let infoPlistURL = applicationURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist")
        guard FileManager.default.fileExists(atPath: infoPlistURL.path) else {
            throw AppActivationError.containingApplicationNotFound
        }
        DistributedNotificationCenter.default().postNotificationName(
            notification,
            object: captureID.uuidString,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}
#endif

enum NativeHostRuntime {
    static func makeRunner(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> HostRunner {
        #if DEBUG
        if let configuration = testConfiguration(environment: environment) {
            return HostRunner(
                staging: HostInboxStore(
                    rootURL: configuration.inboxURL
                ),
                activator: NativeHostTestActivator(
                    applicationURL: configuration.applicationURL,
                    notification: configuration.notification
                )
            )
        }
        #endif

        return HostRunner(
            staging: HostInboxStore(),
            activator: AppActivator()
        )
    }

    #if DEBUG
    static func testConfiguration(
        environment: [String: String]
    ) -> NativeHostTestConfiguration? {
        let keys = [
            NativeHostTestEnvironment.inboxPathKey,
            NativeHostTestEnvironment.appPathKey,
            NativeHostTestEnvironment.notificationKey,
        ]
        guard keys.contains(where: { environment[$0] != nil }) else {
            return nil
        }
        guard
            let inboxPath = environment[
                NativeHostTestEnvironment.inboxPathKey
            ],
            let appPath = environment[
                NativeHostTestEnvironment.appPathKey
            ],
            let notification = environment[
                NativeHostTestEnvironment.notificationKey
            ],
            inboxPath.hasPrefix("/"),
            appPath.hasPrefix("/"),
            !notification.isEmpty
        else {
            preconditionFailure(
                "Injected native-host test environment must provide exact "
                    + "absolute inbox and app paths plus a notification"
            )
        }
        return NativeHostTestConfiguration(
            inboxURL: URL(
                fileURLWithPath: inboxPath,
                isDirectory: true
            ).standardizedFileURL,
            applicationURL: URL(
                fileURLWithPath: appPath,
                isDirectory: true
            ).standardizedFileURL,
            notification: Notification.Name(notification)
        )
    }
    #endif
}
