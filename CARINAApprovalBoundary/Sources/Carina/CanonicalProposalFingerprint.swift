import CryptoKit
import Foundation

public enum CanonicalProposalFingerprint {
    public static let formatVersion: UInt64 = 1
    private static let domain = "CARINA.PROPOSAL.AUTHORITY"

    public static func normalizedDiffDigest(_ diff: String?) -> String {
        guard let diff else { return sha256Hex(Data()) }
        let normalized = diff
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return sha256Hex(Data(normalized.utf8))
    }

    public static func make(
        proposalID: UUID,
        sourceToolID: String,
        sourceContractVersion: UInt64,
        registryVersion: UInt64,
        repoRoot: String,
        mutations: [ValidatedFileMutation],
        filesystemBindings: [FilesystemStateBinding],
        normalizedDiffDigest: String
    ) -> String {
        var writer = CanonicalByteWriter()

        writer.appendString(domain)
        writer.appendUInt64(formatVersion)
        writer.appendString(proposalID.uuidString.lowercased())
        writer.appendString(sourceToolID)
        writer.appendUInt64(sourceContractVersion)
        writer.appendUInt64(registryVersion)
        writer.appendString(repoRoot)

        let sortedMutations = mutations.sorted(by: mutationSort)
        writer.appendUInt64(UInt64(sortedMutations.count))
        for mutation in sortedMutations {
            writer.appendString(mutation.operation.rawValue)
            writer.appendOptionalString(mutation.oldCanonicalPath)
            writer.appendOptionalString(mutation.newCanonicalPath)
            writer.appendBool(mutation.destructive)
        }

        let sortedBindings = filesystemBindings.sorted {
            if $0.path != $1.path { return $0.path < $1.path }
            return $0.role.rawValue < $1.role.rawValue
        }
        writer.appendUInt64(UInt64(sortedBindings.count))
        for binding in sortedBindings {
            writer.appendString(binding.path)
            writer.appendString(binding.role.rawValue)
            writer.appendString(binding.expectation.rawValue)
            writer.appendOptionalUInt64(binding.device)
            writer.appendOptionalUInt64(binding.inode)
            writer.appendOptionalString(binding.contentSHA256)
            writer.appendOptionalUInt64(binding.parentDevice)
            writer.appendOptionalUInt64(binding.parentInode)
        }

        writer.appendString(normalizedDiffDigest.lowercased())
        return sha256Hex(writer.data)
    }

    private static func mutationSort(_ lhs: ValidatedFileMutation, _ rhs: ValidatedFileMutation) -> Bool {
        let lhsPrimary = lhs.newCanonicalPath ?? lhs.oldCanonicalPath ?? ""
        let rhsPrimary = rhs.newCanonicalPath ?? rhs.oldCanonicalPath ?? ""
        if lhsPrimary != rhsPrimary { return lhsPrimary < rhsPrimary }
        if lhs.operation.rawValue != rhs.operation.rawValue {
            return lhs.operation.rawValue < rhs.operation.rawValue
        }
        return (lhs.oldCanonicalPath ?? "") < (rhs.oldCanonicalPath ?? "")
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct CanonicalByteWriter {
    private(set) var data = Data()

    mutating func appendUInt64(_ value: UInt64) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    mutating func appendBool(_ value: Bool) {
        data.append(value ? 1 : 0)
    }

    mutating func appendString(_ value: String) {
        let normalized = value.precomposedStringWithCanonicalMapping
        let bytes = Data(normalized.utf8)
        appendUInt64(UInt64(bytes.count))
        data.append(bytes)
    }

    mutating func appendOptionalString(_ value: String?) {
        guard let value else {
            data.append(0)
            return
        }
        data.append(1)
        appendString(value)
    }

    mutating func appendOptionalUInt64(_ value: UInt64?) {
        guard let value else {
            data.append(0)
            return
        }
        data.append(1)
        appendUInt64(value)
    }
}
