import Foundation

/// Errors surfaced by the macOS-only connection to a local Ollama runtime.
public enum OllamaError: Error, LocalizedError {
    case unavailable
    case modelMissing(String)
    case badResponse
    case decoding(Error)
    case transport(Error)

    public var errorDescription: String? {
        switch self {
        case .unavailable: return "Ollama is not running on this Mac."
        case let .modelMissing(name): return "The local Ollama model \"\(name)\" is not installed."
        case .badResponse: return "Ollama returned an unexpected response."
        case let .decoding(error): return "Ollama returned unreadable data: \(error.localizedDescription)"
        case let .transport(error): return "The local Ollama request failed: \(error.localizedDescription)"
        }
    }
}

/// Shared cancellation classification. Each layer maps non-cancellation errors
/// to its own domain error (`unavailable` for health, `transport` for generation).
enum OllamaErrorMapping {
    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
