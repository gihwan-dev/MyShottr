import Darwin
import Foundation
import Sparkle
import XCTest
@testable import Inkbeam

@MainActor
final class UpdaterConsentIntegrationTests: TemporaryDirectoryTestCase {
    func testRealSparkleSecondLaunchPersistsApprovalAndSchedulesTheBuiltInterval() throws {
        let profile = try SparkleHostProfile(directory: temporaryDirectory)

        let firstDriver = RecordingUserDriver()
        let firstDelegate = RecordingUpdaterDelegate()
        try startRealUpdater(profile: profile, driver: firstDriver, delegate: firstDelegate)
        pumpMainRunLoop()
        XCTAssertEqual(firstDriver.permissionRequests, 0, "launch 1 must not ask for consent")
        XCTAssertEqual(profile.defaults.bool(forKey: "SUHasLaunchedBefore"), true)

        let secondDriver = RecordingUserDriver()
        let secondDelegate = RecordingUpdaterDelegate()
        try startRealUpdater(profile: profile, driver: secondDriver, delegate: secondDelegate)
        waitForPermissionRequest(from: secondDriver)
        XCTAssertNil(profile.defaults.object(forKey: "SUEnableAutomaticChecks"))
        profile.defaults.set(Date(), forKey: "SULastCheckTime")

        secondDriver.replyToPermission(
            automaticChecks: true,
            automaticDownloads: false,
            sendsSystemProfile: false
        )
        waitForSchedule(from: secondDelegate)

        XCTAssertEqual(profile.defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool, true)
        XCTAssertEqual(secondDelegate.scheduledDelays.count, 1)
        XCTAssertEqual(secondDelegate.scheduledDelays[0], 86_400, accuracy: 1)

        let thirdDriver = RecordingUserDriver()
        let thirdDelegate = RecordingUpdaterDelegate()
        try startRealUpdater(profile: profile, driver: thirdDriver, delegate: thirdDelegate)
        pumpMainRunLoop()
        XCTAssertEqual(thirdDriver.permissionRequests, 0, "launch 3 must retain the real Sparkle decision")
    }

    func testRealSparkleSecondLaunchPersistsDeclineAndNeverSchedules() throws {
        let profile = try SparkleHostProfile(directory: temporaryDirectory)
        try startRealUpdater(
            profile: profile,
            driver: RecordingUserDriver(),
            delegate: RecordingUpdaterDelegate()
        )
        pumpMainRunLoop()

        let decliningDriver = RecordingUserDriver()
        let decliningDelegate = RecordingUpdaterDelegate()
        try startRealUpdater(
            profile: profile,
            driver: decliningDriver,
            delegate: decliningDelegate
        )
        waitForPermissionRequest(from: decliningDriver)
        decliningDriver.replyToPermission(
            automaticChecks: false,
            automaticDownloads: false,
            sendsSystemProfile: false
        )
        pumpMainRunLoop(until: 0.2)

        XCTAssertEqual(profile.defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool, false)
        XCTAssertEqual(decliningDelegate.scheduledDelays, [])
        XCTAssertEqual(decliningDelegate.didRefuseScheduling, 1)

        let thirdDriver = RecordingUserDriver()
        try startRealUpdater(
            profile: profile,
            driver: thirdDriver,
            delegate: RecordingUpdaterDelegate()
        )
        pumpMainRunLoop()
        XCTAssertEqual(thirdDriver.permissionRequests, 0, "a decline must suppress later prompts")
    }

