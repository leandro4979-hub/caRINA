import Foundation

public struct ObservedMutation: Equatable, Sendable {
    public let oldPath: String?
    public let newPath: String?
    public let operation: FileOperation

    public init(oldPath: String?, newPath: String?, operation: FileOperation) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.operation = operation
    }
}

public enum DiffParserError: Error, Equatable, Sendable {
    case malformedHeader
    case malformedFileSection
    case conflictingMetadata
    case invalidDevNullUsage
    case missingRenameSource
    case missingRenameDestination
    case pathChangeWithoutRenameMetadata
    case duplicateMetadata(String)
    case unsupportedDiffConstruct(String)
}

/// Quarantines raw Git-style unified diff text and emits typed file mutations.
///
/// Only metadata before the first hunk (`@@`) has structural meaning. Hunk body
/// text is intentionally opaque and can never become parser control input.
public struct DiffMutationInspector: Sendable {
    private struct FileSection {
        let headerOldPath: String
        let headerNewPath: String
        var oldMarkerPath: String?
        var newMarkerPath: String?
        var hasNewFileMode = false
        var hasDeletedFileMode = false
        var renameFrom: String?
        var renameTo: String?
        var enteredHunks = false
    }

    public init() {}

    public func inspect(_ diff: String) throws -> [ObservedMutation] {
        var mutations: [ObservedMutation] = []
        var current: FileSection?

        for rawLine in diff.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("diff --git ") {
                if let section = current {
                    mutations.append(try finalize(section))
                }
                current = try parseGitHeader(line)
                continue
            }

            guard var section = current else {
                throw DiffParserError.malformedFileSection
            }

            if section.enteredHunks {
                // Everything in hunk bodies is inert until the next diff header.
                current = section
                continue
            }

            if line.hasPrefix("@@") {
                section.enteredHunks = true
                current = section
                continue
            }

            try parseMetadataLine(line, section: &section)
            current = section
        }

        if let section = current {
            mutations.append(try finalize(section))
        }

        return mutations
    }

    private func parseGitHeader(_ line: String) throws -> FileSection {
        let parts = line.split(whereSeparator: { $0.isWhitespace })
        guard parts.count == 4,
              parts[0] == "diff",
              parts[1] == "--git"
        else {
            throw DiffParserError.malformedHeader
        }

        let oldRaw = String(parts[2])
        let newRaw = String(parts[3])
        guard oldRaw.hasPrefix("a/"), newRaw.hasPrefix("b/") else {
            throw DiffParserError.malformedHeader
        }

        let oldPath = String(oldRaw.dropFirst(2))
        let newPath = String(newRaw.dropFirst(2))
        guard !oldPath.isEmpty, !newPath.isEmpty else {
            throw DiffParserError.malformedHeader
        }

        return FileSection(headerOldPath: oldPath, headerNewPath: newPath)
    }

    private func parseMetadataLine(_ line: String, section: inout FileSection) throws {
        if line.hasPrefix("GIT binary patch") || line.hasPrefix("Binary files ") {
            throw DiffParserError.unsupportedDiffConstruct("binary")
        }
        if line.hasPrefix("copy from ") || line.hasPrefix("copy to ") {
            throw DiffParserError.unsupportedDiffConstruct("copy")
        }

        if line.hasPrefix("new file mode ") {
            guard !section.hasNewFileMode else {
                throw DiffParserError.duplicateMetadata("new file mode")
            }
            section.hasNewFileMode = true
            return
        }

        if line.hasPrefix("deleted file mode ") {
            guard !section.hasDeletedFileMode else {
                throw DiffParserError.duplicateMetadata("deleted file mode")
            }
            section.hasDeletedFileMode = true
            return
        }

        if line.hasPrefix("rename from ") {
            guard section.renameFrom == nil else {
                throw DiffParserError.duplicateMetadata("rename from")
            }
            section.renameFrom = String(line.dropFirst("rename from ".count))
            return
        }

        if line.hasPrefix("rename to ") {
            guard section.renameTo == nil else {
                throw DiffParserError.duplicateMetadata("rename to")
            }
            section.renameTo = String(line.dropFirst("rename to ".count))
            return
        }

        if line.hasPrefix("--- ") {
            guard section.oldMarkerPath == nil else {
                throw DiffParserError.duplicateMetadata("---")
            }
            section.oldMarkerPath = cleanMarkerPath(String(line.dropFirst(4)))
            return
        }

        if line.hasPrefix("+++ ") {
            guard section.newMarkerPath == nil else {
                throw DiffParserError.duplicateMetadata("+++")
            }
            section.newMarkerPath = cleanMarkerPath(String(line.dropFirst(4)))
            return
        }

        // Known Git metadata that does not change our operation classification.
        if line.hasPrefix("index ") ||
            line.hasPrefix("old mode ") ||
            line.hasPrefix("new mode ") ||
            line.hasPrefix("similarity index ") ||
            line.hasPrefix("dissimilarity index ") {
            return
        }

        throw DiffParserError.unsupportedDiffConstruct(line)
    }

    private func cleanMarkerPath(_ rawPath: String) -> String {
        let path = rawPath.trimmingCharacters(in: .whitespaces)
        if path == "/dev/null" { return path }
        if path.hasPrefix("a/") || path.hasPrefix("b/") {
            return String(path.dropFirst(2))
        }
        return path
    }

    private func finalize(_ section: FileSection) throws -> ObservedMutation {
        try validateSection(section)

        let old = section.headerOldPath
        let new = section.headerNewPath

        if section.renameFrom != nil || section.renameTo != nil {
            guard let from = section.renameFrom else {
                throw DiffParserError.missingRenameSource
            }
            guard let to = section.renameTo else {
                throw DiffParserError.missingRenameDestination
            }
            guard from != "/dev/null", to != "/dev/null" else {
                throw DiffParserError.invalidDevNullUsage
            }
            guard from == old, to == new, from != to else {
                throw DiffParserError.malformedFileSection
            }
            return ObservedMutation(oldPath: from, newPath: to, operation: .rename)
        }

        if old != new {
            throw DiffParserError.pathChangeWithoutRenameMetadata
        }

        if section.hasNewFileMode {
            guard section.oldMarkerPath == "/dev/null",
                  section.newMarkerPath == new
            else {
                throw DiffParserError.invalidDevNullUsage
            }
            return ObservedMutation(oldPath: nil, newPath: new, operation: .create)
        }

        if section.hasDeletedFileMode {
            guard section.oldMarkerPath == old,
                  section.newMarkerPath == "/dev/null"
            else {
                throw DiffParserError.invalidDevNullUsage
            }
            return ObservedMutation(oldPath: old, newPath: nil, operation: .delete)
        }

        guard section.oldMarkerPath == old,
              section.newMarkerPath == new,
              section.oldMarkerPath != "/dev/null",
              section.newMarkerPath != "/dev/null"
        else {
            throw DiffParserError.malformedFileSection
        }

        return ObservedMutation(oldPath: old, newPath: new, operation: .modify)
    }

    private func validateSection(_ section: FileSection) throws {
        if section.hasNewFileMode && section.hasDeletedFileMode {
            throw DiffParserError.conflictingMetadata
        }

        let hasRename = section.renameFrom != nil || section.renameTo != nil
        if hasRename && (section.hasNewFileMode || section.hasDeletedFileMode) {
            throw DiffParserError.conflictingMetadata
        }

        if section.renameFrom != nil && section.renameTo == nil {
            throw DiffParserError.missingRenameDestination
        }
        if section.renameFrom == nil && section.renameTo != nil {
            throw DiffParserError.missingRenameSource
        }
    }
}
