import Foundation

enum AboutDiagnosticsError: Error, Equatable {
    case missingValue(String)
    case invalidChannel
}

struct AboutDiagnostics: Equatable {
    let version: String
    let build: String
    let channel: UpdateChannel

    init(info: [String: Any]) throws {
        version = try Self.requiredString(
            "CFBundleShortVersionString",
            in: info
        )
        build = try Self.requiredString("CFBundleVersion", in: info)
        let channelValue = try Self.requiredString(
            "InkbeamReleaseChannel",
            in: info
        )
        guard let channel = UpdateChannel(rawValue: channelValue) else {
            throw AboutDiagnosticsError.invalidChannel
        }
        self.channel = channel
    }

    var displayVersion: String {
        "\(version) (\(build)) · \(channel.rawValue)"
    }

    private static func requiredString(
        _ key: String,
        in info: [String: Any]
    ) throws -> String {
        guard let value = info[key] as? String, !value.isEmpty else {
            throw AboutDiagnosticsError.missingValue(key)
        }
        return value
    }
}