    func testRealSparkleApprovalIssuesOneLoopbackFeedGETAtTheRequestBoundary() throws {
        let server = try LoopbackFeedServer()
        let feedURL = "http://127.0.0.1:\(server.port)/inkbeam/appcast.xml"
        let profile = try SparkleHostProfile(directory: temporaryDirectory, feedURL: feedURL)

        try startRealUpdater(profile: profile, driver: RecordingUserDriver(), delegate: RecordingUpdaterDelegate())
        pumpMainRunLoop()

        let secondDriver = RecordingUserDriver()
        try startRealUpdater(profile: profile, driver: secondDriver, delegate: RecordingUpdaterDelegate())
        waitForPermissionRequest(from: secondDriver)
        let requestExpectation = expectation(description: "Sparkle feed request")
        server.onRequest = { _ in requestExpectation.fulfill() }
        secondDriver.replyToPermission(automaticChecks: true, automaticDownloads: false, sendsSystemProfile: false)
        wait(for: [requestExpectation], timeout: 3)

        let requests = server.requests
        XCTAssertEqual(requests.count, 1)
        let record = try XCTUnwrap(requests.first)
        let request = record.request
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.scheme, "http")
        XCTAssertEqual(request.url?.host, "127.0.0.1")
        XCTAssertEqual(request.url?.port, server.port)
        XCTAssertEqual(request.url?.path, "/inkbeam/appcast.xml")
        XCTAssertNil(request.url?.query)
        XCTAssertLessThan(abs(record.timestamp.timeIntervalSinceNow), 3)
    }

    private func startRealUpdater(
        profile: SparkleHostProfile,
        driver: RecordingUserDriver,
        delegate: RecordingUpdaterDelegate
    ) throws {
        let updater = SPUUpdater(
            hostBundle: profile.bundle,
            applicationBundle: profile.bundle,
            userDriver: driver,
            delegate: delegate
        )
        profile.retain(updater: updater, driver: driver, delegate: delegate)
        XCTAssertNoThrow(try updater.start())
    }

    private func waitForPermissionRequest(from driver: RecordingUserDriver) {
        let expectation = expectation(description: "Sparkle permission request")
        driver.onPermissionRequest = { expectation.fulfill() }
        wait(for: [expectation], timeout: 2)
    }

    private func waitForSchedule(from delegate: RecordingUpdaterDelegate) {
        let expectation = expectation(description: "Sparkle scheduled update check")
        delegate.onSchedule = { expectation.fulfill() }
        wait(for: [expectation], timeout: 3)
    }

    private func pumpMainRunLoop(until duration: TimeInterval = 0.05) {
        RunLoop.main.run(until: Date().addingTimeInterval(duration))
    }
}

@MainActor
private final class RecordingUserDriver: NSObject, SPUUserDriver {
    private var permissionReply: ((SUUpdatePermissionResponse) -> Void)?
    var permissionRequests = 0
    var onPermissionRequest: (() -> Void)?

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        permissionRequests += 1
        permissionReply = reply
        onPermissionRequest?()
    }

    func replyToPermission(
        automaticChecks: Bool,
        automaticDownloads: Bool,
        sendsSystemProfile: Bool
    ) {
        let reply = try! XCTUnwrap(permissionReply)
        permissionReply = nil
        reply(SUUpdatePermissionResponse(
            automaticUpdateChecks: automaticChecks,
            automaticUpdateDownloading: NSNumber(value: automaticDownloads),
            sendSystemProfile: sendsSystemProfile
        ))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {}
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {}
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() {}
}

@MainActor
private final class RecordingUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    var scheduledDelays: [TimeInterval] = []
    var didRefuseScheduling = 0
    var onSchedule: (() -> Void)?

    func updater(_ updater: SPUUpdater, willScheduleUpdateCheckAfterDelay delay: TimeInterval) {
        scheduledDelays.append(delay)
        onSchedule?()
    }

    func updaterWillNotScheduleUpdateCheck(_ updater: SPUUpdater) {
        didRefuseScheduling += 1
    }
}

private final class SparkleHostProfile {
    let bundle: Bundle
    let defaults: UserDefaults
    private let suiteName: String
    private var retainedObjects: [AnyObject] = []

