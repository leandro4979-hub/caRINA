import XCTest
@testable import Carina

final class BridgeConfigurationTests: XCTestCase {
    func testBuildsExpectedBridgeURLs() throws {
        let configuration = try BridgeConfiguration(host: "100.64.10.20")

        XCTAssertEqual(try configuration.httpBaseURL.absoluteString, "http://100.64.10.20:51001")
        XCTAssertEqual(try configuration.webSocketURL.absoluteString, "ws://100.64.10.20:51002/ws")
    }

    func testExtractsHostFromFullURL() throws {
        let configuration = try BridgeConfiguration(host: "http://carina-mac.local:51001/health")

        XCTAssertEqual(configuration.host, "carina-mac.local")
    }

    func testRejectsIPhoneLoopbackAddresses() {
        XCTAssertThrowsError(try BridgeConfiguration(host: "127.0.0.1"))
        XCTAssertThrowsError(try BridgeConfiguration(host: "localhost"))
        XCTAssertThrowsError(try BridgeConfiguration(host: "::1"))
    }

    func testRejectsMissingHost() {
        XCTAssertThrowsError(try BridgeConfiguration(host: "  "))
    }
}
