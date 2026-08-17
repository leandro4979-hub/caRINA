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
    private var sofaSessionID: String?

    public init(
        config: SofaConfig,
        credentialProvider: any SofaCredentialProvider = EnvironmentSofaCredentialProvider(),
        urlSession: URLSession = .shared
    ) throws {
        let key = try credentialProvider.apiKey().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw SofaError.missingCredential("SOFA_API_KEY")
        }
        self.config = config
        self.apiKey = key
        self.urlSession = urlSession
    }

    @discardableResult
    public func startSession() async throws -> String {
        var request = URLRequest(url: try endpointURL(["api", "sessions"]))
        request.httpMethod = "POST"
        request.timeoutInterval = config.requestTimeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(config.metadata.clientName, forHTTPHeaderField: "X-Sofa-Client-Name")
        request.setValue(config.metadata.modelName, forHTTPHeaderField: "X-Sofa-Model-Name")
        if let provider = config.metadata.modelProvider?.trimmingCharacters(in: .whitespacesAndNewlines), !provider.isEmpty {
            request.setValue(provider, forHTTPHeaderField: "X-Sofa-Model-Provider")
        }

        let (data, response) = try await urlSession.data(for: request)
        let http = try requireHTTPResponse(response)
        guard (200 ... 299).contains(http.statusCode) else {
            throw makeHTTPError(statusCode: http.statusCode, data: data)
        }

        do {
            let response = try JSONDecoder().decode(SofaSessionResponse.self, from: data)
            sofaSessionID = response.sessionID
            return response.sessionID
        } catch {
            throw SofaError.decoding(String(describing: error))
        }
    }

    public func searchPosts(query: String, perPage: Int = 20) async throws -> SofaSearchResponse {
        let boundedPerPage = min(max(perPage, 1), 100)
        let data = try await authenticatedRead(
            path: ["api", "posts"],
            queryItems: [
                URLQueryItem(name: "search", value: query),
                URLQueryItem(name: "per_page", value: String(boundedPerPage))
            ]
        )
        do {
            return try JSONDecoder().decode(SofaSearchResponse.self, from: data)
        } catch {
            throw SofaError.decoding(String(describing: error))
        }
    }

    public func getPost(id: String) async throws -> SofaPost {
        let data = try await readPostData(id: id)
        do {
            return try JSONDecoder().decode(SofaPost.self, from: data)
        } catch {
            throw SofaError.decoding(String(describing: error))
        }
    }

    public func vote(postID: String, value: Int) async throws -> SofaMutationReceipt {
        guard value == 1 || value == -1 else {
            throw SofaError.invalidVoteValue(value)
        }
        let request = SofaVoteRequest(postID: postID, value: value)
        return try await contextualWrite(
            postID: postID,
            path: ["api", "votes"],
            payload: request
        )
    }

    public func verify(
        postID: String,
        outcome: SofaVerificationOutcome,
        feedback: String
    ) async throws -> SofaMutationReceipt {
        guard feedback.count <= 500 else {
            throw SofaError.verificationFeedbackTooLong(feedback.count)
        }
        let request = SofaVerificationRequest(postID: postID, outcome: outcome, feedback: feedback)
        return try await contextualWrite(
            postID: postID,
            path: ["api", "verifications"],
            payload: request
        )
    }

    public func reply(postID: String, body: String) async throws -> SofaMutationReceipt {
        guard body.count <= 25_000 else {
            throw SofaError.replyTooLong(body.count)
        }
        let request = SofaReplyRequest(body: body)
        return try await contextualWrite(
            postID: postID,
            path: ["api", "posts", postID, "replies"],
            payload: request
        )
    }

    private func contextualWrite<Payload: Encodable>(
        postID: String,
        path: [String],
        payload: Payload
    ) async throws -> SofaMutationReceipt {
        _ = try await readPostData(id: postID)
        let body: Data
        do {
            body = try JSONEncoder().encode(payload)
        } catch {
            throw SofaError.encoding(String(describing: error))
        }

        do {
            return try await authenticatedWrite(path: path, body: body, retryInvalidSession: false)
        } catch SofaError.invalidSession {
            _ = try await startSession()
            _ = try await readPostData(id: postID)
            return try await authenticatedWrite(path: path, body: body, retryInvalidSession: false)
        }
    }

    private func readPostData(id: String) async throws -> Data {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SofaError.missingField("postID")
        }
        return try await authenticatedRead(path: ["api", "posts", id])
    }

    private func authenticatedRead(
        path: [String],
        queryItems: [URLQueryItem] = []
    ) async throws -> Data {
        do {
            return try await authenticatedRequest(
                method: "GET",
                path: path,
                queryItems: queryItems,
                body: nil
            ).data
        } catch SofaError.invalidSession {
            _ = try await startSession()
            return try await authenticatedRequest(
                method: "GET",
                path: path,
                queryItems: queryItems,
                body: nil
            ).data
        }
    }

    private func authenticatedWrite(
        path: [String],
        body: Data,
        retryInvalidSession: Bool
    ) async throws -> SofaMutationReceipt {
        do {
            let result = try await authenticatedRequest(
                method: "POST",
                path: path,
                queryItems: [],
                body: body
            )
            return SofaMutationReceipt(statusCode: result.statusCode, responseBody: result.data)
        } catch SofaError.invalidSession where retryInvalidSession {
            _ = try await startSession()
            let result = try await authenticatedRequest(
                method: "POST",
                path: path,
                queryItems: [],
                body: body
            )
            return SofaMutationReceipt(statusCode: result.statusCode, responseBody: result.data)
        }
    }

    private func authenticatedRequest(
        method: String,
        path: [String],
        queryItems: [URLQueryItem],
        body: Data?
    ) async throws -> (data: Data, statusCode: Int) {
        let activeSessionID: String
        if let sofaSessionID {
            activeSessionID = sofaSessionID
        } else {
            activeSessionID = try await startSession()
        }

        var request = URLRequest(url: try endpointURL(path, queryItems: queryItems))
        request.httpMethod = method
        request.timeoutInterval = config.requestTimeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(activeSessionID, forHTTPHeaderField: "X-Sofa-Session")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await urlSession.data(for: request)
        let http = try requireHTTPResponse(response)
        guard (200 ... 299).contains(http.statusCode) else {
            if isInvalidSession(data: data) {
                sofaSessionID = nil
                throw SofaError.invalidSession
            }
            throw makeHTTPError(statusCode: http.statusCode, data: data)
        }
        return (data, http.statusCode)
    }

    private func endpointURL(
        _ path: [String],
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        var url = config.baseURL
        for component in path {
            url.appendPathComponent(component)
        }
        guard !queryItems.isEmpty else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SofaError.invalidConfiguration("could not construct endpoint URL")
        }
        components.queryItems = queryItems
        guard let result = components.url else {
            throw SofaError.invalidConfiguration("could not construct endpoint query")
        }
        return result
    }

    private func requireHTTPResponse(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw SofaError.invalidResponse
        }
        return http
    }

    private func isInvalidSession(data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8)?.lowercased() else { return false }
        return text.contains("invalid_session") || text.contains("missing_session")
    }

    private func makeHTTPError(statusCode: Int, data: Data) -> SofaError {
        let raw = String(data: data.prefix(2_048), encoding: .utf8) ?? "request failed"
        return .httpStatus(code: statusCode, message: raw)
    }
}
