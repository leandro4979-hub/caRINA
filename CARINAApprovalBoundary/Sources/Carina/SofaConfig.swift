import Foundation

public struct SofaClientMetadata: Sendable, Equatable {
    public let clientName: String
    public let modelName: String
    public let modelProvider: String?

    public init(clientName: String, modelName: String, modelProvider: String? = nil) {
        self.clientName = clientName
        self.modelName = modelName
        self.modelProvider = modelProvider
    }
}

public struct SofaConfig: Sendable, Equatable {
    public static let defaultBaseURL = URL(string: "https://agents.stackoverflow.com")!

    public let baseURL: URL
    public let metadata: SofaClientMetadata
    public let requestTimeout: TimeInterval

    public init(
        baseURL: URL = SofaConfig.defaultBaseURL,
        metadata: SofaClientMetadata,
        requestTimeout: TimeInterval = 60
    ) throws {
        guard baseURL.scheme == "https", baseURL.host == "agents.stackoverflow.com" else {
            throw SofaError.invalidConfiguration("baseURL must be https://agents.stackoverflow.com")
        }
        guard !metadata.clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SofaError.invalidConfiguration("clientName must not be empty")
        }
        guard !metadata.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SofaError.invalidConfiguration("modelName must not be empty")
        }
        guard requestTimeout > 0 else {
            throw SofaError.invalidConfiguration("requestTimeout must be greater than zero")
        }

        self.baseURL = baseURL
        self.metadata = metadata
        self.requestTimeout = requestTimeout
    }
}

public protocol SofaCredentialProvider: Sendable {
    func apiKey() throws -> String
}

public struct EnvironmentSofaCredentialProvider: SofaCredentialProvider, Sendable {
    public let variableName: String

    public init(variableName: String = "SOFA_API_KEY") {
        self.variableName = variableName
    }

    public func apiKey() throws -> String {
        guard let value = ProcessInfo.processInfo.environment[variableName]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            throw SofaError.missingCredential(variableName)
        }
        return value
    }
}
