import Foundation

public struct OllamaGenerateRequest: Encodable, Sendable {
    public let model: String
    public let prompt: String
    public let stream: Bool
    public init(model: String, prompt: String, stream: Bool = true) { self.model = model; self.prompt = prompt; self.stream = stream }
}

public struct OllamaGenerateChunk: Decodable, Sendable {
    public let response: String
    public let done: Bool
}

/// A local-only, macOS-side NDJSON client. Do not add this type to an iPhone extension target.
public struct OllamaClient: Sendable {
    private let baseURL: URL
    private let modelName: String
    private let session: URLSession
    private let healthTimeout: TimeInterval

    public init(baseURL: URL = OllamaConfig.baseURL, modelName: String = OllamaConfig.modelName, session: URLSession = .shared, healthTimeout: TimeInterval = 2) {
        self.baseURL = baseURL
        self.modelName = modelName
        self.session = session
        self.healthTimeout = healthTimeout
    }

    /// Streams response fragments in received order after confirming the local model is present.
    public func generate(prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await OllamaHealth.verify(modelName: modelName, baseURL: baseURL, timeout: healthTimeout, session: session)
                    let url = baseURL.appendingPathComponent("api").appendingPathComponent("generate")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 60
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONEncoder().encode(OllamaGenerateRequest(model: modelName, prompt: prompt))
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else { throw OllamaError.badResponse }
                    let decoder = JSONDecoder()
                    var sawDone = false
                    for try await line in bytes.lines where !line.isEmpty {
                        guard let data = line.data(using: .utf8) else { throw OllamaError.badResponse }
                        let chunk: OllamaGenerateChunk
                        do { chunk = try decoder.decode(OllamaGenerateChunk.self, from: data) }
                        catch { throw OllamaError.decoding(error) }
                        if !chunk.response.isEmpty { continuation.yield(chunk.response) }
                        if chunk.done { sawDone = true; break }
                    }
                    guard sawDone else { throw OllamaError.badResponse }
                    continuation.finish()
                } catch let error as OllamaError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: OllamaErrorMapping.isCancellation(error) ? CancellationError() : OllamaError.transport(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
