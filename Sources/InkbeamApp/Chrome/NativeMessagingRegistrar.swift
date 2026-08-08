import Darwin
import Foundation

struct NativeMessagingHostManifest:
    Codable,
    Equatable,
    Sendable
{
    let name: String
    let description: String
    let path: String
    let type: String
    let allowedOrigins: [String]

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case path
        case type
        case allowedOrigins = "allowed_origins"
    }
}

enum NativeMessagingRegistrarError: Error {
    case invalidHelperPath
    case missingPublicKeyResource
    case systemCallFailed(name: String, code: Int32)
}

struct NativeMessagingRegistrar {
    static let hostName = "dev.gihwan.inkbeam.capture"
    static let installedHelperURL = URL(
        fileURLWithPath:
            "/Applications/Inkbeam.app/Contents/Helpers/InkbeamNativeHost"
    )

    private let publicKeyBase64: String
    private let helperURL: URL
    private let manifestURL: URL

    init(
        publicKeyBase64: String,
        helperURL: URL,
        manifestURL: URL = NativeMessagingRegistrar.defaultManifestURL
    ) {
        self.publicKeyBase64 = publicKeyBase64
        self.helperURL = helperURL
        self.manifestURL = manifestURL.standardizedFileURL
    }

    init(
        bundle: Bundle = .main,
        manifestURL: URL = NativeMessagingRegistrar.defaultManifestURL
    ) throws {
        guard
            let publicKeyURL = bundle.url(
                forResource: "chrome-extension-key",
                withExtension: "b64"
            )
        else {
            throw NativeMessagingRegistrarError.missingPublicKeyResource
        }

        publicKeyBase64 = try String(
            contentsOf: publicKeyURL,
            encoding: .utf8
        )
        helperURL = Self.installedHelperURL
        self.manifestURL = manifestURL.standardizedFileURL
    }

    func makeManifest() throws -> NativeMessagingHostManifest {
        guard
            helperURL.isFileURL,
            helperURL.baseURL == nil,
            helperURL.path.hasPrefix("/")
        else {
            throw NativeMessagingRegistrarError.invalidHelperPath
        }

        let extensionID = try ChromeExtensionIdentity.id(
            fromBase64DER: publicKeyBase64
        )
        return NativeMessagingHostManifest(
            name: Self.hostName,
            description: "Open Chrome viewport captures in Inkbeam",
            path: helperURL.standardizedFileURL.path,
            type: "stdio",
            allowedOrigins: [
                "chrome-extension://\(extensionID)/",
            ]
        )
    }

    func install() throws {
        let manifest = try makeManifest()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(manifest)
        let directoryURL = manifestURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let directoryDescriptor = Darwin.open(
            directoryURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard directoryDescriptor >= 0 else {
            throw systemCallError("open native messaging directory")
        }
        defer {
            Darwin.close(directoryDescriptor)
        }
        guard Darwin.fchmod(directoryDescriptor, 0o700) == 0 else {
            throw systemCallError("fchmod native messaging directory")
        }

        let temporaryFilename = ".\(UUID().uuidString).tmp"
        let descriptor = temporaryFilename.withCString {
            Darwin.openat(
                directoryDescriptor,
                $0,
                O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW,
                0o600
            )
        }
        guard descriptor >= 0 else {
            throw systemCallError("open native messaging manifest")
        }

        var descriptorIsOpen = true
        var temporaryFileExists = true
        do {
            guard Darwin.fchmod(descriptor, 0o600) == 0 else {
                throw systemCallError("fchmod native messaging manifest")
            }
            try Self.writeAll(data, to: descriptor)
            guard Darwin.fsync(descriptor) == 0 else {
                throw systemCallError("fsync native messaging manifest")
            }
            let closeStatus = Darwin.close(descriptor)
            descriptorIsOpen = false
            guard closeStatus == 0 else {
                throw systemCallError("close native messaging manifest")
            }

            let finalFilename = manifestURL.lastPathComponent
            let renameStatus = temporaryFilename.withCString {
                temporaryName in
                finalFilename.withCString { finalName in
                    Darwin.renameat(
                        directoryDescriptor,
                        temporaryName,
                        directoryDescriptor,
                        finalName
                    )
                }
            }
            guard renameStatus == 0 else {
                throw systemCallError("publish native messaging manifest")
            }
            temporaryFileExists = false
            guard Darwin.fsync(directoryDescriptor) == 0 else {
                throw systemCallError("fsync native messaging directory")
            }
        } catch {
            if descriptorIsOpen {
                Darwin.close(descriptor)
            }
            if temporaryFileExists {
                temporaryFilename.withCString {
                    _ = Darwin.unlinkat(directoryDescriptor, $0, 0)
                }
            }
            throw error
        }
    }

    private static func writeAll(
        _ data: Data,
        to descriptor: Int32
    ) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let result = Darwin.write(
                    descriptor,
                    bytes.baseAddress?.advanced(by: offset),
                    bytes.count - offset
                )
                if result < 0 {
                    if errno == EINTR {
                        continue
                    }
                    throw systemCallError(
                        "write native messaging manifest"
                    )
                }
                guard result > 0 else {
                    throw NativeMessagingRegistrarError.systemCallFailed(
                        name: "write native messaging manifest",
                        code: EIO
                    )
                }
                offset += result
            }
        }
    }

    static var defaultManifestURL: URL {
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
            .appendingPathComponent("\(hostName).json")
    }

    private static func systemCallError(
        _ name: String
    ) -> NativeMessagingRegistrarError {
        NativeMessagingRegistrarError.systemCallFailed(
            name: name,
            code: errno
        )
    }

    private func systemCallError(
        _ name: String
    ) -> NativeMessagingRegistrarError {
        Self.systemCallError(name)
    }
}
