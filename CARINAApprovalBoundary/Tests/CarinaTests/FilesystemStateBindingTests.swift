import Foundation
import XCTest
@testable import Carina

final class FilesystemStateBindingTests: XCTestCase {
    private let binder = FilesystemStateBinder()

    func testExistingFileRevalidatesWhenUnchanged() throws {
        let fixture = try TempFixture()
        let file = fixture.root.appendingPathComponent("A.swift")
        try Data("let a = 1\n".utf8).write(to: file)

        let mutation = ValidatedFileMutation(
            oldCanonicalPath: file.path,
            newCanonicalPath: file.path,
            operation: .modify,
            destructive: false
        )

        let bindings = try binder.capture(for: [mutation])
        XCTAssertNoThrow(try binder.revalidate(bindings))
    }

    func testContentSwapFailsRevalidation() throws {
        let fixture = try TempFixture()
        let file = fixture.root.appendingPathComponent("A.swift")
        try Data("let a = 1\n".utf8).write(to: file)

        let mutation = ValidatedFileMutation(
            oldCanonicalPath: file.path,
            newCanonicalPath: file.path,
            operation: .modify,
            destructive: false
        )
        let bindings = try binder.capture(for: [mutation])

        try Data("let a = 2\n".utf8).write(to: file)

        XCTAssertThrowsError(try binder.revalidate(bindings)) { error in
            XCTAssertEqual(error as? FilesystemStateBindingError, .stateChanged(file.path))
        }
    }

    func testCreateBindsAbsentDestinationAndParentIdentity() throws {
        let fixture = try TempFixture()
        let destination = fixture.root.appendingPathComponent("New.swift")

        let mutation = ValidatedFileMutation(
            oldCanonicalPath: nil,
            newCanonicalPath: destination.path,
            operation: .create,
            destructive: false
        )
        let bindings = try binder.capture(for: [mutation])

        XCTAssertEqual(bindings.count, 1)
        XCTAssertEqual(bindings[0].expectation, .absent)
        XCTAssertNotNil(bindings[0].parentDevice)
        XCTAssertNotNil(bindings[0].parentInode)
        XCTAssertNoThrow(try binder.revalidate(bindings))
    }

    func testCreateFailsIfDestinationAppearsAfterValidation() throws {
        let fixture = try TempFixture()
        let destination = fixture.root.appendingPathComponent("New.swift")

        let mutation = ValidatedFileMutation(
            oldCanonicalPath: nil,
            newCanonicalPath: destination.path,
            operation: .create,
            destructive: false
        )
        let bindings = try binder.capture(for: [mutation])
        try Data("surprise".utf8).write(to: destination)

        XCTAssertThrowsError(try binder.revalidate(bindings))
    }

    func testRenameBindsSourceAndAbsentDestination() throws {
        let fixture = try TempFixture()
        let source = fixture.root.appendingPathComponent("Old.swift")
        let destination = fixture.root.appendingPathComponent("New.swift")
        try Data("let value = 1\n".utf8).write(to: source)

        let mutation = ValidatedFileMutation(
            oldCanonicalPath: source.path,
            newCanonicalPath: destination.path,
            operation: .rename,
            destructive: true
        )
        let bindings = try binder.capture(for: [mutation])

        XCTAssertEqual(bindings.count, 2)
        XCTAssertTrue(bindings.contains { $0.path == source.path && $0.expectation == .existing })
        XCTAssertTrue(bindings.contains { $0.path == destination.path && $0.expectation == .absent })
    }
}

private final class TempFixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("carina-fs-binding-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }
}
