import Foundation
import XCTest
@testable import Carina

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest, URLProtocol) -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handler else { XCTFail("Missing URL handler"); return }
        handler(request, self)
    }
    override func stopLoading() {}
}

final class OllamaClientTests: XCTestCase {
    private let baseURL = URL(string: "http://127.0.0.1:11434")!

    override func setUp() { MockURLProtocol.handler = nil }
    override func tearDown() { MockURLProtocol.handler = nil }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func respond(_ request: URLRequest, _ handlerProtocol: URLProtocol, status: Int = 200, chunks: [String]) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/x-ndjson"])!
        handlerProtocol.client?.urlProtocol(handlerProtocol, didReceive: response, cacheStoragePolicy: .notAllowed)
        for chunk in chunks { handlerProtocol.client?.urlProtocol(handlerProtocol, didLoad: Data(chunk.utf8)) }
        handlerProtocol.client?.urlProtocolDidFinishLoading(handlerProtocol)
    }

    func testHealthCheckSucceedsWhenInstalledModelIsPresent() async throws {
        MockURLProtocol.handler = { [self] request, handlerProtocol in respond(request, handlerProtocol, chunks: [#"{"models":[{"name":"llama3.2:3b"}]}"#]) }
        try await OllamaHealth.verify(baseURL: baseURL, session: session())
    }

    func testHealthCheckReportsMissingModel() async {
        MockURLProtocol.handler = { [self] request, handlerProtocol in respond(request, handlerProtocol, chunks: [#"{"models":[{"name":"other"}]}"#]) }
        do { try await OllamaHealth.verify(baseURL: baseURL, session: session()); XCTFail("Expected modelMissing") }
        catch let OllamaError.modelMissing(name) { XCTAssertEqual(name, "llama3.2:3b") }
        catch { XCTFail("Unexpected error: \(error)") }
    }

    func testHealthCheckMapsConnectionFailureToUnavailable() async {
        MockURLProtocol.handler = { _, handlerProtocol in handlerProtocol.client?.urlProtocol(handlerProtocol, didFailWithError: URLError(.cannotConnectToHost)) }
        do { try await OllamaHealth.verify(baseURL: baseURL, session: session()); XCTFail("Expected unavailable") }
        catch let error as OllamaError { if case .unavailable = error {} else { XCTFail("Unexpected error: \(error)") } }
        catch { XCTFail("Unexpected error: \(error)") }
    }

    func testHealthCheckPreservesCancellation() async {
        MockURLProtocol.handler = { _, handlerProtocol in handlerProtocol.client?.urlProtocol(handlerProtocol, didFailWithError: URLError(.cancelled)) }
        do { try await OllamaHealth.verify(baseURL: baseURL, session: session()); XCTFail("Expected cancellation") }
        catch is CancellationError {}
        catch { XCTFail("Unexpected error: \(error)") }
    }

    func testGenerationYieldsAllResponseFragments() async throws {
        MockURLProtocol.handler = { [self] request, handlerProtocol in
            if request.url?.path == "/api/tags" { respond(request, handlerProtocol, chunks: [#"{"models":[{"name":"llama3.2:3b"}]}"#]) }
            else { respond(request, handlerProtocol, chunks: [#"{"response":"Hel","done":false}"# + "\n", #"{"response":"lo","done":true}"# + "\n"]) }
        }
        let client = OllamaClient(baseURL: baseURL, session: session())
        var fragments: [String] = []
        for try await fragment in client.generate(prompt: "ping") { fragments.append(fragment) }
        XCTAssertEqual(fragments, ["Hel", "lo"])
    }

    func testGenerationDoesNotRequestGenerateAfterFailedHealthCheck() async {
        var paths: [String] = []
        MockURLProtocol.handler = { [self] request, handlerProtocol in paths.append(request.url!.path); respond(request, handlerProtocol, chunks: [#"{"models":[]}"#]) }
        let client = OllamaClient(baseURL: baseURL, session: session())
        do { for try await _ in client.generate(prompt: "ping") {} ; XCTFail("Expected modelMissing") }
        catch OllamaError.modelMissing {}
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(paths, ["/api/tags"])
    }

    func testGenerationFailsForMalformedNDJSON() async {
        MockURLProtocol.handler = { [self] request, handlerProtocol in
            if request.url?.path == "/api/tags" { respond(request, handlerProtocol, chunks: [#"{"models":[{"name":"llama3.2:3b"}]}"#]) }
            else { respond(request, handlerProtocol, chunks: ["not-json\n"]) }
        }
        let client = OllamaClient(baseURL: baseURL, session: session())
        do { for try await _ in client.generate(prompt: "ping") {} ; XCTFail("Expected decoding") }
        catch OllamaError.decoding {}
        catch { XCTFail("Unexpected error: \(error)") }
    }

    func testGenerationPreservesCancellation() async {
        MockURLProtocol.handler = { [self] request, handlerProtocol in
            if request.url?.path == "/api/tags" { respond(request, handlerProtocol, chunks: [#"{"models":[{"name":"llama3.2:3b"}]}"#]) }
            else { handlerProtocol.client?.urlProtocol(handlerProtocol, didFailWithError: URLError(.cancelled)) }
        }
        let client = OllamaClient(baseURL: baseURL, session: session())
        do { for try await _ in client.generate(prompt: "ping") {} ; XCTFail("Expected cancellation") }
        catch is CancellationError {}
        catch { XCTFail("Unexpected error: \(error)") }
    }
}
