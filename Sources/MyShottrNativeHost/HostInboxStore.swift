import Darwin
import Foundation

enum HostInboxStoreError: Error {
    case insecureInboxRoot
    case systemCallFailed(name: String, code: Int32)
}

struct HostInboxStore: HostCaptureStaging {
    typealias WriteOperation = (Int32, Data) throws -> Void
    typealias SynchronizeOperation = (Int32) -> Int32

    let rootURL: URL
    private let idGenerator: () -> UUID
    private let writeOperation: WriteOperation
    private let synchronizeOperation: SynchronizeOperation

    init(
        rootURL: URL = HostInboxStore.defaultRootURL,
        idGenerator: @escaping () -> UUID = UUID.init,
        writeOperation: @escaping WriteOperation = HostInboxStore.writeAll,
        synchronizeOperation: @escaping SynchronizeOperation = Darwin.fsync
    ) {
        self.rootURL = rootURL
        self.idGenerator = idGenerator
        self.writeOperation = writeOperation
        self.synchronizeOperation = synchronizeOperation
    }

    func stage(pngData: Data) throws -> UUID {
        try createAndValidateRoot()

        let rootDescriptor = Darwin.open(
            rootURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard rootDescriptor >= 0 else {
            throw systemCallError("open inbox")
        }
        defer {
            Darwin.close(rootDescriptor)
        }

        guard Darwin.fchmod(rootDescriptor, 0o700) == 0 else {
            throw systemCallError("fchmod inbox")
        }

        let captureID = idGenerator()
        let filename = "\(captureID.uuidString).png"
        let descriptor = filename.withCString {
            Darwin.openat(
                rootDescriptor,
                $0,
                O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW,
                0o600
            )
        }
        guard descriptor >= 0 else {
            throw systemCallError("open staged capture")
        }

        var descriptorIsOpen = true
        do {
            guard Darwin.fchmod(descriptor, 0o600) == 0 else {
                throw systemCallError("fchmod staged capture")
            }
            try writeOperation(descriptor, pngData)
            guard synchronizeOperation(descriptor) == 0 else {
                throw systemCallError("fsync staged capture")
            }
            guard Darwin.close(descriptor) == 0 else {
                descriptorIsOpen = false
                throw systemCallError("close staged capture")
            }
            descriptorIsOpen = false
            return captureID
        } catch {
            if descriptorIsOpen {
                Darwin.close(descriptor)
            }
            filename.withCString {
                _ = Darwin.unlinkat(rootDescriptor, $0, 0)
            }
            throw error
        }
    }

    private func createAndValidateRoot() throws {
        var metadata = stat()
        let status = rootURL.path.withCString {
            Darwin.lstat($0, &metadata)
        }

        if status == 0 {
            guard metadata.st_mode & S_IFMT == S_IFDIR else {
                throw HostInboxStoreError.insecureInboxRoot
            }
        } else if errno == ENOENT {
            try FileManager.default.createDirectory(
                at: rootURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } else {
            throw systemCallError("lstat inbox")
        }

        var verifiedMetadata = stat()
        guard
            rootURL.path.withCString({
                Darwin.lstat($0, &verifiedMetadata)
            }) == 0,
            verifiedMetadata.st_mode & S_IFMT == S_IFDIR
        else {
            throw HostInboxStoreError.insecureInboxRoot
        }
    }

    private static func writeAll(_ descriptor: Int32, _ data: Data) throws {
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
                    throw systemCallError("write staged capture")
                }
                guard result > 0 else {
                    throw HostInboxStoreError.systemCallFailed(
                        name: "write staged capture",
                        code: EIO
                    )
                }
                offset += result
            }
        }
    }

    private static var defaultRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("MyShottr", isDirectory: true)
            .appendingPathComponent("Inbox", isDirectory: true)
    }

    private static func systemCallError(_ name: String) -> HostInboxStoreError {
        HostInboxStoreError.systemCallFailed(name: name, code: errno)
    }

    private func systemCallError(_ name: String) -> HostInboxStoreError {
        Self.systemCallError(name)
    }
}
