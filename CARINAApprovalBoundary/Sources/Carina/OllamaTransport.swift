import Foundation
import Network

/// The Ollama app has one literal origin. DNS aliases, alternate ports and URL
/// components cannot broaden it, even through an injected client configuration.
enum OllamaOriginPolicy {
    static func endpoint(_ path: String, baseURL: URL) throws -> URL {
        guard let parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              parts.scheme == "http", parts.percentEncodedHost == "127.0.0.1",
              parts.port == 11434, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.percentEncodedPath.isEmpty || parts.percentEncodedPath == "/",
              path == "tags" || path == "generate" else { throw OllamaError.badResponse }
        // Construct from the trusted constant after validating the caller's base.
        return OllamaConfig.baseURL.appendingPathComponent("api").appendingPathComponent(path)
    }
}

/// Even a same-origin redirect is rejected; no redirected prompt is sent.
final class OllamaRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Owns session lifetime; copying configuration never reuses a caller's delegate.
final class OllamaTransport: @unchecked Sendable {
    let session: URLSession

    init(copying source: URLSession? = nil) {
        session = Self.makeSession(copying: source)
    }

    static func makeSession(copying source: URLSession? = nil) -> URLSession {
        let configuration = source?.configuration ?? .ephemeral
        // An empty dictionary overrides system HTTP/SOCKS/PAC proxy settings.
        configuration.connectionProxyDictionary = [:]
        if #available(macOS 14.0, *) { configuration.proxyConfigurations = [] }
        return URLSession(configuration: configuration, delegate: OllamaRedirectGuard(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }
}
