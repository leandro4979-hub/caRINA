import Foundation

enum BridgeConfigurationError: LocalizedError, Equatable {
    case missingHost
    case loopbackHost
    case invalidHost

    var errorDescription: String? {
        switch self {
        case .missingHost:
            return "Enter the Mac LAN name, LAN address, or Tailscale address."
        case .loopbackHost:
            return "127.0.0.1 and localhost point back to the iPhone. Use the Mac address instead."
        case .invalidHost:
            return "The bridge address is not valid."
        }
    }
}

struct BridgeConfiguration: Codable, Equatable, Sendable {
    static let httpPort = 51_001
    static let webSocketPort = 51_002

    let host: String

    init(host: String) throws {
        let normalized = Self.normalize(host)
        guard !normalized.isEmpty else {
            throw BridgeConfigurationError.missingHost
        }

        let lowercaseHost = normalized.lowercased()
        guard lowercaseHost != "localhost",
              lowercaseHost != "::1",
              !lowercaseHost.hasPrefix("127.") else {
            throw BridgeConfigurationError.loopbackHost
        }

        guard normalized.range(of: #"^[A-Za-z0-9][A-Za-z0-9.:-]*$"#, options: .regularExpression) != nil else {
            throw BridgeConfigurationError.invalidHost
        }

        self.host = normalized
    }

    var httpBaseURL: URL {
        get throws {
            try makeURL(scheme: "http", port: Self.httpPort)
        }
    }

    var webSocketURL: URL {
        get throws {
            try makeURL(scheme: "ws", port: Self.webSocketPort, path: "/ws")
        }
    }

    private func makeURL(scheme: String, port: Int, path: String = "") throws -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        components.path = path
        guard let url = components.url else {
            throw BridgeConfigurationError.invalidHost
        }
        return url
    }

    private static func normalize(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if let components = URLComponents(string: trimmed),
           components.scheme != nil,
           let parsedHost = components.host {
            return parsedHost
        }

        return trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/", maxSplits: 1)
            .first
            .map(String.init) ?? ""
    }
}

enum BridgeDefaults {
    static let hostKey = "carina.bridge.host"
    static let defaultHost = "leandros-MacBook-Air.local"
}

@MainActor
final class BridgeSettings: ObservableObject {
    @Published var host: String
    @Published private(set) var validationMessage: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        host = defaults.string(forKey: BridgeDefaults.hostKey) ?? BridgeDefaults.defaultHost
    }

    func configuration() throws -> BridgeConfiguration {
        try BridgeConfiguration(host: host)
    }

    @discardableResult
    func save() -> Bool {
        do {
            let configuration = try configuration()
            host = configuration.host
            defaults.set(configuration.host, forKey: BridgeDefaults.hostKey)
            validationMessage = nil
            return true
        } catch {
            validationMessage = error.localizedDescription
            return false
        }
    }
}
