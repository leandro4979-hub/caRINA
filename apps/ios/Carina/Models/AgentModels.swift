import Foundation

enum ProviderRoute: String, Codable, CaseIterable, Identifiable, Sendable {
    case openclaw
    case openai
    case ollama
    case apple

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openclaw: "Automatic"
        case .openai: "OpenAI"
        case .ollama: "Ollama"
        case .apple: "Apple Intelligence"
        }
    }
}

enum CarinaDelegate: String, Codable, CaseIterable, Identifiable, Sendable {
    case maya
    case hermes
    case karina
    case clever

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .maya: "Maya"
        case .hermes: "Hermes"
        case .karina: "Karina"
        case .clever: "Clever AI"
        }
    }

    var legacyRoute: AgentRoute {
        switch self {
        case .maya: .maya
        case .hermes: .hermes
        case .karina: .karina
        case .clever: .clever
        }
    }
}

extension ProviderRoute {
    var legacyRoute: AgentRoute {
        switch self {
        case .openclaw: .openclaw
        case .openai: .openai
        case .ollama: .ollama
        case .apple: .apple
        }
    }
}

/// Compatibility-only representation for the pre-delegation UI and stored selections.
enum AgentRoute: String, Codable, CaseIterable, Identifiable, Sendable {
    case openclaw
    case openai
    case ollama
    case maya
    case hermes
    case karina
    case clever
    case apple

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openclaw: "OpenClaw"
        case .openai: "OpenAI"
        case .ollama: "Ollama"
        case .maya: "Maya"
        case .hermes: "Hermes"
        case .karina: "Karina"
        case .clever: "Clever AI"
        case .apple: "Apple Intelligence"
        }
    }

    var providerRoute: ProviderRoute {
        switch self {
        case .openai: .openai
        case .ollama: .ollama
        case .apple: .apple
        default: .openclaw
        }
    }

    var delegate: CarinaDelegate? {
        switch self {
        case .maya: .maya
        case .hermes: .hermes
        case .karina: .karina
        case .clever: .clever
        default: nil
        }
    }
}

enum AgentMessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

struct AgentMessage: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let role: AgentMessageRole
    let text: String
    let createdAt: Date
    let agent: String?
    let route: AgentRoute?

    init(
        id: UUID = UUID(),
        role: AgentMessageRole,
        text: String,
        createdAt: Date = Date(),
        agent: String? = nil,
        route: AgentRoute? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.agent = agent
        self.route = route
    }
}

enum AgentResponseStatus: String, Codable, Sendable {
    case informational
    case prepared
    case waitingForApproval = "waiting_for_approval"
    case executed
    case failed
}

struct AgentRequest: Codable, Equatable, Sendable {
    let requestId: UUID
    let conversationId: UUID
    let route: ProviderRoute
    let delegate: CarinaDelegate?
    let message: String
    let systemInstruction: String

    init(
        requestID: UUID = UUID(),
        conversationID: UUID,
        route: ProviderRoute,
        delegate: CarinaDelegate? = nil,
        message: String,
        systemInstruction: String
    ) {
        self.requestId = requestID
        self.conversationId = conversationID
        self.route = route
        self.delegate = delegate
        self.message = message
        self.systemInstruction = systemInstruction
    }
}

struct PreparedAction: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let command: String
    let summary: String
    let payload: [String: String]
    let permission: CarinaPermission
    let fingerprint: String
    let createdAt: Date
    let expiresAt: Date
}

struct AgentResponse: Codable, Equatable, Sendable {
    let requestId: UUID
    let conversationId: UUID
    let route: ProviderRoute
    let agent: String
    let delegateAgent: CarinaDelegate?
    let provider: String
    let model: String?
    let text: String
    let status: AgentResponseStatus
    let preparedAction: PreparedAction?

    init(
        requestId: UUID,
        conversationId: UUID,
        route: ProviderRoute,
        agent: String,
        delegateAgent: CarinaDelegate? = nil,
        provider: String,
        model: String?,
        text: String,
        status: AgentResponseStatus,
        preparedAction: PreparedAction?
    ) {
        self.requestId = requestId
        self.conversationId = conversationId
        self.route = route
        self.agent = agent
        self.delegateAgent = delegateAgent
        self.provider = provider
        self.model = model
        self.text = text
        self.status = status
        self.preparedAction = preparedAction
    }
}

enum AgentError: LocalizedError, Equatable {
    case missingBridgeToken
    case invalidResponse
    case responseTooLarge
    case httpStatus(Int, String)
    case timedOut
    case cancelled
    case approval(String)
    case localModelUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingBridgeToken:
            "Add the bridge token in CARINA Settings. The OpenAI key remains on the Mac."
        case .invalidResponse:
            "The agent bridge returned an invalid response."
        case .responseTooLarge:
            "The agent response exceeded CARINA's safety limit."
        case .httpStatus(let status, let message):
            "Bridge error \(status): \(message)"
        case .timedOut:
            "The agent request timed out."
        case .cancelled:
            "The agent request was cancelled."
        case .approval(let message):
            message
        case .localModelUnavailable(let reason):
            "Apple Intelligence is unavailable: \(reason)"
        }
    }
}
