import Foundation
import XCTest
@testable import Carina

private final class QwenMockProtocol: URLProtocol {
    static var handler: ((URLRequest, URLProtocol) -> Void)?
    static var onStop: ((URLRequest) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handler?(request, self) }
    override func stopLoading() { Self.onStop?(request) }
}

final class QwenOpenAIProviderTests: XCTestCase {
    override func tearDown() { QwenMockProtocol.handler = nil; QwenMockProtocol.onStop = nil; super.tearDown() }
    private func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [QwenMockProtocol.self]
        return URLSession(configuration: c)
    }
    private func respond(_ req: URLRequest, _ proto: URLProtocol, _ text: String) {
        let reply = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        proto.client?.urlProtocol(proto, didReceive: reply, cacheStoragePolicy: .notAllowed)
        proto.client?.urlProtocol(proto, didLoad: Data(text.utf8))
        proto.client?.urlProtocolDidFinishLoading(proto)
    }

    func testProviderReturnsOnlyTextAndDisablesReasoning() async throws {
        var paths = [String]()
        QwenMockProtocol.handler = { [self] req, proto in
            paths.append(req.url!.path)
            if req.url!.path == "/api/tags" {
                respond(req, proto, #"{"models":[{"name":"qwen3.5:4b"}]}"#)
            } else {
                XCTAssertEqual(req.url!.host, "127.0.0.1")
                XCTAssertEqual(req.url!.port, 11434)
                let data: Data
                if let body = req.httpBody { data = body }
                else if let stream = req.httpBodyStream {
                    stream.open()
                    defer { stream.close() }
                    var output = Data()
                    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
                    defer { buffer.deallocate() }
                    while stream.hasBytesAvailable {
                        let n = stream.read(buffer, maxLength: 4096)
                        if n <= 0 { break }
                        output.append(buffer, count: n)
                    }
                    data = output
                } else { data = Data() }
                let json = try! XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                XCTAssertEqual(json["reasoning_effort"] as? String, "none")
                XCTAssertEqual(json["model"] as? String, "qwen3.5:4b")
                XCTAssertEqual(json["stream"] as? Bool, false)
                XCTAssertNil(json["tools"], "Model adapter must never offer tools")
                respond(req, proto, #"{"choices":[{"message":{"content":"LISTO"}}]}"#)
            }
        }
        let answer = try await QwenOpenAIProvider(session: session()).complete(prompt: "Say LISTO")
        XCTAssertEqual(answer, "LISTO")
        XCTAssertEqual(paths, ["/api/tags", "/v1/chat/completions"])
    }

    private func checkResponseSize(payloadSize: Int, shouldPass: Bool) async throws {
        QwenMockProtocol.handler = { [self] req, proto in
            if req.url!.path == "/api/tags" {
                respond(req, proto, #"{"models":[{"name":"qwen3.5:4b"}]}"#)
                return
            }
            // JSON response with exact byte size, sent as small chunks and no Content-Length.
            let prefix = #"{"choices":[{"message":{"content":""#
            let suffix = #""}}]}"#
            let count = payloadSize - prefix.utf8.count - suffix.utf8.count
            XCTAssertGreaterThanOrEqual(count, 0)
            let reply = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil,
                                        headerFields: ["Content-Type": "application/json"])!
            proto.client?.urlProtocol(proto, didReceive: reply, cacheStoragePolicy: .notAllowed)
            proto.client?.urlProtocol(proto, didLoad: Data(prefix.utf8))
            let chunk = Data(repeating: 65, count: 8192)
            for _ in 0..<(count / chunk.count) {
                proto.client?.urlProtocol(proto, didLoad: chunk)
            }
            let remainder = count % chunk.count
            if remainder > 0 { proto.client?.urlProtocol(proto, didLoad: Data(repeating: 65, count: remainder)) }
            proto.client?.urlProtocol(proto, didLoad: Data(suffix.utf8))
            proto.client?.urlProtocolDidFinishLoading(proto)
        }
        if shouldPass {
            let answer = try await QwenOpenAIProvider(session: session()).complete(prompt: "bounded")
            let overhead = #"{"choices":[{"message":{"content":""# .utf8.count + #""}}]}"#.utf8.count
            XCTAssertEqual(answer.utf8.count, payloadSize - overhead)
        } else {
            do {
                _ = try await QwenOpenAIProvider(session: session()).complete(prompt: "bounded")
                XCTFail("An over-limit response must fail closed")
            } catch QwenOpenAIProviderError.responseTooLarge { }
        }
    }

    func testExactlyOneMiBResponseSucceeds() async throws {
        try await checkResponseSize(payloadSize: 1_048_576, shouldPass: true)
    }

    func testOneMiBPlusOneByteResponseFailsClosed() async throws {
        try await checkResponseSize(payloadSize: 1_048_577, shouldPass: false)
    }

    func testOversizedResponseCancelsTransport() async throws {
        let stopped = expectation(description: "Oversized response cancels URLProtocol transport")
        QwenMockProtocol.onStop = { request in
            if request.url?.path == "/v1/chat/completions" { stopped.fulfill() }
        }
        QwenMockProtocol.handler = { [self] req, proto in
            if req.url?.path == "/api/tags" {
                respond(req, proto, #"{"models":[{"name":"qwen3.5:4b"}]}"#)
                return
            }
            let response = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            proto.client?.urlProtocol(proto, didReceive: response, cacheStoragePolicy: .notAllowed)
            proto.client?.urlProtocol(proto, didLoad: Data(repeating: 65, count: 1_048_577))
            // Deliberately leave the transfer open; cancellation must stop it.
        }
        do {
            _ = try await QwenOpenAIProvider(session: session()).complete(prompt: "bounded")
            XCTFail("Expected responseTooLarge")
        } catch QwenOpenAIProviderError.responseTooLarge { }
        await fulfillment(of: [stopped], timeout: 3)
    }

    func testLiveLocalQwenWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["QWEN_LIVE_TEST"] == "1" else {
            throw XCTSkip("Live Ollama test is explicitly opt-in")
        }
        let response = try await QwenOpenAIProvider().complete(prompt: "Respond with LISTO only.")
        XCTAssertTrue(response.uppercased().contains("LISTO"), "Local Qwen must return visible text")
    }

    func testUnsafeOriginNeverSendsPrompt() async {
        var count = 0
        QwenMockProtocol.handler = { _, _ in count += 1 }
        do {
            _ = try await QwenOpenAIProvider(baseURL: URL(string: "http://192.168.1.1:11434")!, session: session()).complete(prompt: "secret-test-canary")
            XCTFail("Expected fail-closed origin")
        } catch { XCTAssertEqual(count, 0) }
    }

    func testMissingModelPreventsGeneration() async {
        var paths = [String]()
        QwenMockProtocol.handler = { [self] req, proto in
            paths.append(req.url!.path)
            respond(req, proto, #"{"models":[]}"#)
        }
        do {
            _ = try await QwenOpenAIProvider(session: session()).complete(prompt: "Hello")
            XCTFail("Expected missing model")
        } catch OllamaError.modelMissing { XCTAssertEqual(paths, ["/api/tags"]) }
        catch { XCTFail("Wrong error: \(error)") }
    }
}
