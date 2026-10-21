import Foundation

/// A local, text-only OpenAI-compatible Qwen inference adapter.
/// This is not an execution adapter. CARINA's approval boundary remains authoritative.
public enum QwenOpenAIProviderError: Error, Equatable {
    case responseTooLarge
}

public struct QwenOpenAIProvider: Sendable {
    private static let maximumResponseBytes = 1_048_576
    private let transport: OllamaTransport
    private let modelName: String
    private let baseURL: URL

    public init(modelName: String = "qwen3.5:4b", baseURL: URL = OllamaConfig.baseURL, session: URLSession? = nil) {
        self.modelName = modelName
        self.baseURL = baseURL
        self.transport = OllamaTransport(copying: session)
    }

    public func complete(prompt: String) async throws -> String {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OllamaError.badResponse
        }
        // Reject unsafe origins before reading model state or transmitting the prompt.
        _ = try OllamaOriginPolicy.endpoint("tags", baseURL: baseURL)
        try await OllamaHealth.verify(modelName: modelName, baseURL: baseURL, session: transport.session)
        let endpoint = URL(string: "http://127.0.0.1:11434/v1/chat/completions")!
        var request = URLRequest(url: endpoint, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Request(model: modelName, messages: [.init(role: "user", content: prompt)], stream: false, max_tokens: 800, reasoning_effort: "none"))
        let (bytes, response) = try await transport.session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw OllamaError.badResponse }
        if response.expectedContentLength > Int64(Self.maximumResponseBytes) {
            throw QwenOpenAIProviderError.responseTooLarge
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < Self.maximumResponseBytes else {
                throw QwenOpenAIProviderError.responseTooLarge
            }
            data.append(byte)
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let text = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw OllamaError.badResponse
        }
        return text
    }
}

private struct Request: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    let model: String
    let messages: [Message]
    let stream: Bool
    let max_tokens: Int
    let reasoning_effort: String
}

private struct Response: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }
    let choices: [Choice]
}
