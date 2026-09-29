import XCTest
@testable import Carina

final class DiffMutationInspectorTests: XCTestCase {
    private let inspector = DiffMutationInspector()

    func testParsesModification() throws {
        let diff = """
        diff --git a/Sources/Config.swift b/Sources/Config.swift
        index 123456..789012 100644
        --- a/Sources/Config.swift
        +++ b/Sources/Config.swift
        @@ -1,1 +1,1 @@
        -let version = "1.0"
        +let version = "1.1"
        """

        XCTAssertEqual(
            try inspector.inspect(diff),
            [ObservedMutation(oldPath: "Sources/Config.swift", newPath: "Sources/Config.swift", operation: .modify)]
        )
    }

    func testParsesCreateDeleteRenameAndMultipleSections() throws {
        let diff = """
        diff --git a/Sources/New.swift b/Sources/New.swift
        new file mode 100644
        --- /dev/null
        +++ b/Sources/New.swift
        diff --git a/Sources/Old.swift b/Sources/Old.swift
        deleted file mode 100644
        --- a/Sources/Old.swift
        +++ /dev/null
        diff --git a/Sources/A.swift b/Sources/B.swift
        similarity index 100%
        rename from Sources/A.swift
        rename to Sources/B.swift
        """

        XCTAssertEqual(
            try inspector.inspect(diff),
            [
                ObservedMutation(oldPath: nil, newPath: "Sources/New.swift", operation: .create),
                ObservedMutation(oldPath: "Sources/Old.swift", newPath: nil, operation: .delete),
                ObservedMutation(oldPath: "Sources/A.swift", newPath: "Sources/B.swift", operation: .rename)
            ]
        )
    }

    func testHunkContentsCannotBecomeMetadata() throws {
        let diff = """
        diff --git a/Sources/Safe.swift b/Sources/Safe.swift
        --- a/Sources/Safe.swift
        +++ b/Sources/Safe.swift
        @@ -1,1 +1,3 @@
        -print("hello")
        +print("deleted file mode 100644")
        +print("rename to ../../Secrets/key.txt")
        +print("GIT binary patch")
        """

        XCTAssertEqual(
            try inspector.inspect(diff),
            [ObservedMutation(oldPath: "Sources/Safe.swift", newPath: "Sources/Safe.swift", operation: .modify)]
        )
    }

    func testRejectsMalformedHeader() {
        XCTAssertThrowsError(try inspector.inspect("diff --git only-one-path.swift")) {
            XCTAssertEqual($0 as? DiffParserError, .malformedHeader)
        }
    }

    func testRejectsPathChangeWithoutRenameMetadata() {
        let diff = """
        diff --git a/Sources/Old.swift b/Sources/New.swift
        --- a/Sources/Old.swift
        +++ b/Sources/New.swift
        """

        XCTAssertThrowsError(try inspector.inspect(diff)) {
            XCTAssertEqual($0 as? DiffParserError, .pathChangeWithoutRenameMetadata)
        }
    }

    func testRejectsDuplicateMarkers() {
        let diff = """
        diff --git a/Sources/A.swift b/Sources/A.swift
        --- a/Sources/A.swift
        --- a/Sources/Other.swift
        +++ b/Sources/A.swift
        """

        XCTAssertThrowsError(try inspector.inspect(diff)) {
            XCTAssertEqual($0 as? DiffParserError, .duplicateMetadata("---"))
        }
    }

    func testRejectsConflictingModeMarkers() {
        let diff = """
        diff --git a/Sources/A.swift b/Sources/A.swift
        new file mode 100644
        deleted file mode 100644
        """

        XCTAssertThrowsError(try inspector.inspect(diff)) {
            XCTAssertEqual($0 as? DiffParserError, .conflictingMetadata)
        }
    }

    func testRejectsRenameMixedWithDeleteMetadata() {
        let diff = """
        diff --git a/Sources/A.swift b/Sources/B.swift
        deleted file mode 100644
        rename from Sources/A.swift
        rename to Sources/B.swift
        """

        XCTAssertThrowsError(try inspector.inspect(diff)) {
            XCTAssertEqual($0 as? DiffParserError, .conflictingMetadata)
        }
    }

    func testRejectsDevNullRename() {
        let diff = """
        diff --git a/dev/null b/Sources/B.swift
        rename from /dev/null
        rename to Sources/B.swift
        """

        XCTAssertThrowsError(try inspector.inspect(diff)) {
            XCTAssertEqual($0 as? DiffParserError, .invalidDevNullUsage)
        }
    }

    func testRejectsTextBeforeFirstDiffHeader() {
        let diff = """
        not-a-diff
        diff --git a/Sources/A.swift b/Sources/A.swift
        --- a/Sources/A.swift
        +++ b/Sources/A.swift
        """

        XCTAssertThrowsError(try inspector.inspect(diff)) {
            XCTAssertEqual($0 as? DiffParserError, .malformedFileSection)
        }
    }

    func testRejectsUnsupportedBinaryAndCopyMetadata() {
        let binary = """
        diff --git a/A.bin b/A.bin
        GIT binary patch
        """
        XCTAssertThrowsError(try inspector.inspect(binary)) {
            XCTAssertEqual($0 as? DiffParserError, .unsupportedDiffConstruct("binary"))
        }

        let copy = """
        diff --git a/A.swift b/B.swift
        copy from A.swift
        copy to B.swift
        """
        XCTAssertThrowsError(try inspector.inspect(copy)) {
            XCTAssertEqual($0 as? DiffParserError, .unsupportedDiffConstruct("copy"))
        }
    }
}
