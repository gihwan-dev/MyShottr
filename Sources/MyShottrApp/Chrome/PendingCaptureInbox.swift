import Darwin
import Foundation

struct StagedCapture: Equatable, Sendable {
    let id: UUID
    let pngURL: URL
}

struct PendingCaptureClaim: Equatable, Sendable {
    let id: UUID
    let pngData: Data
    let processingURL: URL
    let fileDevice: UInt64
    let fileInode: UInt64
}

protocol PendingCaptureStoring: Sendable {
    func stage(pngData: Data) throws -> StagedCapture
    func pendingCaptures() throws -> [StagedCapture]
    func claim(id: UUID) throws -> PendingCaptureClaim
    func acknowledge(_ claim: PendingCaptureClaim) throws
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
    let rootURL: URL

    private let idGenerator: @Sendable () -> UUID
    private let directorySync: @Sendable (Int32) -> Int32

    init(
        root: URL = PendingCaptureInbox.defaultRootURL,
        idGenerator: @escaping @Sendable () -> UUID = UUID.init,
        directorySync:
            @escaping @Sendable (Int32) -> Int32 = Darwin.fsync
    ) throws {
        rootURL = root.standardizedFileURL
        self.idGenerator = idGenerator
        self.directorySync = directorySync
        try createAndValidateRoot()
    }

