import Darwin
import Foundation

struct StagedCapture: Equatable, Sendable {
    let id: UUID
    let pngURL: URL
}

protocol PendingCaptureStoring: Sendable {
    func stage(pngData: Data) throws -> StagedCapture
    func pendingCaptures() throws -> [StagedCapture]
    func consume(id: UUID) throws -> Data
}

enum PendingCaptureInboxError: Error, Equatable {
    case captureNotFound
    case insecureInboxRoot
    case invalidEntry
    case invalidPNG
    case imageTooLarge
    case systemCallFailed(name: String, code: Int32)
}

struct PendingCaptureInbox: PendingCaptureStoring {
    private static let maximumImageLength = 45 * 1024 * 1024

    let rootURL: URL
    private let idGenerator: @Sendable () -> UUID

    init(
        root: URL = PendingCaptureInbox.defaultRootURL,
        idGenerator: @escaping @Sendable () -> UUID = UUID.init
    ) throws {
        rootURL = root.standardizedFileURL
        self.idGenerator = idGenerator
        try createAndValidateRoot()
    }

    func stage(pngData: Data) throws -> StagedCapture {
        guard pngData.count <= Self.maximumImageLength else {
            throw PendingCaptureInboxError.imageTooLarge
        }

        let rootDescriptor = try openRoot()
        defer {
            Darwin.close(rootDescriptor)
        }

        let id = idGenerator()
        let filename = captureFilename(id: id)
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
        var ownsFile = true
        do {
            guard Darwin.fchmod(descriptor, 0o600) == 0 else {
                throw systemCallError("fchmod staged capture")
            }
            try Self.writeAll(pngData, to: descriptor)
            guard Darwin.fsync(descriptor) == 0 else {
                throw systemCallError("fsync staged capture")
            }
            let closeStatus = Darwin.close(descriptor)
            descriptorIsOpen = false
            guard closeStatus == 0 else {
                throw systemCallError("close staged capture")
            }

            do {
                _ = try PNGMetadata.read(from: pngData)
            } catch {
                throw PendingCaptureInboxError.invalidPNG
            }
            guard Darwin.fsync(rootDescriptor) == 0 else {
                throw systemCallError("fsync inbox")
            }

            ownsFile = false
            return StagedCapture(
                id: id,
                pngURL: rootURL.appendingPathComponent(filename)
            )
        } catch {
            if descriptorIsOpen {
                Darwin.close(descriptor)
            }
            if ownsFile {
                filename.withCString {
                    _ = Darwin.unlinkat(rootDescriptor, $0, 0)
                }
                _ = Darwin.fsync(rootDescriptor)
            }
            throw error
        }
    }

    func pendingCaptures() throws -> [StagedCapture] {
        let rootDescriptor = try openRoot()
        defer {
            Darwin.close(rootDescriptor)
        }

        let filenames = try directoryFilenames(
            rootDescriptor: rootDescriptor
        )
        var entries: [PendingEntry] = []

        for filename in filenames {
            guard let id = captureID(from: filename) else {
                continue
            }

            var metadata = stat()
            let status = filename.withCString {
                Darwin.fstatat(
                    rootDescriptor,
                    $0,
                    &metadata,
                    AT_SYMLINK_NOFOLLOW
                )
            }
            if status != 0 {
                if errno == ENOENT {
                    continue
                }
                throw systemCallError("inspect pending capture")
            }
            entries.append(
                PendingEntry(
                    capture: StagedCapture(
                        id: id,
                        pngURL: rootURL.appendingPathComponent(filename)
                    ),
                    modifiedSeconds: metadata.st_mtimespec.tv_sec,
                    modifiedNanoseconds: metadata.st_mtimespec.tv_nsec
                )
            )
        }

        return entries.sorted {
            if $0.modifiedSeconds != $1.modifiedSeconds {
                return $0.modifiedSeconds < $1.modifiedSeconds
            }
            if $0.modifiedNanoseconds != $1.modifiedNanoseconds {
                return $0.modifiedNanoseconds < $1.modifiedNanoseconds
            }
            return $0.capture.id.uuidString < $1.capture.id.uuidString
        }.map(\.capture)
    }

    func consume(id: UUID) throws -> Data {
        let rootDescriptor = try openRoot()
        defer {
            Darwin.close(rootDescriptor)
        }

        let filename = captureFilename(id: id)
        let descriptor = filename.withCString {
            Darwin.openat(
                rootDescriptor,
                $0,
                O_RDONLY | O_NOFOLLOW
            )
        }
        guard descriptor >= 0 else {
            let code = errno
            if code == ELOOP {
                removeEntry(filename, from: rootDescriptor)
                throw PendingCaptureInboxError.invalidEntry
            }
            if code == ENOENT {
                throw PendingCaptureInboxError.captureNotFound
            }
            throw PendingCaptureInboxError.systemCallFailed(
                name: "open pending capture",
                code: code
            )
        }

        var descriptorIsOpen = true
        do {
            var metadata = stat()
            guard Darwin.fstat(descriptor, &metadata) == 0 else {
                throw systemCallError("inspect pending capture")
            }
            guard
                metadata.st_mode & S_IFMT == S_IFREG,
                metadata.st_uid == getuid(),
                metadata.st_nlink == 1,
                metadata.st_mode & 0o777 == 0o600
            else {
                throw PendingCaptureInboxError.invalidEntry
            }
            guard
                metadata.st_size > 0,
                metadata.st_size <= Self.maximumImageLength
            else {
                throw PendingCaptureInboxError.imageTooLarge
            }

            let data = try Self.readAll(
                from: descriptor,
                expectedLength: Int(metadata.st_size)
            )
            let closeStatus = Darwin.close(descriptor)
            descriptorIsOpen = false
            guard closeStatus == 0 else {
                throw systemCallError("close pending capture")
            }
            guard filename.withCString({
                Darwin.unlinkat(rootDescriptor, $0, 0)
            }) == 0 else {
                throw systemCallError("remove consumed capture")
            }
            guard Darwin.fsync(rootDescriptor) == 0 else {
                throw systemCallError("fsync inbox")
            }

            do {
                _ = try PNGMetadata.read(from: data)
            } catch {
                throw PendingCaptureInboxError.invalidPNG
            }
            return data
        } catch {
            if descriptorIsOpen {
                Darwin.close(descriptor)
            }
            removeEntry(filename, from: rootDescriptor)
            throw error
        }
    }

