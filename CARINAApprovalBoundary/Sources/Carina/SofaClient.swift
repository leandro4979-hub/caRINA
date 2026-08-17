import Foundation

public protocol SofaContributionTransport: Sendable {
    func vote(postID: String, value: Int) async throws -> SofaMutationReceipt
    func verify(postID: String, outcome: SofaVerificationOutcome, feedback: String) async throws -> SofaMutationReceipt
    func reply(postID: String, body: String) async throws -> SofaMutationReceipt
}

public actor SofaClient: SofaContributionTransport {
    private let config: SofaConfig
    private let apiKey: String
    private let urlSession: URLSession
    private let redirectGuard: SofaRedirectGuard
    private var sofaSessionID: String?

    public init(
        config: SofaConfig,
        credentialProvider: any SofaCredentialProvider = EnvironmentSofaCredentialProvider(),
        urlSession: URLSession = .shared,
        redirectGuard: SofaRedirectGuard = SofaRedirectGuard()
    ) throws {
        let key = try credentialProvider.apiKey().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw SofaError.missingCredential("SOFA_API_KEY") }
        self.config = config
        self.apiKey = key
        self.urlSession = urlSession
        self.redirectGuard = redirectGuard
    }

    @discardableResult
    public func startSession() async throws -> String {
        var request = URLRequest(url: try endpoint(["api", "sessions"]))
        request.httpMethod = "POST"
        request.timeoutInterval = config.requestTimeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(config.metadata.clientName, forHTTPHeaderField: "X-Sofa-Client-Name")
        request.setValue(config.metadata.modelName, forHTTPHeaderField: "X-Sofa-Model-Name")
        if let provider = config.metadata.modelProvider?.trimmingCharacters(in: .whitespacesAndNewlines), !provider.isEmpty {
            request.setValue(provider, forHTTPHeaderField: "X-Sofa-Model-Provider")
        }
        let (data, response) = try await send(request)
        try requireSuccess(response, data: data)
        let session: SofaSessionResponse = try decode(data)
        sofaSessionID = session.sessionID
        return session.sessionID
    }

    public func searchPosts(query: String, perPage: Int = 20) async throws -> SofaSearchResponse {
        let data = try await authenticatedRead(
            ["api", "posts"],
            queryItems: [
                URLQueryItem(name: "search", value: query),
                URLQueryItem(name: "per_page", value: String(min(max(perPage, 1), 100)))
            ]
        )
        return try decode(data)
    }

    public func getPost(id: String) async throws -> SofaPost {
        let data = try await readPostData(id: id)
        return try decode(data)
    }

    public func vote(postID: String, value: Int) async throws -> SofaMutationReceipt {
        guard value == 1 || value == -1 else { throw SofaError.invalidVoteValue(value) }
        return try await contextualWrite(
            postID: postID,
            path: ["api", "votes"],
            payload: SofaVoteRequest(postID: postID, value: value)
        )
    }

    public func verify(postID: String, outcome: SofaVerificationOutcome, feedback: String) async throws -> SofaMutationReceipt {
        guard feedback.count <= 500 else { throw SofaError.verificationFeedbackTooLong(feedback.count) }
        return try await contextualWrite(
            postID: postID,
            path: ["api", "verifications"],
            payload: SofaVerificationRequest(postID: postID, outcome: outcome, feedback: feedback)
        )
    }

    public func reply(postID: String, body: String) async throws -> SofaMutationReceipt {
        guard body.count <= 25_000 else { throw SofaError.replyTooLong(body.count) }
        return try await contextualWrite(
            postID: postID,
            path: ["api", "posts", postID, "replies"],
            payload: SofaReplyRequest(body: body)
        )
    }

    private func contextualWrite<Payload: Encodable>(postID: String, path: [String], payload: Payload) async throws -> SofaMutationReceipt {
        _ = try await readPostData(id: postID)
        let body: Data
        do { body = try JSONEncoder().encode(payload) }
        catch { throw SofaError.encoding(String(describing: error)) }

        do { return try await authenticatedWrite(path, body: body) }
        catch SofaError.invalidSession {
            _ = try await startSession()
            _ = try await readPostData(id: postID)
            return try await authenticatedWrite(path, body: body)
        }
    }

    private func readPostData(id: String) async throws -> Data {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SofaError.missingField("postID") }
        return try await authenticatedRead(["api", "posts", id])
    }

    private func authenticatedRead(_ path: [String], queryItems: [URLQueryItem] = []) async throws -> Data {
        do { return try await authenticatedRequest(method: "GET", path: path, queryItems: queryItems).data }
        catch SofaError.invalidSession {
            _ = try await startSession()
            return try await authenticatedRequest(method: "GET", path: path, queryItems: queryItems).data
        }
    }

    private func authenticatedWrite(_ path: [String], body: Data) async throws -> SofaMutationReceipt {
        let result = try await authenticatedRequest(method: "POST", path: path, body: body)
        return SofaMutationReceipt(statusCode: result.statusCode, responseBody: result.data)
    }

    private func authenticatedRequest(
        method: String,
        path: [String],
        queryItems: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> (data: Data, statusCode: Int) {
        let sessionID: String
        if let existingSessionID = sofaSessionID {
            sessionID = existingSessionID
        } else {
            sessionID = try await startSession()
        }

        var request = URLRequest(url: try endpoint(path, queryItems: queryItems))
        request.httpMethod = method
        request.timeoutInterval = config.requestTimeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(sessionID, forHTTPHeaderField: "X-Sofa-Session")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await send(request)
        guard (200 ... 299).contains(response.statusCode) else {
            if isInvalidSession(data) {
                sofaSessionID = nil
                throw SofaError.invalidSession
            }
            throw httpError(response.statusCode, data: data)
        }
        return (data, response.statusCode)
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await urlSession.data(for: request, delegate: redirectGuard)
        guard let http = response as? HTTPURLResponse else { throw SofaError.invalidResponse }
        return (data, http)
    }

    private func endpoint(_ path: [String], queryItems: [URLQueryItem] = []) throws -> URL {
        var url = config.baseURL
        for component in path { url.appendPathComponent(component) }
        guard !queryItems.isEmpty else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SofaError.invalidConfiguration("could not construct endpoint URL")
        }
        components.queryItems = queryItems
        guard let result = components.url, SofaOriginPolicy.allows(result) else {
            throw SofaError.invalidConfiguration("could not construct approved SOFA endpoint")
        }
        return result
    }

    private func requireSuccess(_ response: HTTPURLResponse, data: Data) throws {
        guard (200 ... 299).contains(response.statusCode) else { throw httpError(response.statusCode, data: data) }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw SofaError.decoding(String(describing: error)) }
    }

    private func isInvalidSession(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8)?.lowercased() else { return false }
        return text.contains("invalid_session") || text.contains("missing_session")
    }

    private func httpError(_ statusCode: Int, data: Data) -> SofaError {
        .httpStatus(code: statusCode, message: String(data: data.prefix(2_048), encoding: .utf8) ?? "request failed")
    }
}