    func stage(pngData: Data) throws -> StagedCapture {
        try validatePNG(pngData)

        let rootDescriptor = try openRoot()
        defer {
            Darwin.close(rootDescriptor)
        }

        let id = idGenerator()
        let filename = pendingFilename(id: id)
        let processing = processingFilename(id: id)
        guard try !entryExists(
            processing,
            rootDescriptor: rootDescriptor
        ) else {
            throw PendingCaptureInboxError.systemCallFailed(
                name: "create staged capture",
                code: EEXIST
            )
        }

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
            guard directorySync(rootDescriptor) == 0 else {
                throw systemCallError("fsync inbox after stage")
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
                _ = directorySync(rootDescriptor)
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
        var entriesByID: [UUID: PendingEntry] = [:]

        for filename in filenames {
            guard let parsed = captureEntry(from: filename) else {
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

            let candidate = PendingEntry(
                capture: StagedCapture(
                    id: parsed.id,
                    pngURL: rootURL.appendingPathComponent(filename)
                ),
                state: parsed.state,
                modifiedSeconds: metadata.st_mtimespec.tv_sec,
                modifiedNanoseconds: metadata.st_mtimespec.tv_nsec
            )
            if let current = entriesByID[parsed.id],
               current.state == .processing {
                continue
            }
            entriesByID[parsed.id] = candidate
        }

        return entriesByID.values.sorted {
            if $0.modifiedSeconds != $1.modifiedSeconds {
                return $0.modifiedSeconds < $1.modifiedSeconds
            }
            if $0.modifiedNanoseconds != $1.modifiedNanoseconds {
                return $0.modifiedNanoseconds < $1.modifiedNanoseconds
            }
            return $0.capture.id.uuidString
                < $1.capture.id.uuidString
        }.map(\.capture)
    }

    func claim(id: UUID) throws -> PendingCaptureClaim {
        let rootDescriptor = try openRoot()
        defer {
            Darwin.close(rootDescriptor)
        }

        let pending = pendingFilename(id: id)
        let processing = processingFilename(id: id)
        if try entryExists(
            processing,
            rootDescriptor: rootDescriptor
        ) {
            if try entryExists(
                pending,
                rootDescriptor: rootDescriptor
            ) {
                try removeEntryDurably(
                    pending,
                    rootDescriptor: rootDescriptor,
                    syncErrorName:
                        "fsync inbox after duplicate removal"
                )
            }
        } else {
            let renameStatus = pending.withCString { pendingName in
                processing.withCString { processingName in
                    Darwin.renameatx_np(
                        rootDescriptor,
                        pendingName,
                        rootDescriptor,
                        processingName,
                        UInt32(RENAME_EXCL)
                    )
                }
            }
            guard renameStatus == 0 else {
                let code = errno
                if code == ENOENT {
                    throw PendingCaptureInboxError.captureNotFound
                }
                if code == EEXIST {
                    if try entryExists(
                        pending,
                        rootDescriptor: rootDescriptor
                    ) {
                        try removeEntryDurably(
                            pending,
                            rootDescriptor: rootDescriptor,
                            syncErrorName:
                                "fsync inbox after duplicate removal"
                        )
                    }
                    return try readClaimedCapture(
                        id: id,
                        filename: processing,
                        rootDescriptor: rootDescriptor
                    )
                }
                throw PendingCaptureInboxError.systemCallFailed(
                    name: "claim pending capture",
                    code: code
                )
            }
            guard directorySync(rootDescriptor) == 0 else {
                throw systemCallError("fsync inbox after claim")
            }
        }

        return try readClaimedCapture(
            id: id,
            filename: processing,
            rootDescriptor: rootDescriptor
        )
    }

    func acknowledge(_ claim: PendingCaptureClaim) throws {
        let rootDescriptor = try openRoot()
        defer {
            Darwin.close(rootDescriptor)
        }

        let filename = processingFilename(id: claim.id)
        var metadata = stat()
        let status = filename.withCString {
            Darwin.fstatat(
                rootDescriptor,
                $0,
                &metadata,
                AT_SYMLINK_NOFOLLOW
            )
        }
        guard status == 0 else {
            if errno == ENOENT {
                throw PendingCaptureInboxError.captureNotFound
            }
            throw systemCallError("inspect acknowledged capture")
        }
        guard
            validOwnerOnlyRegularFile(metadata),
            UInt64(metadata.st_dev) == claim.fileDevice,
            UInt64(metadata.st_ino) == claim.fileInode
        else {
            throw PendingCaptureInboxError.invalidEntry
        }

        guard filename.withCString({
            Darwin.unlinkat(rootDescriptor, $0, 0)
        }) == 0 else {
            throw systemCallError("remove acknowledged capture")
        }
        guard directorySync(rootDescriptor) == 0 else {
            throw systemCallError(
                "fsync inbox after acknowledge"
            )
        }
    }

    private func readClaimedCapture(
        id: UUID,
        filename: String,
        rootDescriptor: Int32
    ) throws -> PendingCaptureClaim {
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
                try removeEntryDurably(
                    filename,
                    rootDescriptor: rootDescriptor,
                    syncErrorName:
                        "fsync inbox after invalid entry removal"
                )
                throw PendingCaptureInboxError.invalidEntry
            }
            if code == ENOENT {
                throw PendingCaptureInboxError.captureNotFound
            }
            throw PendingCaptureInboxError.systemCallFailed(
                name: "open claimed capture",
                code: code
            )
        }

        var descriptorIsOpen = true
        do {
            var metadata = stat()
            guard Darwin.fstat(descriptor, &metadata) == 0 else {
                throw systemCallError("inspect claimed capture")
            }
            guard validOwnerOnlyRegularFile(metadata) else {
                throw PendingCaptureInboxError.invalidEntry
            }
            guard
                metadata.st_size > 0,
                metadata.st_size
                    <= SafePNGValidationPolicy.maximumImageLength
            else {
                throw PendingCaptureInboxError.imageTooLarge
            }

            let data = try Self.readAll(
                from: descriptor,
                expectedLength: Int(metadata.st_size)
            )
            try validatePNG(data)

            var pathMetadata = stat()
            guard filename.withCString({
                Darwin.fstatat(
                    rootDescriptor,
                    $0,
                    &pathMetadata,
                    AT_SYMLINK_NOFOLLOW
                )
            }) == 0 else {
                throw systemCallError("reinspect claimed capture")
            }
            guard
                validOwnerOnlyRegularFile(pathMetadata),
                pathMetadata.st_dev == metadata.st_dev,
                pathMetadata.st_ino == metadata.st_ino
            else {
                throw PendingCaptureInboxError.invalidEntry
            }

            let closeStatus = Darwin.close(descriptor)
            descriptorIsOpen = false
            guard closeStatus == 0 else {
                throw systemCallError("close claimed capture")
            }
            return PendingCaptureClaim(
                id: id,
                pngData: data,
                processingURL:
                    rootURL.appendingPathComponent(filename),
                fileDevice: UInt64(metadata.st_dev),
                fileInode: UInt64(metadata.st_ino)
            )
        } catch {
            if descriptorIsOpen {
                Darwin.close(descriptor)
            }
            switch error {
            case PendingCaptureInboxError.invalidEntry,
                 PendingCaptureInboxError.invalidPNG,
                 PendingCaptureInboxError.imageTooLarge:
                try removeEntryDurably(
                    filename,
                    rootDescriptor: rootDescriptor,
                    syncErrorName:
                        "fsync inbox after rejected capture"
                )
            default:
                break
            }
            throw error
        }
    }

