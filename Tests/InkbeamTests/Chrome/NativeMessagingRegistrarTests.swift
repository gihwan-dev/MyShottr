import Foundation
import XCTest
@testable import Inkbeam

final class NativeMessagingRegistrarTests: TemporaryDirectoryTestCase {
    func testRegistrarUsesOnlyExactInkbeamHostAndManifestLocation() {
        XCTAssertEqual(
            NativeMessagingRegistrar.hostName,
            "dev.gihwan.inkbeam.capture"
        )
        XCTAssertEqual(
            NativeMessagingRegistrar.defaultManifestURL.path,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent(
                    "Application Support",
                    isDirectory: true
                )
                .appendingPathComponent("Google", isDirectory: true)
                .appendingPathComponent("Chrome", isDirectory: true)
                .appendingPathComponent(
                    "NativeMessagingHosts",
                    isDirectory: true
                )
                .appendingPathComponent(
                    "dev.gihwan.inkbeam.capture.json"
                )
                .path
        )
    }

    func testAppBundleContainsCommittedExtensionPublicKey() throws {
        let keyURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "chrome-extension-key",
                withExtension: "b64"
            )
        )
        let key = try String(contentsOf: keyURL, encoding: .utf8)

        XCTAssertEqual(
            try ChromeExtensionIdentity.id(fromBase64DER: key),
            ChromeFixtures.extensionID
        )
    }

    func testBundledRegistrarUsesInstalledHelperPath() throws {
        let registrar = try NativeMessagingRegistrar(
            bundle: .main,
            manifestURL: ChromeFixtures.manifestURL(
                in: temporaryDirectory
            )
        )

        let manifest = try registrar.makeManifest()

        XCTAssertEqual(
            manifest.path,
            "/Applications/Inkbeam.app/Contents/Helpers/InkbeamNativeHost"
        )
        XCTAssertEqual(
            manifest.allowedOrigins,
            ["chrome-extension://\(ChromeFixtures.extensionID)/"]
        )
    }

    func testManifestUsesExactHostOriginAndAbsoluteHelperPath() throws {
        let helperURL = ChromeFixtures.helperURL(in: temporaryDirectory)
        let registrar = NativeMessagingRegistrar(
            publicKeyBase64: ChromeFixtures.extensionPublicKeyBase64,
            helperURL: helperURL,
            manifestURL: ChromeFixtures.manifestURL(in: temporaryDirectory)
        )

        let manifest = try registrar.makeManifest()

        XCTAssertEqual(manifest.name, "dev.gihwan.inkbeam.capture")
        XCTAssertEqual(
            manifest.description,
            "Open Chrome viewport captures in Inkbeam"
        )
        XCTAssertEqual(manifest.path, helperURL.path)
        XCTAssertTrue(manifest.path.hasPrefix("/"))
        XCTAssertEqual(manifest.type, "stdio")
        XCTAssertEqual(
            manifest.allowedOrigins,
            ["chrome-extension://\(ChromeFixtures.extensionID)/"]
        )
    }

    func testInstallWritesDecodableOwnerOnlyManifest() throws {
        let manifestURL = ChromeFixtures.manifestURL(in: temporaryDirectory)
        let registrar = NativeMessagingRegistrar(
            publicKeyBase64: ChromeFixtures.extensionPublicKeyBase64,
            helperURL: ChromeFixtures.helperURL(in: temporaryDirectory),
            manifestURL: manifestURL
        )

        try registrar.install()

        let decoded = try JSONDecoder().decode(
            NativeMessagingHostManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        XCTAssertEqual(decoded, try registrar.makeManifest())
        let attributes = try FileManager.default.attributesOfItem(
            atPath: manifestURL.path
        )
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeRegular)
        XCTAssertEqual(
            (attributes[.posixPermissions] as? NSNumber)?.intValue,
            0o600
        )
    }

    func testInstallRefreshesManifestWithCurrentAbsoluteHelperPath() throws {
        let manifestURL = ChromeFixtures.manifestURL(in: temporaryDirectory)
        let oldHelper = temporaryDirectory
            .appendingPathComponent("Old.app/Contents/Helpers/InkbeamNativeHost")
        try NativeMessagingRegistrar(
            publicKeyBase64: ChromeFixtures.extensionPublicKeyBase64,
            helperURL: oldHelper,
            manifestURL: manifestURL
        ).install()
        let currentHelper = ChromeFixtures.helperURL(in: temporaryDirectory)
        let registrar = NativeMessagingRegistrar(
            publicKeyBase64: ChromeFixtures.extensionPublicKeyBase64,
            helperURL: currentHelper,
            manifestURL: manifestURL
        )

        try registrar.install()

        let decoded = try JSONDecoder().decode(
            NativeMessagingHostManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        XCTAssertEqual(decoded.path, currentHelper.path)
    }

    func testInstallDoesNotWriteOrDeleteLegacyHostManifest() throws {
        let hostDirectory = temporaryDirectory.appendingPathComponent(
            "NativeMessagingHosts",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: hostDirectory,
            withIntermediateDirectories: true
        )
        let legacyURL = hostDirectory.appendingPathComponent(
            "com." + "my" + "shottr.capture.json"
        )
        let legacyData = Data("legacy sentinel".utf8)
        try legacyData.write(to: legacyURL)
        let manifestURL = hostDirectory.appendingPathComponent(
            "dev.gihwan.inkbeam.capture.json"
        )
        let registrar = NativeMessagingRegistrar(
            publicKeyBase64: ChromeFixtures.extensionPublicKeyBase64,
            helperURL: ChromeFixtures.helperURL(in: temporaryDirectory),
            manifestURL: manifestURL
        )

        try registrar.install()

        XCTAssertEqual(try Data(contentsOf: legacyURL), legacyData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path))
    }

    func testRelativeHelperPathIsRejected() {
        let registrar = NativeMessagingRegistrar(
            publicKeyBase64: ChromeFixtures.extensionPublicKeyBase64,
            helperURL: URL(string: "relative/helper")!,
            manifestURL: ChromeFixtures.manifestURL(in: temporaryDirectory)
        )

        XCTAssertThrowsError(try registrar.makeManifest())
    }
}
