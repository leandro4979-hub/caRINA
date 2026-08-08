# Swift Networking

> Runnable `URLSession` patterns for async requests, decoding, and retries.
> Last verified: 2026-08-07

## Async GET with JSON decoding

Fetches and decodes a JSON payload using structured concurrency.

```swift
import Foundation

struct Repo: Decodable { let name: String; let stargazersCount: Int }

func fetchRepo(owner: String, repo: String) async throws -> Repo {
    let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)")!
    var request = URLRequest(url: url)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        throw URLError(.badServerResponse)
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(Repo.self, from: data)
}

let repo = try await fetchRepo(owner: "leandro4979-hub", repo: "caRINA")
print(repo.name, repo.stargazersCount)
```

## POST a JSON body

Encodes a value, sends it, and decodes the response in one call.

```swift
import Foundation

struct Payload: Codable { let message: String }
struct Echo: Decodable { let json: Payload }

func postJSON<Body: Encodable, Result: Decodable>(_ url: URL, body: Body) async throws -> Result {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(body)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        throw URLError(.badServerResponse)
    }
    return try JSONDecoder().decode(Result.self, from: data)
}

let echo: Echo = try await postJSON(URL(string: "https://httpbin.org/post")!, body: Payload(message: "Hello"))
print(echo.json.message)
```

## Retry with exponential backoff

Survives transient failure without hammering the server; retry only idempotent requests.

```swift
import Foundation

func withRetry<T>(attempts: Int = 3, initialDelay: Duration = .milliseconds(300), operation: () async throws -> T) async throws -> T {
    var delay = initialDelay
    for attempt in 1...attempts {
        do { return try await operation() }
        catch {
            guard attempt < attempts else { throw error }
            try await Task.sleep(for: delay)
            delay += delay
        }
    }
    fatalError("unreachable")
}

let status: Int = try await withRetry {
    let (_, response) = try await URLSession.shared.data(from: URL(string: "https://example.com")!)
    return (response as! HTTPURLResponse).statusCode
}
print(status)
```

**Notes:** Requires macOS 13 or iOS 16 for `Duration` and `Task.sleep(for:)`.

## Typed HTTP errors

Converts status codes into a diagnosable error rather than a generic failure.

```swift
import Foundation

enum HTTPError: Error, CustomStringConvertible {
    case unauthorized, notFound, rateLimited(retryAfter: Int?), server(status: Int)
    var description: String {
        switch self {
        case .unauthorized: "401 unauthorized"
        case .notFound: "404 not found"
        case .rateLimited(let after): "429 rate limited, retry after \(after ?? -1)s"
        case .server(let status): "server error \(status)"
        }
    }
}

func validate(_ response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    switch http.statusCode {
    case 200..<300: return
    case 401: throw HTTPError.unauthorized
    case 404: throw HTTPError.notFound
    case 429: throw HTTPError.rateLimited(retryAfter: http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init))
    default: throw HTTPError.server(status: http.statusCode)
    }
}

let (_, response) = try await URLSession.shared.data(from: URL(string: "https://example.com")!)
try validate(response)
```

## Configured session with timeouts

Avoids requests that hang indefinitely on a degraded network.

```swift
import Foundation

extension URLSession {
    static let api: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        config.requestCachePolicy = .reloadRevalidatingCacheData
        config.httpAdditionalHeaders = ["User-Agent": "CARINA/1.0"]
        return URLSession(configuration: config)
    }()
}

let url = URL(string: "https://example.com")!
let (_, response) = try await URLSession.api.data(from: url)
print(response.url?.absoluteString ?? "No URL")
```

## URLProtocol request mocking

Intercepts `URLSession` requests and supplies deterministic responses without reaching the network.

```swift
import Foundation

final class MockURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)
    static var requestHandler: Handler?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
```

**Notes:** Reset `MockURLProtocol.requestHandler` in test teardown to avoid leaking state.

## Test session factory

Builds an isolated session that routes all requests through `MockURLProtocol`.

```swift
import Foundation

func makeMockSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

let session = makeMockSession()
print(session.configuration.protocolClasses?.contains { $0 == MockURLProtocol.self } ?? false)
```

## Deterministic JSON response test

Injects a mocked GitHub repository response and verifies decoding without an internet connection.

```swift
import Foundation

struct Repository: Decodable, Equatable { let name: String }

func fetchRepository(from url: URL, session: URLSession) async throws -> Repository {
    let (data, response) = try await session.data(from: url)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        throw URLError(.badServerResponse)
    }
    return try JSONDecoder().decode(Repository.self, from: data)
}

MockURLProtocol.requestHandler = { request in
    guard let url = request.url else { throw URLError(.badURL) }
    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                   headerFields: ["Content-Type": "application/json"])!
    return (response, Data(#"{"name":"CARINA"}"#.utf8))
}

let repository = try await fetchRepository(from: URL(string: "https://api.github.com/repos/leandro4979-hub/caRINA")!, session: makeMockSession())
print(repository.name)
```

## Parse a GitHub Link header

Extracts the URL identified by a relation such as `next` from a GitHub REST API `Link` header.

```swift
import Foundation

func linkURL(rel: String, in header: String?) -> URL? {
    guard let header else { return nil }
    for part in header.split(separator: ",") {
        let fields = part.split(separator: ";", maxSplits: 1)
        guard fields.count == 2 else { continue }
        let urlText = fields[0].trimmingCharacters(in: .whitespaces)
        let relation = fields[1].trimmingCharacters(in: .whitespaces)
        guard relation == "rel=\"\(rel)\"", urlText.first == "<", urlText.last == ">" else { continue }
        return URL(string: String(urlText.dropFirst().dropLast()))
    }
    return nil
}

let header = "<https://api.github.com/resource?page=2>; rel=\"next\""
print(linkURL(rel: "next", in: header)?.absoluteString ?? "no next page")
```

## Fetch every GitHub page

Requests each `rel="next"` URL until none remains, returning one accumulated collection.

```swift
import Foundation

func fetchAllPages<Item: Decodable>(from initialURL: URL, session: URLSession = .shared) async throws -> [Item] {
    var nextURL: URL? = initialURL
    var results: [Item] = []
    while let url = nextURL {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        results += try JSONDecoder().decode([Item].self, from: data)
        nextURL = linkURL(rel: "next", in: http.value(forHTTPHeaderField: "Link"))
    }
    return results
}
```

## Paginated GitHub repositories example

Fetches all public repositories for a GitHub user, requesting 100 results per page.

```swift
import Foundation

struct GitHubRepository: Decodable {
    let name: String
    let htmlURL: URL
    enum CodingKeys: String, CodingKey { case name; case htmlURL = "html_url" }
}

let url = URL(string: "https://api.github.com/users/leandro4979-hub/repos?per_page=100")!
let repositories: [GitHubRepository] = try await fetchAllPages(from: url)
print(repositories.map(\.name).joined(separator: "\n"))
```
