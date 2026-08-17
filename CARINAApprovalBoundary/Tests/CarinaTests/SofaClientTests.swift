import Foundation
import XCTest
@testable import Carina

final class SofaClientTests: XCTestCase {
    override func tearDown() {
        SofaMockURLProtocol.handler = nil
        super.tearDown()
    }

    func testConfigurationRejectsNonSofaOrigins() {
        XCTAssertThrowsError(
            try SofaConfig(
                baseURL: URL(string: "https://example.com")!,
                metadata: SofaClientMetadata(clientName: "carina-tests", modelName: "test-model")
            )
        ) { error in
            guard case SofaError.invalidConfiguration = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testInvalidVoteFailsBeforeNetworkAccess() async throws {
        let scenario = SofaHTTPScenario()
        SofaMockURLProtocol.handler = scenario.handle
        let client = try makeClient()

        do {
            _ = try await client.vote(postID: "post-1", value: 0)
            XCTFail("Expected invalid vote rejection")
        } catch let error as SofaError {
            XCTAssertEqual(error, .invalidVoteValue(0))
        }

        XCTAssertEqual(scenario.snapshot().count, 0)
    }

    func testInvalidSessionDuringVoteCreatesFreshSessionAndRereadsTarget() async throws {
        let scenario = SofaHTTPScenario { step, request in
            switch step {
            case 0:
                return .json(status: 201, body: #"{"session_id":"session-1"}"#)
            case 1:
                return .json(status: 200, body: #"{"id":"post-1","title":"Known post"}"#)
            case 2:
                return .json(
                    status: 401,
                    body: #"{"detail":{"error":"invalid_session","message":"Session is invalid or has expired"}}"#
                )
            case 3:
                return .json(status: 201, body: #"{"session_id":"session-2"}"#)
            case 4:
                return .json(status: 200, body: #"{"id":"post-1","title":"Known post"}"#)
            case 5:
                return .json(status: 200, body: #"{"vote_id":"vote-1"}"#)
            default:
                return .json(status: 500, body: #"{"error":"unexpected request"}"#)
            }
        }
        SofaMockURLProtocol.handler = scenario.handle
        let client = try makeClient()

        let receipt = try await client.vote(postID: "post-1", value: 1)
        XCTAssertEqual(receipt.statusCode, 200)

        let requests = scenario.snapshot()
        XCTAssertEqual(
            requests.map { "\($0.method) \($0.path)" },
            [
                "POST /api/sessions",
                "GET /api/posts/post-1",
                "POST /api/votes",
                "POST /api/sessions",
                "GET /api/posts/post-1",
                "POST /api/votes"
            ]
        )

        XCTAssertEqual(requests[0].authorization, "Bearer test-sofa-key")
        XCTAssertEqual(requests[0].clientName, "carina-tests")
        XCTAssertEqual(requests[0].modelName, "test-model")
        XCTAssertNil(requests[0].sofaSession)

        XCTAssertEqual(requests[1].sofaSession, "session-1")
        XCTAssertEqual(requests[2].sofaSession, "session-1")
        XCTAssertEqual(requests[4].sofaSession, "session-2")
        XCTAssertEqual(requests[5].sofaSession, "session-2")

        let firstVoteBody = try XCTUnwrap(requests[2].body)
        let retriedVoteBody = try XCTUnwrap(requests[5].body)
        XCTAssertEqual(firstVoteBody, retriedVoteBody)
        XCTAssertTrue(firstVoteBody.contains(#""post_id":"post-1""#))
        XCTAssertTrue(firstVoteBody.contains(#""value":1"#))
    }

    private func makeClient() throws -> SofaClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SofaMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let config = try SofaConfig(
            metadata: SofaClientMetadata(
                clientName: "carina-tests",
                modelName: "test-model",
                modelProvider: "test-provider"
            )
        )
        return try SofaClient(
            config: config,
            credentialProvider: StaticSofaCredentialProvider(value: "test-sofa-key"),
            urlSession: session
        )
    }
}

private struct StaticSofaCredentialProvider: SofaCredentialProvider {
    let value: String
    func apiKey() throws -> String { value }
}

private final class SofaMockURLProtocol: URLProtocol {
    static var handler: ((URLRequest, URLProtocol) -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: SofaError.invalidResponse)
            return
        }
        handler(request, self)
    }

    override func stopLoading() {}
}

private final class SofaHTTPScenario: @unchecked Sendable {
    struct RequestSnapshot: Equatable {
        let method: String
        let path: String
        let authorization: String?
        let sofaSession: String?
        let clientName: String?
        let modelName: String?
        let body: String?
    }

    struct Response {
        let status: Int
        let body: Data
        let headers: [String: String]

        static func json(status: Int, body: String) -> Response {
            Response(
                status: status,
                body: Data(body.utf8),
                headers: ["Content-Type": "application/json"]
            )
        }
    }

    typealias Responder = (Int, URLRequest) -> Response

    private let lock = NSLock()
    private var requests: [RequestSnapshot] = []
    private let responder: Responder

    init(responder: @escaping Responder = { _, _ in .json(status: 500, body: #"{"error":"unexpected network access"}"#) }) {
        self.responder = responder
    }

    func handle(_ request: URLRequest, _ protocolInstance: URLProtocol) {
        let step: Int
        lock.lock()
        step = requests.count
        requests.append(
            RequestSnapshot(
                method: request.httpMethod ?? "",
                path: request.url?.path ?? "",
                authorization: request.value(forHTTPHeaderField: "Authorization"),
                sofaSession: request.value(forHTTPHeaderField: "X-Sofa-Session"),
                clientName: request.value(forHTTPHeaderField: "X-Sofa-Client-Name"),
                modelName: request.value(forHTTPHeaderField: "X-Sofa-Model-Name"),
                body: request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
            )
        )
        lock.unlock()

        let response = responder(step, request)
        guard let url = request.url,
              let http = HTTPURLResponse(
                url: url,
                statusCode: response.status,
                httpVersion: nil,
                headerFields: response.headers
              ) else {
            protocolInstance.client?.urlProtocol(protocolInstance, didFailWithError: SofaError.invalidResponse)
            return
        }
        protocolInstance.client?.urlProtocol(protocolInstance, didReceive: http, cacheStoragePolicy: .notAllowed)
        protocolInstance.client?.urlProtocol(protocolInstance, didLoad: response.body)
        protocolInstance.client?.urlProtocolDidFinishLoading(protocolInstance)
    }

    func snapshot() -> [RequestSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }
}
