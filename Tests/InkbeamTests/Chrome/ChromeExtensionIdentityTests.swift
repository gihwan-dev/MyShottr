import XCTest
@testable import Inkbeam

final class ChromeExtensionIdentityTests: XCTestCase {
    func testBundledPublicKeyIsByteIdenticalToCommittedIdentityKey() throws {
        let bundledURL = try XCTUnwrap(
            Bundle.main.url(
                forResource: "chrome-extension-key",
                withExtension: "b64"
            )
        )
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let committedURL = repositoryRoot.appendingPathComponent(
            "Config/chrome-extension-key.b64"
        )

        XCTAssertEqual(
            try Data(contentsOf: bundledURL),
            try Data(contentsOf: committedURL)
        )
    }

    func testCommittedPublicKeyProducesKnownExtensionID() throws {
        XCTAssertEqual(
            try ChromeExtensionIdentity.id(
                fromBase64DER: ChromeFixtures.extensionPublicKeyBase64
            ),
            ChromeFixtures.extensionID
        )
    }

    func testExtensionIDHasThirtyTwoLowercaseAPCharacters() throws {
        let id = try ChromeExtensionIdentity.id(
            fromBase64DER: ChromeFixtures.extensionPublicKeyBase64
        )

        XCTAssertNotNil(
            id.range(
                of: #"^[a-p]{32}$"#,
                options: .regularExpression
            )
        )
    }

    func testInvalidBase64IsRejected() {
        XCTAssertThrowsError(
            try ChromeExtensionIdentity.id(fromBase64DER: "not/base64%%%")
        )
    }
}
