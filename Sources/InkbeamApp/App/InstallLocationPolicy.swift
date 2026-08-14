import Foundation

enum InstallLocationDecision: Equatable {
    case eligible
    case moveToApplications
}

struct InstallLocationPolicy {
    func decision(
        bundleURL: URL,
        isWritable: Bool,
        isDebugBuild: Bool
    ) -> InstallLocationDecision {
        if isDebugBuild {
            return .eligible
        }

        let standardizedURL = bundleURL.standardizedFileURL
        guard standardizedURL.lastPathComponent == "Inkbeam.app",
              isWritable
        else {
            return .moveToApplications
        }

        let containerURL = standardizedURL.deletingLastPathComponent()
        if containerURL.lastPathComponent == "Applications" {
            return .eligible
        }

        return .moveToApplications
    }
}
