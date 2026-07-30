import Foundation

#if DEBUG
enum NativeHostTestEnvironment {
    static let inboxPathKey = "MYSHOTTR_NATIVE_HOST_TEST_INBOX"
    static let activationFailureKey =
        "MYSHOTTR_NATIVE_HOST_TEST_ACTIVATION_FAILURE"
}

private struct NativeHostTestActivator: AppActivating {
    let shouldFail: Bool

    func activateContainingApp(captureID _: UUID) throws {
        if shouldFail {
            throw AppActivationError.activationFailed
        }
    }
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
            let shouldFailActivation =
                environment[
                    NativeHostTestEnvironment.activationFailureKey
                ] == "1"
            return HostRunner(
                staging: HostInboxStore(
                    rootURL: URL(
                        fileURLWithPath: inboxPath,
                        isDirectory: true
                    ).standardizedFileURL
                ),
                activator: NativeHostTestActivator(
                    shouldFail: shouldFailActivation
                )
            )
        }
        #endif

        return HostRunner(
            staging: HostInboxStore(),
            activator: AppActivator()
        )
    }
}
