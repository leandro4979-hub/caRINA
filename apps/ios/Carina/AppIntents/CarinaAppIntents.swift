import AppIntents
import Foundation

struct OpenCarinaIntent: AppIntent {
    static let title: LocalizedStringResource = "Open CARINA"
    static let description = IntentDescription("Open the CARINA iPhone command center.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct ConfigureCarinaBridgeIntent: AppIntent {
    static let title: LocalizedStringResource = "Configure CARINA Bridge"
    static let description = IntentDescription("Set the Mac LAN or Tailscale address used by CARINA.")

    @Parameter(title: "Mac Address", description: "A LAN hostname, LAN address, or Tailscale address")
    var host: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let configuration = try BridgeConfiguration(host: host)
        UserDefaults.standard.set(configuration.host, forKey: BridgeDefaults.hostKey)
        return .result(dialog: "CARINA will connect to \(configuration.host) on ports 51001 and 51002.")
    }
}

struct CheckCarinaBridgeIntent: AppIntent {
    static let title: LocalizedStringResource = "Check CARINA Bridge"
    static let description = IntentDescription("Check whether the CARINA bridge is reachable on the configured Mac.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let host = UserDefaults.standard.string(forKey: BridgeDefaults.hostKey) ?? ""
        let configuration = try BridgeConfiguration(host: host)
        let healthURL = try configuration.httpBaseURL.appending(path: "health")
        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 8
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            return .result(dialog: "The CARINA bridge did not return a healthy response.")
        }
        return .result(dialog: "The CARINA bridge is online at \(configuration.host).")
    }
}

struct CarinaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenCarinaIntent(),
            phrases: ["Open \(.applicationName)", "Talk to \(.applicationName)"],
            shortTitle: "Open CARINA",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: CheckCarinaBridgeIntent(),
            phrases: ["Check \(.applicationName) bridge"],
            shortTitle: "Check Bridge",
            systemImageName: "network"
        )
    }
}
