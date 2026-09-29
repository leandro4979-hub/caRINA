import CryptoKit
import Darwin
import Foundation

public enum FilesystemBindingRole: String, Codable, Sendable, Hashable {
    case source
    case destination
}

public enum FilesystemExpectation: String, Codable, Sendable, Hashable {
    case existing
    case absent
}

public struct FilesystemStateBinding: Codable, Sendable, Equatable, Hashable {
    public let path: String
    public let role: FilesystemBindingRole
    public let expectation: FilesystemExpectation
    public let device: UInt64?
    public let inode: UInt64?
    public let contentSHA256: String?
    public let parentDevice: UInt64?
    public let parentInode: UInt64?

    public init(
        path: String,
        role: FilesystemBindingRole,
        expectation: FilesystemExpectation,
        device: UInt64?,
        inode: UInt64?,
        contentSHA256: String?,
        parentDevice: UInt64?,
        parentInode: UInt64?
    ) {
        self.path = path
        self.role = role
        self.expectation = expectation
        self.device = device
        self.inode = inode
        self.contentSHA256 = contentSHA256
        self.parentDevice = parentDevice
        self.parentInode = parentInode
    }
}

public enum FilesystemStateBindingError: Error, Equatable, Sendable {
    case missingExpectedPath(String)
    case destinationAlreadyExists(String)
    case missingParent(String)
    case symlinkDetected(String)
    case unsupportedObjectType(String)
    case metadataReadFailed(String)
    case contentReadFailed(String)
    case stateChanged(String)
}

public protocol FilesystemStateCapturing: Sendable {
    func capture(for mutations: [ValidatedFileMutation]) throws -> [FilesystemStateBinding]
    func revalidate(_ bindings: [FilesystemStateBinding]) throws
}

public struct FilesystemStateBinder: FilesystemStateCapturing {
    public init() {}

    public func capture(for mutations: [ValidatedFileMutation]) throws -> [FilesystemStateBinding] {
        var result: [FilesystemStateBinding] = []

        for mutation in mutations {
            switch mutation.operation {
            case .create:
                guard let destination = mutation.newCanonicalPath else { continue }
                result.append(try captureAbsent(path: destination, role: .destination))

            case .modify, .delete:
                guard let source = mutation.oldCanonicalPath ?? mutation.newCanonicalPath else { continue }
                result.append(try captureExisting(path: source, role: .source))

            case .rename:
                guard let source = mutation.oldCanonicalPath,
                      let destination = mutation.newCanonicalPath
                else { continue }
                result.append(try captureExisting(path: source, role: .source))
                result.append(try captureAbsent(path: destination, role: .destination))
            }
        }

        return result.sorted {
            if $0.path != $1.path { return $0.path < $1.path }
            return $0.role.rawValue < $1.role.rawValue
        }
    }

    public func revalidate(_ bindings: [FilesystemStateBinding]) throws {
        for expected in bindings {
            let current: FilesystemStateBinding
            switch expected.expectation {
            case .existing:
                current = try captureExisting(path: expected.path, role: expected.role)
            case .absent:
                current = try captureAbsent(path: expected.path, role: expected.role)
            }

            guard current == expected else {
                throw FilesystemStateBindingError.stateChanged(expected.path)
            }
        }
    }

    private func captureExisting(path: String, role: FilesystemBindingRole) throws -> FilesystemStateBinding {
        let object = try statObject(path: path, mustExist: true)
        if object.isSymlink { throw FilesystemStateBindingError.symlinkDetected(path) }
        guard object.isRegularFile else {
            throw FilesystemStateBindingError.unsupportedObjectType(path)
        }

        let parent = try statParent(of: path)
        let digest = try sha256File(path: path)

        return FilesystemStateBinding(
            path: path,
            role: role,
            expectation: .existing,
            device: object.device,
            inode: object.inode,
            contentSHA256: digest,
            parentDevice: parent.device,
            parentInode: parent.inode
        )
    }

    private func captureAbsent(path: String, role: FilesystemBindingRole) throws -> FilesystemStateBinding {
        let object = try statObject(path: path, mustExist: false)
        if object.exists {
            throw FilesystemStateBindingError.destinationAlreadyExists(path)
        }

        let parent = try statParent(of: path)
        return FilesystemStateBinding(
            path: path,
            role: role,
            expectation: .absent,
            device: nil,
            inode: nil,
            contentSHA256: nil,
            parentDevice: parent.device,
            parentInode: parent.inode
        )
    }

    private func statParent(of path: String) throws -> ObjectStat {
        let parentPath = URL(fileURLWithPath: path).deletingLastPathComponent().path
        let parent = try statObject(path: parentPath, mustExist: true)
        if parent.isSymlink { throw FilesystemStateBindingError.symlinkDetected(parentPath) }
        guard parent.isDirectory else {
            throw FilesystemStateBindingError.missingParent(parentPath)
        }
        return parent
    }

    private func statObject(path: String, mustExist: Bool) throws -> ObjectStat {
        var info = stat()
        let rc = path.withCString { lstat($0, &info) }

        if rc != 0 {
            if errno == ENOENT && !mustExist {
                return ObjectStat(exists: false, device: 0, inode: 0, mode: 0)
            }
            if errno == ENOENT {
                throw FilesystemStateBindingError.missingExpectedPath(path)
            }
            throw FilesystemStateBindingError.metadataReadFailed(path)
        }

        return ObjectStat(
            exists: true,
            device: UInt64(info.st_dev),
            inode: UInt64(info.st_ino),
            mode: info.st_mode
        )
    }

    private func sha256File(path: String) throws -> String {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            throw FilesystemStateBindingError.contentReadFailed(path)
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        do {
            while true {
                let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
            }
        } catch {
            throw FilesystemStateBindingError.contentReadFailed(path)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private struct ObjectStat {
    let exists: Bool
    let device: UInt64
    let inode: UInt64
    let mode: mode_t

    var fileType: mode_t { mode & S_IFMT }
    var isSymlink: Bool { exists && fileType == S_IFLNK }
    var isRegularFile: Bool { exists && fileType == S_IFREG }
    var isDirectory: Bool { exists && fileType == S_IFDIR }
}
