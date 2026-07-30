import Foundation

#if DEBUG
enum NativeHostTestEnvironment {
    static let inboxPathKey = "MYSHOTTR_NATIVE_HOST_TEST_INBOX"
}

private struct NativeHostTestActivator: AppActivating {
    func activateContainingApp(captureID _: UUID) throws {}
}
#endif

enum NativeHostRuntime {
    static func makeRunner(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> HostRunner {
        #if DEBUG
        if let inboxPath = environment[NativeHostTestEnvironment.inboxPathKey] {
            precondition(
                inboxPath.hasPrefix("/"),
                "Injected native-host test inbox must be absolute"
            )
            return HostRunner(
                staging: HostInboxStore(
                    rootURL: URL(
                        fileURLWithPath: inboxPath,
                        isDirectory: true
                    ).standardizedFileURL
                ),
                activator: NativeHostTestActivator()
            )
        }
        #endif

        return HostRunner(
            staging: HostInboxStore(),
            activator: AppActivator()
        )
    }
}
