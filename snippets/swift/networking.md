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
