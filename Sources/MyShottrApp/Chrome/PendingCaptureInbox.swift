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

struct PresentedCapture: Equatable, Sendable {
    let id: UUID
    let presentedURL: URL
    let fileDevice: UInt64
    let fileInode: UInt64
}

enum PresentedCleanupResult: Equatable, Sendable {
    case removed
    case alreadyAbsent
    case removedAwaitingDurability
}

protocol PendingCaptureStoring: Sendable {
    func stage(pngData: Data) throws -> StagedCapture
    func pendingCaptures() throws -> [StagedCapture]
    func cleanupOnlyCaptures() throws -> [PresentedCapture]
    func claim(id: UUID) throws -> PendingCaptureClaim
    func commitPresentation(
        _ claim: PendingCaptureClaim
    ) throws -> PresentedCapture
    func cleanupPresented(
        _ presented: PresentedCapture
    ) throws -> PresentedCleanupResult
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
    private let stateIDGenerator: @Sendable () -> UUID
    private let directorySync: @Sendable (Int32) -> Int32
    private let renameEntry:
        @Sendable (Int32, String, String) -> Int32
    private let unlinkEntry: @Sendable (Int32, String) -> Int32

    init(
        root: URL = PendingCaptureInbox.defaultRootURL,
        idGenerator: @escaping @Sendable () -> UUID = UUID.init,
        stateIDGenerator:
            @escaping @Sendable () -> UUID = UUID.init,
        directorySync:
            @escaping @Sendable (Int32) -> Int32 = Darwin.fsync,
        renameEntry:
            @escaping @Sendable (
                Int32,
                String,
                String
            ) -> Int32 = Self.renameExclusive,
        unlinkEntry:
            @escaping @Sendable (
                Int32,
                String
            ) -> Int32 = Self.unlink
    ) throws {
        rootURL = root.standardizedFileURL
        self.idGenerator = idGenerator
        self.stateIDGenerator = stateIDGenerator
        self.directorySync = directorySync
        self.renameEntry = renameEntry
        self.unlinkEntry = unlinkEntry
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
        guard try stateEntries(
            id: id,
            rootDescriptor: rootDescriptor
        ).isEmpty else {
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

        let entries = try parsedEntries(rootDescriptor: rootDescriptor)
        let cleanupOnlyIDs = Set(
            entries
                .filter { $0.state.isCleanupOnly }
                .map(\.id)
        )
        var entriesByID: [UUID: PendingEntry] = [:]

        for parsed in entries {
            guard
                parsed.state == .pending
                    || parsed.state == .processing,
                !cleanupOnlyIDs.contains(parsed.id)
            else {
                continue
            }

            var metadata = stat()
            let status = parsed.filename.withCString {
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
                    pngURL:
                        rootURL.appendingPathComponent(parsed.filename)
                ),
                state: parsed.state,
                modifiedSeconds: metadata.st_mtimespec.tv_sec,
                modifiedNanoseconds: metadata.st_mtimespec.tv_nsec
            )
            if let current = entriesByID[parsed.id],
               current.state == .processing,
               parsed.state == .pending {
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

    func cleanupOnlyCaptures() throws -> [PresentedCapture] {
        let rootDescriptor = try openRoot()
        defer {
            Darwin.close(rootDescriptor)
        }

        let entries = try parsedEntries(rootDescriptor: rootDescriptor)
        let cleanupOnlyIDs = Set(
            entries
                .filter { $0.state.isCleanupOnly }
                .map(\.id)
        )
        for entry in entries where
            cleanupOnlyIDs.contains(entry.id)
                && !entry.state.isCleanupOnly {
            _ = try quarantineAndRemove(
                entry.filename,
                id: entry.id,
                expectedIdentity: nil,
                rootDescriptor: rootDescriptor
            )
        }

        var captures: [PresentedCapture] = []
        for entry in entries {
            guard entry.state.isCleanupOnly else {
                continue
            }

            var metadata = stat()
            let status = entry.filename.withCString {
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
                throw systemCallError("inspect cleanup-only capture")
            }

            let identity = FileIdentity(metadata)
            guard validOwnerOnlyRegularFile(metadata) else {
                _ = try quarantineAndRemove(
                    entry.filename,
                    id: entry.id,
                    expectedIdentity: identity,
                    rootDescriptor: rootDescriptor
                )
                continue
            }
            captures.append(
                PresentedCapture(
                    id: entry.id,
                    presentedURL:
                        rootURL.appendingPathComponent(entry.filename),
                    fileDevice: identity.device,
                    fileInode: identity.inode
                )
            )
        }
        return captures.sorted {
            $0.presentedURL.lastPathComponent
                < $1.presentedURL.lastPathComponent
        }
    }

    func claim(id: UUID) throws -> PendingCaptureClaim {
        let rootDescriptor = try openRoot()
        defer {
            Darwin.close(rootDescriptor)
        }

        let pending = pendingFilename(id: id)
        let existing = try stateEntries(
            id: id,
            rootDescriptor: rootDescriptor
        )
        if existing.contains(where: { $0.state.isCleanupOnly }) {
            throw PendingCaptureInboxError.captureNotFound
        }
        if let processing = existing
            .filter({ $0.state == .processing })
            .sorted(by: { $0.filename < $1.filename })
            .first {
            if try entryExists(
                pending,
                rootDescriptor: rootDescriptor
            ) {
                _ = try quarantineAndRemove(
                    pending,
                    id: id,
                    expectedIdentity: nil,
                    rootDescriptor: rootDescriptor
                )
            }
            for duplicate in existing where
                duplicate.state == .processing
                    && duplicate.filename != processing.filename {
                _ = try quarantineAndRemove(
                    duplicate.filename,
                    id: id,
                    expectedIdentity: nil,
                    rootDescriptor: rootDescriptor
                )
            }
            return try readClaimedCapture(
                id: id,
                filename: processing.filename,
                rootDescriptor: rootDescriptor
            )
        }

        let processing = stateFilename(
            id: id,
            stateID: stateIDGenerator(),
            state: .processing
        )
        guard renameEntry(rootDescriptor, pending, processing) == 0 else {
            let code = errno
            if code == ENOENT {
                throw PendingCaptureInboxError.captureNotFound
            }
            throw PendingCaptureInboxError.systemCallFailed(
                name: "claim pending capture",
                code: code
            )
        }
        guard directorySync(rootDescriptor) == 0 else {
            throw systemCallError("fsync inbox after claim")
        }
        return try readClaimedCapture(
            id: id,
            filename: processing,
            rootDescriptor: rootDescriptor
        )
    }

    func commitPresentation(
        _ claim: PendingCaptureClaim
    ) throws -> PresentedCapture {
        let rootDescriptor = try openRoot()
        defer {
            Darwin.close(rootDescriptor)
        }

        let expectedIdentity = FileIdentity(
            device: claim.fileDevice,
            inode: claim.fileInode
        )
        let processing = claim.processingURL.lastPathComponent
        guard
            let parsedProcessing = captureEntry(from: processing),
            parsedProcessing.id == claim.id,
            parsedProcessing.state == .processing,
            parsedProcessing.filename == processing
        else {
            throw PendingCaptureInboxError.invalidEntry
        }
        let presented = stateFilename(
            id: claim.id,
            stateID: parsedProcessing.stateID,
            state: .presented
        )

        if try !entryExists(
            processing,
            rootDescriptor: rootDescriptor
        ) {
            if let recovered = try locateEntry(
                id: claim.id,
                states: [.presented],
                identity: expectedIdentity,
                rootDescriptor: rootDescriptor
            ) {
                guard directorySync(rootDescriptor) == 0 else {
                    throw systemCallError(
                        "fsync inbox after presented transition"
                    )
                }
                return recovered
            }
            throw PendingCaptureInboxError.captureNotFound
        }

        guard renameEntry(
            rootDescriptor,
            processing,
            presented
        ) == 0 else {
            throw systemCallError("commit presented capture")
        }

        var movedMetadata = stat()
        guard presented.withCString({
            Darwin.fstatat(
                rootDescriptor,
                $0,
                &movedMetadata,
                AT_SYMLINK_NOFOLLOW
            )
        }) == 0 else {
            throw systemCallError("verify presented capture")
        }
        guard
            validOwnerOnlyRegularFile(movedMetadata),
            FileIdentity(movedMetadata) == expectedIdentity
        else {
            throw PendingCaptureInboxError.invalidEntry
        }
        guard directorySync(rootDescriptor) == 0 else {
            throw systemCallError(
                "fsync inbox after presented transition"
            )
        }

        return PresentedCapture(
            id: claim.id,
            presentedURL: rootURL.appendingPathComponent(presented),
            fileDevice: expectedIdentity.device,
            fileInode: expectedIdentity.inode
        )
    }

    func cleanupPresented(
        _ presented: PresentedCapture
    ) throws -> PresentedCleanupResult {
        let rootDescriptor = try openRoot()
        defer {
            Darwin.close(rootDescriptor)
        }

        let identity = FileIdentity(
            device: presented.fileDevice,
            inode: presented.fileInode
        )
        guard let located = try locateCleanupFilename(
            presented,
            identity: identity,
            rootDescriptor: rootDescriptor
        ) else {
            return .alreadyAbsent
        }
        return try quarantineAndRemove(
            located,
            id: presented.id,
            expectedIdentity: identity,
            rootDescriptor: rootDescriptor
        )
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
                _ = try quarantineAndRemove(
                    filename,
                    id: id,
                    expectedIdentity: nil,
                    rootDescriptor: rootDescriptor
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
        var expectedIdentity: FileIdentity?
        do {
            var metadata = stat()
            guard Darwin.fstat(descriptor, &metadata) == 0 else {
                throw systemCallError("inspect claimed capture")
            }
            expectedIdentity = FileIdentity(metadata)
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
                _ = try quarantineAndRemove(
                    filename,
                    id: id,
                    expectedIdentity: expectedIdentity,
                    rootDescriptor: rootDescriptor
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

    private func stateFilename(
        id: UUID,
        stateID: UUID,
        state: PendingEntryState
    ) -> String {
        precondition(state != .pending)
        return "\(id.uuidString).\(stateID.uuidString).\(state.rawValue)"
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

    private func parsedEntries(
        rootDescriptor: Int32
    ) throws -> [ParsedInboxEntry] {
        try directoryFilenames(rootDescriptor: rootDescriptor)
            .compactMap(captureEntry(from:))
    }

    private func stateEntries(
        id: UUID,
        rootDescriptor: Int32
    ) throws -> [ParsedInboxEntry] {
        try parsedEntries(rootDescriptor: rootDescriptor)
            .filter { $0.id == id }
    }

    private func captureEntry(
        from filename: String
    ) -> ParsedInboxEntry? {
        if filename.hasSuffix(".png") {
            guard
                let id = UUID(
                    uuidString:
                        String(filename.dropLast(".png".count))
                ),
                filename == pendingFilename(id: id)
            else {
                return nil
            }
            return ParsedInboxEntry(
                id: id,
                stateID: Self.pendingStateID,
                state: .pending,
                filename: filename
            )
        }

        let components = filename.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard
            components.count == 3,
            let id = UUID(uuidString: String(components[0])),
            let stateID = UUID(uuidString: String(components[1])),
            let state = PendingEntryState(
                rawValue: String(components[2])
            ),
            state != .pending,
            filename == stateFilename(
                id: id,
                stateID: stateID,
                state: state
            )
        else {
            return nil
        }
        return ParsedInboxEntry(
            id: id,
            stateID: stateID,
            state: state,
            filename: filename
        )
    }

    private func locateEntry(
        id: UUID,
        states: Set<PendingEntryState>,
        identity: FileIdentity,
        rootDescriptor: Int32
    ) throws -> PresentedCapture? {
        for entry in try stateEntries(
            id: id,
            rootDescriptor: rootDescriptor
        ) where states.contains(entry.state) {
            var metadata = stat()
            let status = entry.filename.withCString {
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
                throw systemCallError("inspect recovered capture")
            }
            guard
                validOwnerOnlyRegularFile(metadata),
                FileIdentity(metadata) == identity
            else {
                continue
            }
            return PresentedCapture(
                id: id,
                presentedURL:
                    rootURL.appendingPathComponent(entry.filename),
                fileDevice: identity.device,
                fileInode: identity.inode
            )
        }
        return nil
    }

    private func locateCleanupFilename(
        _ presented: PresentedCapture,
        identity: FileIdentity,
        rootDescriptor: Int32
    ) throws -> String? {
        let preferred = presented.presentedURL.lastPathComponent
        if
            let parsed = captureEntry(from: preferred),
            parsed.id == presented.id,
            parsed.state.isCleanupOnly,
            try entryHasIdentity(
                preferred,
                identity: identity,
                rootDescriptor: rootDescriptor
            )
        {
            return preferred
        }

        return try stateEntries(
            id: presented.id,
            rootDescriptor: rootDescriptor
        )
        .filter { $0.state.isCleanupOnly }
        .first {
            try entryHasIdentity(
                $0.filename,
                identity: identity,
                rootDescriptor: rootDescriptor
            )
        }?.filename
    }

    private func entryHasIdentity(
        _ filename: String,
        identity: FileIdentity,
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
        if status != 0 {
            if errno == ENOENT {
                return false
            }
            throw systemCallError("inspect cleanup path")
        }
        return FileIdentity(metadata) == identity
    }

    private func quarantineAndRemove(
        _ filename: String,
        id: UUID,
        expectedIdentity: FileIdentity?,
        rootDescriptor: Int32
    ) throws -> PresentedCleanupResult {
        var sourceMetadata = stat()
        let sourceStatus = filename.withCString {
            Darwin.fstatat(
                rootDescriptor,
                $0,
                &sourceMetadata,
                AT_SYMLINK_NOFOLLOW
            )
        }
        if sourceStatus != 0 {
            if errno == ENOENT {
                return .alreadyAbsent
            }
            throw systemCallError("inspect quarantined capture")
        }
        let sourceIdentity = FileIdentity(sourceMetadata)
        let quarantine = stateFilename(
            id: id,
            stateID: stateIDGenerator(),
            state: .quarantine
        )
        let renameStatus = renameEntry(
            rootDescriptor,
            filename,
            quarantine
        )
        if renameStatus != 0 {
            if errno == ENOENT {
                return .alreadyAbsent
            }
            throw systemCallError("quarantine capture")
        }

        var movedMetadata = stat()
        guard quarantine.withCString({
            Darwin.fstatat(
                rootDescriptor,
                $0,
                &movedMetadata,
                AT_SYMLINK_NOFOLLOW
            )
        }) == 0 else {
            throw systemCallError("verify quarantined capture")
        }
        let movedIdentity = FileIdentity(movedMetadata)
        guard
            movedMetadata.st_uid == getuid(),
            movedIdentity == sourceIdentity,
            expectedIdentity == nil
                || movedIdentity == expectedIdentity
        else {
            throw PendingCaptureInboxError.invalidEntry
        }
        guard directorySync(rootDescriptor) == 0 else {
            throw systemCallError(
                "fsync inbox after quarantine transition"
            )
        }
        guard unlinkEntry(rootDescriptor, quarantine) == 0 else {
            if errno == ENOENT {
                return .alreadyAbsent
            }
            throw systemCallError("remove quarantined capture")
        }
        guard directorySync(rootDescriptor) == 0 else {
            return .removedAwaitingDurability
        }
        return .removed
    }

    private static func renameExclusive(
        _ directory: Int32,
        _ source: String,
        _ destination: String
    ) -> Int32 {
        source.withCString { sourceName in
            destination.withCString { destinationName in
                Darwin.renameatx_np(
                    directory,
                    sourceName,
                    directory,
                    destinationName,
                    UInt32(RENAME_EXCL)
                )
            }
        }
    }

    private static func unlink(
        _ directory: Int32,
        _ filename: String
    ) -> Int32 {
        filename.withCString {
            Darwin.unlinkat(directory, $0, 0)
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

    private static let pendingStateID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000000"
    )!

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

private enum PendingEntryState: String, Hashable {
    case pending
    case processing
    case presented
    case quarantine

    var isCleanupOnly: Bool {
        self == .presented || self == .quarantine
    }
}

private struct ParsedInboxEntry {
    let id: UUID
    let stateID: UUID
    let state: PendingEntryState
    let filename: String
}

private struct FileIdentity: Equatable {
    let device: UInt64
    let inode: UInt64

    init(device: UInt64, inode: UInt64) {
        self.device = device
        self.inode = inode
    }

    init(_ metadata: stat) {
        device = UInt64(metadata.st_dev)
        inode = UInt64(metadata.st_ino)
    }
}

private struct PendingEntry {
    let capture: StagedCapture
    let state: PendingEntryState
    let modifiedSeconds: Int
    let modifiedNanoseconds: Int
}
