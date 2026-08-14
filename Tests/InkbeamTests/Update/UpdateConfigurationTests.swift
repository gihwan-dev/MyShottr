import Foundation
import XCTest
@testable import Inkbeam

final class UpdateConfigurationTests: XCTestCase {
    private let publicKey =
        "xr1xG+wKx4sHmGeuF5bkgFjjqaZEJ6pMbAJoiHCuUUE="

    func testStableConfigurationAcceptsOnlyStableFeedAndChannel() throws {
        let configuration = try UpdateConfiguration(
            info: validInfo(
                feed: "https://gihwan-dev.github.io/inkbeam/appcast.xml",
                channel: "Stable"
            )
        )

        XCTAssertEqual(configuration.channel, .stable)
        XCTAssertEqual(
            configuration.feedURL.absoluteString,
            "https://gihwan-dev.github.io/inkbeam/appcast.xml"
        )
        XCTAssertEqual(configuration.publicEDKey, publicKey)
        XCTAssertNoThrow(try configuration.validate())
    }

    func testBetaConfigurationAcceptsOnlyBetaFeedAndChannel() throws {
        let configuration = try UpdateConfiguration(
            info: validInfo(
                feed: "https://gihwan-dev.github.io/inkbeam/appcast-beta.xml",
                channel: "Release Candidate"
            )
        )

        XCTAssertEqual(configuration.channel, .beta)
        XCTAssertEqual(configuration.appcastHost, .githubPages)
    }

    func testConfigurationRejectsHTTPFeed() {
        assertInvalid(
            validInfo(
                feed: "http://gihwan-dev.github.io/inkbeam/appcast.xml",
                channel: "Stable"
            ),
            expected: .invalidFeed
        )
    }

    func testConfigurationRejectsUnapprovedHTTPSFeedShapes() {
        let feeds = [
            "https://example.com/inkbeam/appcast.xml",
            "https://gihwan-dev.github.io/inkbeam/other.xml",
            "https://gihwan-dev.github.io/inkbeam/appcast.xml?next=1",
            "https://user@gihwan-dev.github.io/inkbeam/appcast.xml",
        ]

        for feed in feeds {
            assertInvalid(
                validInfo(feed: feed, channel: "Stable"),
                expected: .invalidFeed
            )
        }
    }

    func testConfigurationRejectsFeedChannelMismatch() {
        assertInvalid(
            validInfo(
                feed: "https://gihwan-dev.github.io/inkbeam/appcast-beta.xml",
                channel: "Stable"
            ),
            expected: .feedChannelMismatch
        )
    }

    func testConfigurationRejectsUnknownChannel() {
        assertInvalid(
            validInfo(
                feed: "https://gihwan-dev.github.io/inkbeam/appcast.xml",
                channel: "Nightly"
            ),
            expected: .invalidChannel
        )
    }

    func testConfigurationRejectsMissingValues() {
        for key in [
            "SUFeedURL",
            "SUPublicEDKey",
            "InkbeamReleaseChannel",
        ] {
            var info = validInfo(
                feed: "https://gihwan-dev.github.io/inkbeam/appcast.xml",
                channel: "Stable"
            )
            info.removeValue(forKey: key)

            assertInvalid(info, expected: .missingValue(key))
        }
    }

    func testConfigurationRejectsWhitespaceAndMalformedPublicKeys() {
        let invalidKeys = [
            "\(publicKey)\n",
            " \(publicKey)",
            String(repeating: "A", count: 44),
            "not-base64",
        ]

        for key in invalidKeys {
            assertInvalid(
                validInfo(
                    feed: "https://gihwan-dev.github.io/inkbeam/appcast.xml",
                    channel: "Stable",
                    key: key
                ),
                expected: .invalidPublicKey
            )
        }
    }

    private func validInfo(
        feed: String,
        channel: String,
        key: String? = nil
    ) -> [String: Any] {
        [
            "SUFeedURL": feed,
            "SUPublicEDKey": key ?? publicKey,
            "InkbeamReleaseChannel": channel,
        ]
    }

    private func assertInvalid(
        _ info: [String: Any],
        expected: UpdateConfigurationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try UpdateConfiguration(info: info),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? UpdateConfigurationError,
                expected,
                file: file,
                line: line
            )
        }
    }
}
