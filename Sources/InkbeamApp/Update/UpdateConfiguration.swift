import Foundation

enum UpdateChannel: String, Equatable {
    case beta = "Release Candidate"
    case stable = "Stable"
}

enum UpdateAppcastHost: String, Equatable {
    case githubPages = "gihwan-dev.github.io"
}

enum UpdateConfigurationError: Error, Equatable {
    case missingValue(String)
    case invalidFeed
    case invalidPublicKey
    case invalidChannel
    case feedChannelMismatch
}

struct UpdateConfiguration: Equatable {
    private static let stableFeed =
        "https://gihwan-dev.github.io/inkbeam/appcast.xml"
    private static let betaFeed =
        "https://gihwan-dev.github.io/inkbeam/appcast-beta.xml"

    let feedURL: URL
    let publicEDKey: String
    let channel: UpdateChannel

    init(info: [String: Any]) throws {
        let feed = try Self.requiredString("SUFeedURL", in: info)
        let key = try Self.requiredString("SUPublicEDKey", in: info)
        let channelValue = try Self.requiredString(
            "InkbeamReleaseChannel",
            in: info
        )

        guard let channel = UpdateChannel(rawValue: channelValue) else {
            throw UpdateConfigurationError.invalidChannel
        }
        guard let feedURL = URL(string: feed) else {
            throw UpdateConfigurationError.invalidFeed
        }

        self.feedURL = feedURL
        publicEDKey = key
        self.channel = channel
        try validate()
    }

    var appcastHost: UpdateAppcastHost {
        .githubPages
    }

    func validate() throws {
        let feed = feedURL.absoluteString
        let approvedFeed: String
        switch channel {
        case .beta:
            approvedFeed = Self.betaFeed
        case .stable:
            approvedFeed = Self.stableFeed
        }

        guard feed == Self.stableFeed || feed == Self.betaFeed else {
            throw UpdateConfigurationError.invalidFeed
        }
        guard feed == approvedFeed else {
            throw UpdateConfigurationError.feedChannelMismatch
        }
        guard Self.isValidPublicKey(publicEDKey) else {
            throw UpdateConfigurationError.invalidPublicKey
        }
    }

    private static func requiredString(
        _ key: String,
        in info: [String: Any]
    ) throws -> String {
        guard let value = info[key] as? String, !value.isEmpty else {
            throw UpdateConfigurationError.missingValue(key)
        }
        return value
    }

    private static func isValidPublicKey(_ value: String) -> Bool {
        let base64Characters = CharacterSet(
            charactersIn:
                "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        )
        guard value.count == 44,
              value.last == "=",
              value.dropLast().unicodeScalars.allSatisfy(
                  base64Characters.contains
              ),
              let decoded = Data(base64Encoded: value),
              decoded.count == 32
        else {
            return false
        }
        return true
    }
}