    private func validatePNG(_ data: Data) throws {
        do {
            _ = try SafePNGValidationPolicy.validate(data)
        } catch SafePNGValidationError.invalidPNG {
            throw PendingCaptureInboxError.invalidPNG
        } catch SafePNGValidationError.imageTooLarge {
            throw PendingCaptureInboxError.imageTooLarge
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

    private func entryExists(
        _ filename: String,
        rootDescriptor: Int32
    ) throws -> Bool {
        var metadata = stat()
        let status = filename.withCString {
            Darwin.fstatat(
                rootDescriptor,
                $0,
                &metadata,
                AT_SYMLINK_NOFOLLOW
            )
        }
        if status == 0 {
            return true
        }
        if errno == ENOENT {
            return false
        }
        throw systemCallError("inspect inbox entry")
    }

    private func validOwnerOnlyRegularFile(
        _ metadata: stat
    ) -> Bool {
        metadata.st_mode & S_IFMT == S_IFREG
            && metadata.st_uid == getuid()
            && metadata.st_nlink == 1
            && metadata.st_mode & 0o777 == 0o600
    }

    private func pendingFilename(id: UUID) -> String {
        "\(id.uuidString).png"
    }

    private func processingFilename(id: UUID) -> String {
        "\(id.uuidString).processing"
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

    private func captureEntry(
        from filename: String
    ) -> (id: UUID, state: PendingEntryState)? {
        let state: PendingEntryState
        let suffix: String
        if filename.hasSuffix(".png") {
            state = .pending
            suffix = ".png"
        } else if filename.hasSuffix(".processing") {
            state = .processing
            suffix = ".processing"
        } else {
            return nil
        }

        guard
            let id = UUID(
                uuidString: String(filename.dropLast(suffix.count))
            ),
            filename
                == (state == .pending
                    ? pendingFilename(id: id)
                    : processingFilename(id: id))
        else {
            return nil
        }
        return (id, state)
    }

    private func removeEntryDurably(
        _ filename: String,
        rootDescriptor: Int32,
        syncErrorName: String
    ) throws {
        guard filename.withCString({
            Darwin.unlinkat(rootDescriptor, $0, 0)
        }) == 0 else {
            if errno == ENOENT {
                return
            }
            throw systemCallError("remove inbox entry")
        }
        guard directorySync(rootDescriptor) == 0 else {
            throw systemCallError(syncErrorName)
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
                throw systemCallError("read claimed capture")
            }
            if count == 0 {
                break
            }
            guard
                data.count + count
                    <= SafePNGValidationPolicy.maximumImageLength
            else {
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

private enum PendingEntryState {
    case pending
    case processing
}

private struct PendingEntry {
    let capture: StagedCapture
    let state: PendingEntryState
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
}
