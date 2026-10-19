import Foundation

/// Prevents URLSession from following a redirect away from the approved SOFA
/// HTTPS origin. This keeps credentials and mutation payloads inside the
/// reviewed network boundary even when an upstream response is a redirect.
public final class SofaRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    public override init() {
        super.init()
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, SofaOriginPolicy.allows(url) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
