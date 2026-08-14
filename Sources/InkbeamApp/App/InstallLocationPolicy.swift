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

        let path = standardizedURL.path
        guard !path.contains("/AppTranslocation/") else {
            return .moveToApplications
        }

        let systemApplicationsPrefix = "/Applications/"
        let userApplicationsPrefix = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .standardizedFileURL
            .path + "/"

        return path.hasPrefix(systemApplicationsPrefix)
            || path.hasPrefix(userApplicationsPrefix)
            ? .eligible
            : .moveToApplications
    }
}