    private func createAndValidateRoot() throws {
        var metadata = stat()
        let status = rootURL.path.withCString {
            Darwin.lstat($0, &metadata)
        }

        if status == 0 {
            guard
                metadata.st_mode & S_IFMT == S_IFDIR,
                metadata.st_uid == getuid()
            else {
                throw PendingCaptureInboxError.insecureInboxRoot
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

        let descriptor = Darwin.open(
            rootURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw PendingCaptureInboxError.insecureInboxRoot
        }
        defer {
            Darwin.close(descriptor)
        }

        var verified = stat()
        guard
            Darwin.fstat(descriptor, &verified) == 0,
            verified.st_mode & S_IFMT == S_IFDIR,
            verified.st_uid == getuid(),
            Darwin.fchmod(descriptor, 0o700) == 0
        else {
            throw PendingCaptureInboxError.insecureInboxRoot
        }
    }

    private func openRoot() throws -> Int32 {
        let descriptor = Darwin.open(
            rootURL.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw systemCallError("open inbox")
        }

        var metadata = stat()
        guard
            Darwin.fstat(descriptor, &metadata) == 0,
            metadata.st_mode & S_IFMT == S_IFDIR,
            metadata.st_uid == getuid(),
            metadata.st_mode & 0o777 == 0o700
        else {
            Darwin.close(descriptor)
            throw PendingCaptureInboxError.insecureInboxRoot
        }
        return descriptor
    }

    private func captureFilename(id: UUID) -> String {
        "\(id.uuidString).png"
    }

    private func directoryFilenames(
        rootDescriptor: Int32
    ) throws -> [String] {
        let enumerationDescriptor = Darwin.dup(rootDescriptor)
        guard enumerationDescriptor >= 0 else {
            throw systemCallError("duplicate inbox descriptor")
        }
        guard let directory = Darwin.fdopendir(enumerationDescriptor) else {
            let code = errno
            Darwin.close(enumerationDescriptor)
            throw PendingCaptureInboxError.systemCallFailed(
                name: "open inbox directory stream",
                code: code
            )
        }
        defer {
            Darwin.closedir(directory)
        }

        var filenames: [String] = []
        errno = 0
        while let entry = Darwin.readdir(directory) {
            var record = entry.pointee
            let filename = withUnsafePointer(to: &record.d_name) {
                pointer in
                pointer.withMemoryRebound(
                    to: CChar.self,
                    capacity: Int(record.d_namlen) + 1
                ) {
                    String(cString: $0)
                }
            }
            if filename != ".", filename != ".." {
                filenames.append(filename)
            }
            errno = 0
        }
        guard errno == 0 else {
            throw systemCallError("read inbox directory")
        }
        return filenames
    }

    private func captureID(from filename: String) -> UUID? {
        guard
            filename.hasSuffix(".png"),
            let id = UUID(
                uuidString: String(filename.dropLast(".png".count))
            ),
            filename == captureFilename(id: id)
        else {
            return nil
        }
        return id
    }

    private func removeEntry(
        _ filename: String,
        from rootDescriptor: Int32
    ) {
        filename.withCString {
            _ = Darwin.unlinkat(rootDescriptor, $0, 0)
        }
        _ = Darwin.fsync(rootDescriptor)
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
                    throw systemCallError("write staged capture")
                }
                guard result > 0 else {
                    throw PendingCaptureInboxError.systemCallFailed(
                        name: "write staged capture",
                        code: EIO
                    )
                }
                offset += result
            }
        }
    }

    private static func readAll(
        from descriptor: Int32,
        expectedLength: Int
    ) throws -> Data {
        var data = Data()
        data.reserveCapacity(expectedLength)
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)

        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count < 0 {
                if errno == EINTR {
                    continue
                }
                throw systemCallError("read pending capture")
            }
            if count == 0 {
                break
            }
            guard data.count + count <= maximumImageLength else {
                throw PendingCaptureInboxError.imageTooLarge
            }
            data.append(buffer, count: count)
        }
        return data
    }

    private static var defaultRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent(
                "Application Support",
                isDirectory: true
            )
            .appendingPathComponent("MyShottr", isDirectory: true)
            .appendingPathComponent("Inbox", isDirectory: true)
    }

    private static func systemCallError(
        _ name: String
    ) -> PendingCaptureInboxError {
        PendingCaptureInboxError.systemCallFailed(
            name: name,
            code: errno
        )
    }

    private func systemCallError(
        _ name: String
    ) -> PendingCaptureInboxError {
        Self.systemCallError(name)
    }
}

private struct PendingEntry {
    let capture: StagedCapture
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
}
