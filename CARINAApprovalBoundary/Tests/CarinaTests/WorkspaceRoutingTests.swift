import XCTest
@testable import Carina

final class WorkspaceRoutingTests: XCTestCase {
    func testBuiltInCatalogMatchesApprovedWorkspaceArchitecture() throws {
        let snapshot = CarinaWorkspaceCatalog.v1

        let engineering = try XCTUnwrap(snapshot.workspace(id: "engineering"))
        XCTAssertEqual(engineering.sources, ["github", "codex", "local_repos"])
        XCTAssertEqual(engineering.skills, ["review_pr", "diagnose_ci", "dispatch_issue"])
        XCTAssertTrue(engineering.sessionIsolation)

        let apple = try XCTUnwrap(snapshot.workspace(id: "apple"))
        XCTAssertEqual(apple.sources, ["siri", "shortcuts", "xcode"])
        XCTAssertEqual(apple.skills, ["build_shortcut", "deploy_iphone_app"])
        XCTAssertTrue(apple.sessionIsolation)

        let personal = try XCTUnwrap(snapshot.workspace(id: "personal"))
        XCTAssertEqual(personal.sources, ["calendar", "documents"])
        XCTAssertEqual(personal.skills, ["personal_automation"])
        XCTAssertTrue(personal.sessionIsolation)
    }

    func testSameWorkspaceRouteResolvesRegisteredSkillAndSources() throws {
        let router = WorkspaceRouter(snapshot: CarinaWorkspaceCatalog.v1)
        let route = try router.route(WorkspaceRouteRequest(
            originWorkspaceID: "engineering",
            skillID: "diagnose_ci",
            sourceIDs: ["github", "codex"]
        ))

        XCTAssertEqual(route.registrySnapshotID, "carina-workspaces-v1")
        XCTAssertEqual(route.workspaceID, "engineering")
        XCTAssertEqual(route.skillID, "diagnose_ci")
        XCTAssertEqual(route.sourceIDs, ["github", "codex"])
        XCTAssertTrue(route.sessionIsolation)
    }

    func testUnknownWorkspaceFailsClosed() {
        let router = WorkspaceRouter(snapshot: CarinaWorkspaceCatalog.v1)

        XCTAssertThrowsError(try router.route(WorkspaceRouteRequest(
            originWorkspaceID: "unknown",
            skillID: "diagnose_ci"
        ))) { error in
            XCTAssertEqual(error as? WorkspaceRoutingError, .unknownWorkspace("unknown"))
        }
    }

    func testUnknownSkillFailsClosed() {
        let router = WorkspaceRouter(snapshot: CarinaWorkspaceCatalog.v1)

        XCTAssertThrowsError(try router.route(WorkspaceRouteRequest(
            originWorkspaceID: "engineering",
            skillID: "deploy_iphone_app"
        ))) { error in
            XCTAssertEqual(error as? WorkspaceRoutingError, .unknownSkill("deploy_iphone_app"))
        }
    }

    func testSourceOutsideWorkspaceFailsClosed() {
        let router = WorkspaceRouter(snapshot: CarinaWorkspaceCatalog.v1)

        XCTAssertThrowsError(try router.route(WorkspaceRouteRequest(
            originWorkspaceID: "personal",
            skillID: "personal_automation",
            sourceIDs: ["github"]
        ))) { error in
            XCTAssertEqual(error as? WorkspaceRoutingError, .sourceNotAllowed("github"))
        }
    }

    func testCrossWorkspaceRequestRequiresPolicyAndProducesNoRoute() {
        let router = WorkspaceRouter(snapshot: CarinaWorkspaceCatalog.v1)

        XCTAssertThrowsError(try router.route(WorkspaceRouteRequest(
            originWorkspaceID: "engineering",
            targetWorkspaceID: "apple",
            skillID: "deploy_iphone_app",
            sourceIDs: ["xcode"]
        ))) { error in
            XCTAssertEqual(
                error as? WorkspaceRoutingError,
                .crossWorkspaceRequiresPolicy(origin: "engineering", target: "apple")
            )
        }
    }

    func testWorkspaceWithoutSessionIsolationCannotRoute() throws {
        let unsafe = WorkspaceDefinition(
            id: "unsafe",
            name: "Unsafe",
            sources: ["local"],
            skills: ["read"],
            sessionIsolation: false
        )
        let snapshot = try WorkspaceRegistrySnapshot(id: "test", workspaces: [unsafe])
        let router = WorkspaceRouter(snapshot: snapshot)

        XCTAssertThrowsError(try router.route(WorkspaceRouteRequest(
            originWorkspaceID: "unsafe",
            skillID: "read",
            sourceIDs: ["local"]
        ))) { error in
            XCTAssertEqual(error as? WorkspaceRoutingError, .sessionIsolationRequired("unsafe"))
        }
    }

    func testDuplicateWorkspaceIDsAreRejectedInsteadOfOverwritten() {
        let first = WorkspaceDefinition(id: "engineering", name: "One", sources: [], skills: [])
        let second = WorkspaceDefinition(id: "engineering", name: "Two", sources: [], skills: [])

        XCTAssertThrowsError(try WorkspaceRegistrySnapshot(id: "test", workspaces: [first, second])) { error in
            XCTAssertEqual(error as? WorkspaceRoutingError, .duplicateWorkspace("engineering"))
        }
    }
}
