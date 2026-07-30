import Foundation

protocol SessionTerminationTracking: Sendable {
    func beginSession() throws -> Bool
    func markCleanExit() throws
}

enum SessionTerminationStateError: Error, Equatable {
    case invalidRoot
    case invalidState
    case writeFailed
}

struct SessionTerminationState: SessionTerminationTracking {
    private struct State: Codable {
        let schemaVersion: Int
        let cleanExit: Bool
    }

    private let root: URL
    private let stateURL: URL

    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/MyShottr",
                isDirectory: true
            )
    }

    init(
        root: URL = SessionTerminationState.defaultRoot
    ) throws {
        self.root = root.standardizedFileURL
        self.stateURL = self.root.appendingPathComponent(
            "session.json",
            isDirectory: false
        )
        try Self.prepareRoot(self.root)
    }

    func beginSession() throws -> Bool {
        let previousCleanExit = try readPreviousCleanExit()
        try write(cleanExit: false)
        return previousCleanExit
    }

    func markCleanExit() throws {
        try write(cleanExit: true)
    }

    private func readPreviousCleanExit() throws -> Bool {
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                ],
                options: []
            )
        } catch {
            throw SessionTerminationStateError.invalidRoot
        }
        guard let entry = entries.first(
            where: { $0.lastPathComponent == stateURL.lastPathComponent }
        ) else {
            return true
        }
        do {
            let values = try entry.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true
            else {
                throw SessionTerminationStateError.invalidState
            }
            let data = try Data(contentsOf: entry)
            guard let object = try JSONSerialization
                    .jsonObject(with: data) as? [String: Any],
                  Set(object.keys) == [
                    "schemaVersion",
                    "cleanExit",
                  ],
                  object["schemaVersion"] as? Int == 1,
                  object["cleanExit"] is Bool
            else {
                throw SessionTerminationStateError.invalidState
            }
            return try JSONDecoder()
                .decode(State.self, from: data)
                .cleanExit
        } catch let error as SessionTerminationStateError {
            throw error
        } catch {
            throw SessionTerminationStateError.invalidState
        }
    }

    private func write(cleanExit: Bool) throws {
        let state = State(
            schemaVersion: 1,
            cleanExit: cleanExit
        )
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: stateURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: stateURL.path
            )
        } catch {
            throw SessionTerminationStateError.writeFailed
        }
    }

    private static func prepareRoot(_ root: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: root.path) {
            let values: URLResourceValues
            do {
                values = try root.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                )
            } catch {
                throw SessionTerminationStateError.invalidRoot
            }
            guard values.isDirectory == true,
                  values.isSymbolicLink != true
            else {
                throw SessionTerminationStateError.invalidRoot
            }
        } else {
            do {
                try fileManager.createDirectory(
                    at: root,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                throw SessionTerminationStateError.invalidRoot
            }
        }
        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: root.path
            )
        } catch {
            throw SessionTerminationStateError.invalidRoot
        }
    }
}