    init(directory: URL, feedURL: String? = nil) throws {
        suiteName = "dev.gihwan.inkbeam.tests.sparkle.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let bundleURL = directory.appendingPathComponent("Host.app")
        let contentsURL = bundleURL.appendingPathComponent("Contents")
        let macOSURL = contentsURL.appendingPathComponent("MacOS")
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try Data().write(to: macOSURL.appendingPathComponent("Host"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: macOSURL.appendingPathComponent("Host").path)
        let productionInfo = try XCTUnwrap(Bundle(for: AppDelegate.self).infoDictionary)
        let effectiveFeedURL = try XCTUnwrap(feedURL ?? productionInfo["SUFeedURL"] as? String)
        let info: [String: Any] = [
            "CFBundleIdentifier": suiteName,
            "CFBundleName": "Sparkle Test Host",
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": "Host",
            "CFBundleShortVersionString": "0.2.0",
            "CFBundleVersion": "1",
            "SUDefaultsDomain": suiteName,
            "SUFeedURL": effectiveFeedURL,
            "SUPublicEDKey": try XCTUnwrap(productionInfo["SUPublicEDKey"]),
            "SUScheduledCheckInterval": try XCTUnwrap(productionInfo["SUScheduledCheckInterval"]),
            "SUAutomaticallyUpdate": try XCTUnwrap(productionInfo["SUAutomaticallyUpdate"]),
            "SUAllowsAutomaticUpdates": try XCTUnwrap(productionInfo["SUAllowsAutomaticUpdates"]),
            "SUEnableSystemProfiling": try XCTUnwrap(productionInfo["SUEnableSystemProfiling"]),
            "SUEnableJavaScript": try XCTUnwrap(productionInfo["SUEnableJavaScript"]),
            "SUVerifyUpdateBeforeExtraction": try XCTUnwrap(productionInfo["SUVerifyUpdateBeforeExtraction"]),
            "SURequireSignedFeed": try XCTUnwrap(productionInfo["SURequireSignedFeed"]),
            "SUSignedFeedFailureExpirationInterval": try XCTUnwrap(productionInfo["SUSignedFeedFailureExpirationInterval"]),
        ]
        (info as NSDictionary).write(to: contentsURL.appendingPathComponent("Info.plist"), atomically: true)
        bundle = try XCTUnwrap(Bundle(url: bundleURL))
    }

    func retain(updater: SPUUpdater, driver: RecordingUserDriver, delegate: RecordingUpdaterDelegate) {
        retainedObjects.append(updater)
        retainedObjects.append(driver)
        retainedObjects.append(delegate)
    }

    deinit { defaults.removePersistentDomain(forName: suiteName) }
}

private final class LoopbackFeedServer: @unchecked Sendable {
    struct RequestRecord {
        let request: URLRequest
        let timestamp: Date
    }
    private let socketDescriptor: Int32
    private let queue = DispatchQueue(label: "dev.gihwan.inkbeam.tests.feed")
    private let lock = NSLock()
    private var source: DispatchSourceRead? = nil
    private var storedRequests: [RequestRecord] = []
    var onRequest: ((URLRequest) -> Void)?

    private(set) var port = 0

    init() throws {
        socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else { throw POSIXError(.ENFILE) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(0).bigEndian
        address.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, listen(socketDescriptor, 4) == 0 else {
            close(socketDescriptor)
            throw POSIXError(.EADDRINUSE)
        }
        var boundAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketDescriptor, $0, &length)
            }
        }
        guard nameResult == 0 else {
            close(socketDescriptor)
            throw POSIXError(.EINVAL)
        }
        port = Int(UInt16(bigEndian: boundAddress.sin_port))
        let source = DispatchSource.makeReadSource(fileDescriptor: socketDescriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptConnection() }
        source.resume()
        self.source = source
    }

    var requests: [RequestRecord] {
        lock.lock()
        defer { lock.unlock() }
        return storedRequests
    }

    private func acceptConnection() {
        let connection = accept(socketDescriptor, nil, nil)
        guard connection >= 0 else { return }
        defer { close(connection) }
        var buffer = [UInt8](repeating: 0, count: 4096)
        let count = recv(connection, &buffer, buffer.count, 0)
        guard count > 0,
              let requestLine = String(bytes: buffer.prefix(Int(count)), encoding: .utf8)?.split(separator: "\r\n").first
        else { return }
        let components = requestLine.split(separator: " ")
        guard components.count >= 2,
              let url = URL(string: "http://127.0.0.1:\(port)\(components[1])")
        else { return }
        var request = URLRequest(url: url)
        request.httpMethod = String(components[0])
        lock.lock()
        storedRequests.append(RequestRecord(request: request, timestamp: Date()))
        let handler = onRequest
        lock.unlock()
        handler?(request)
        let body = "<?xml version=\"1.0\"?><rss version=\"2.0\"><channel><title>Inkbeam</title></channel></rss>"
        let response = "HTTP/1.1 200 OK\r\nContent-Type: application/xml\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        _ = response.withCString { send(connection, $0, strlen($0), 0) }
    }

    deinit {
        source?.cancel()
        close(socketDescriptor)
    }
}
