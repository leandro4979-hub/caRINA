import Foundation

public enum OllamaHealth {
    private struct Tag: Decodable { let name: String }
    private struct TagsResponse: Decodable { let models: [Tag] }

    /// Confirms that a loopback Ollama runtime is reachable and contains the requested model.
    public static func verify(modelName: String = OllamaConfig.modelName, baseURL: URL = OllamaConfig.baseURL, timeout: TimeInterval = 2, session: URLSession? = nil) async throws {
        let url = try OllamaOriginPolicy.endpoint("tags", baseURL: baseURL)
        let transport = OllamaTransport(copying: session)
        let request = URLRequest(url: url, timeoutInterval: timeout)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.session.data(for: request)
        } catch {
            if OllamaErrorMapping.isCancellation(error) { throw CancellationError() }
            throw OllamaError.unavailable
        }
        guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else { throw OllamaError.badResponse }
        let tags: TagsResponse
        do { tags = try JSONDecoder().decode(TagsResponse.self, from: data) }
        catch { throw OllamaError.decoding(error) }
        guard tags.models.contains(where: { $0.name == modelName }) else { throw OllamaError.modelMissing(modelName) }
    }
}
