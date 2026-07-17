import Foundation
import os

protocol AgentProvider: Sendable {
    func send(_ request: AgentRequest) async throws -> AgentResponse
    func execute(_ action: PreparedAction, conversationID: UUID) async throws -> AgentResponse
}

struct BridgeAgentProvider: AgentProvider {
    private static let maximumResponseBytes = 1_048_576

    let configuration: BridgeConfiguration
    let bearerToken: String
    let session: URLSession

    init(
        configuration: BridgeConfiguration,
        bearerToken: String,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.bearerToken = bearerToken
        self.session = session
    }

    func send(_ request: AgentRequest) async throws -> AgentResponse {
        try await post(path: "v1/agent/message", body: request)
    }

    func execute(_ action: PreparedAction, conversationID: UUID) async throws -> AgentResponse {
        let request = ActionExecutionRequest(action: action, conversationID: conversationID)
        return try await post(path: "v1/actions/execute", body: request)
    }

    private func post<Body: Encodable>(path: String, body: Body) async throws -> AgentResponse {
        guard bearerToken.count >= 32 else { throw AgentError.missingBridgeToken }
        let url = try configuration.httpBaseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(body)

        do {
            let (data, response) = try await session.data(for: request)
            guard data.count <= Self.maximumResponseBytes else { throw AgentError.responseTooLarge }
            guard let httpResponse = response as? HTTPURLResponse else { throw AgentError.invalidResponse }
            guard (200..<300).contains(httpResponse.statusCode) else {
                let detail = (try? JSONDecoder().decode(BridgeErrorBody.self, from: data).error)
                    ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                throw AgentError.httpStatus(httpResponse.statusCode, detail)
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(AgentResponse.self, from: data)
        } catch is CancellationError {
            throw AgentError.cancelled
        } catch let error as URLError where error.code == .timedOut {
            throw AgentError.timedOut
        } catch let error as AgentError {
            throw error
        } catch {
            throw AgentError.httpStatus(0, error.localizedDescription)
        }
    }
}

struct MockAgentProvider: AgentProvider {
    let response: AgentResponse

    func send(_ request: AgentRequest) async throws -> AgentResponse { response }
    func execute(_ action: PreparedAction, conversationID: UUID) async throws -> AgentResponse { response }
}

private struct ActionExecutionRequest: Encodable {
    let action: PreparedAction
    let conversationID: UUID
}

private struct BridgeErrorBody: Decodable {
    let error: String
}

@MainActor
final class CarinaAgentService: ObservableObject {
    enum State: Equatable {
        case idle
        case sending
        case waitingForApproval
        case failed(String)

        var label: String {
            switch self {
            case .idle: "Ready"
            case .sending: "Thinking"
            case .waitingForApproval: "Waiting for approval"
            case .failed(let message): message
            }
        }
    }

    @Published private(set) var messages: [AgentMessage] = []
    @Published private(set) var state: State = .idle
    @Published private(set) var pendingApproval: PreparedAction?
    @Published var route: AgentRoute = .openclaw

    let conversationID = UUID()
    private let permissionEngine = CommandPermissionEngine()
    private let approvalStore = ApprovalStore()
    private var activeTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.leandrofajardo.carina", category: "AgentService")

    deinit { activeTask?.cancel() }

    func send(message: String, configuration: BridgeConfiguration, bearerToken: String) {
        let clean = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        cancel()
        messages.append(AgentMessage(role: .user, text: clean))
        state = .sending
        let request = AgentRequest(
            conversationID: conversationID,
            route: route,
            message: clean,
            systemInstruction: "You are CARINA, Leandro's truthful iPhone agent interface. Route through OpenClaw when available. Never claim an action executed unless the trusted bridge confirms it."
        )
        let provider = BridgeAgentProvider(configuration: configuration, bearerToken: bearerToken)
        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await provider.send(request)
                await self.accept(response)
            } catch {
                self.logger.error("Agent request failed: \(error.localizedDescription, privacy: .public)")
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        if state == .sending { state = .idle }
    }

    func approve(configuration: BridgeConfiguration, bearerToken: String) {
        guard let action = pendingApproval else { return }
        let provider = BridgeAgentProvider(configuration: configuration, bearerToken: bearerToken)
        state = .sending
        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.approvalStore.consume(action)
                self.pendingApproval = nil
                let response = try await provider.execute(action, conversationID: self.conversationID)
                await self.accept(response)
            } catch {
                self.logger.error("Approved action failed: \(error.localizedDescription, privacy: .public)")
                self.pendingApproval = nil
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    func deny() {
        guard let action = pendingApproval else { return }
        Task { await approvalStore.deny(action) }
        pendingApproval = nil
        state = .idle
        messages.append(AgentMessage(role: .system, text: "Action denied. Nothing was executed."))
    }

    private func accept(_ response: AgentResponse) async {
        messages.append(
            AgentMessage(
                role: .assistant,
                text: response.text,
                agent: response.agent,
                route: response.route
            )
        )
        guard let action = response.preparedAction else {
            state = response.status == .failed ? .failed(response.text) : .idle
            return
        }
        switch permissionEngine.validate(action) {
        case .requireApproval:
            do {
                try await approvalStore.register(action)
                pendingApproval = action
                state = .waitingForApproval
            } catch {
                state = .failed(error.localizedDescription)
            }
        case .allow:
            state = .failed("The bridge incorrectly marked a non-execute command as approval-gated.")
        case .deny(let reason):
            state = .failed(reason)
        }
    }
}
