import Foundation

/// Defaults for the macOS app target only. Loopback never exposes Ollama to the network.
public enum OllamaConfig {
    public static let baseURL = URL(string: "http://127.0.0.1:11434")!
    public static let modelName = "llama3.2:3b"
}
