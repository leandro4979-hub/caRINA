# Swift networking

Each example runs with `swift filename.swift` on macOS with Swift 5.7 or later.

## Fetch text

```swift
import Foundation

let url = URL(string: "https://example.com")!
let (data, _) = try await URLSession.shared.data(from: url)
print(String(decoding: data, as: UTF8.self))
```

Fetches a URL and prints its response body.

## Check an HTTP status

```swift
import Foundation

let url = URL(string: "https://example.com")!
let (_, response) = try await URLSession.shared.data(from: url)
guard let http = response as? HTTPURLResponse else { fatalError("Not HTTP") }
print(http.statusCode)
```

Fetches a URL and prints its HTTP status code.

## Decode JSON

```swift
import Foundation

struct Todo: Decodable { let id: Int; let title: String }
let url = URL(string: "https://jsonplaceholder.typicode.com/todos/1")!
let (data, _) = try await URLSession.shared.data(from: url)
let todo = try JSONDecoder().decode(Todo.self, from: data)
print(todo.id, todo.title)
```

Downloads and decodes a JSON object into a Swift type.

## Send JSON

```swift
import Foundation

let url = URL(string: "https://httpbin.org/post")!
var request = URLRequest(url: url)
request.httpMethod = "POST"
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.httpBody = try JSONSerialization.data(withJSONObject: ["message": "Hello"])
let (data, _) = try await URLSession.shared.data(for: request)
print(String(decoding: data, as: UTF8.self))
```

Sends a JSON request body and prints the echoed response.

## Add a timeout

```swift
import Foundation

let configuration = URLSessionConfiguration.ephemeral
configuration.timeoutIntervalForRequest = 10
let session = URLSession(configuration: configuration)
let url = URL(string: "https://example.com")!
let (_, response) = try await session.data(from: url)
print(response.url?.absoluteString ?? "No URL")
```

Uses an ephemeral session with a ten-second request timeout.
