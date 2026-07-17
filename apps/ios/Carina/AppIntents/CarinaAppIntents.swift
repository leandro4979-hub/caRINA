import AppIntents
import Foundation

enum CarinaIntentCommand: String, AppEnum {
    case systemStatus = "system.status"
    case agentStatus = "agent.status"
    case bridgeStatus = "bridge.status"
    case openClawStatus = "openclaw.status"
    case shortcutPrepare = "shortcut.prepare"
    case shortcutRun = "shortcut.run"

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "CARINA Command")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .systemStatus: "System Status",
        .agentStatus: "Agent Status",
        .bridgeStatus: "Bridge Status",
        .openClawStatus: "OpenClaw Status",
        .shortcutPrepare: "Prepare Shortcut",
        .shortcutRun: "Run Shortcut",
    ]
}

struct OpenCarinaIntent: AppIntent {
    static let title: LocalizedStringResource = "Open CARINA"
    static let description = IntentDescription("Open the CARINA iPhone agent center.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult { .result() }
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
    static let description = IntentDescription("Check the authenticated CARINA bridge on the configured Mac.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let host = UserDefaults.standard.string(forKey: BridgeDefaults.hostKey) ?? ""
        let configuration = try BridgeConfiguration(host: host)
        guard let token = try await SecureCredentialStore.shared.load(account: CredentialManager.bridgeTokenAccount),
              !token.isEmpty else {
            return .result(dialog: "Open CARINA Settings and save the bridge token first.")
        }
        let healthURL = try configuration.httpBaseURL.appending(path: "health")
        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            return .result(dialog: "The CARINA bridge did not return a healthy response.")
        }
        return .result(dialog: "The CARINA bridge is online at \(configuration.host).")
    }
}

struct RunCarinaCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "Run CARINA Command"
    static let description = IntentDescription("Validate and route an allow-listed CARINA command.")
    static let openAppWhenRun = true

    @Parameter(title: "Command")
    var command: CarinaIntentCommand

    @Parameter(title: "Value", description: "Agent name or Shortcut name when required", default: "")
    var value: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let payload: [String: String]
        switch command {
        case .agentStatus:
            payload = ["agent": value]
        case .shortcutPrepare, .shortcutRun:
            payload = ["shortcutName": value]
        default:
            payload = [:]
        }
        let request = CommandRequest(name: command.rawValue, payload: payload)
        switch CommandPermissionEngine().authorize(request) {
        case .allow:
            if command == .shortcutPrepare {
                return .result(dialog: "Prepared \(value). Nothing was executed.")
            }
            return .result(dialog: "\(command.rawValue) is authorized as a read-only command. CARINA is open to show the result.")
        case .requireApproval(let reason):
            try await requestConfirmation()
            return .result(dialog: "Approved once: \(reason) CARINA is open to complete the authenticated request.")
        case .deny(let reason):
            return .result(dialog: "CARINA rejected the command: \(reason)")
        }
    }
}

struct CarinaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenCarinaIntent(),
            phrases: ["Open \(.applicationName)", "Talk to \(.applicationName)", "Ask \(.applicationName)"],
            shortTitle: "Open CARINA",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: CheckCarinaBridgeIntent(),
            phrases: ["Check \(.applicationName) bridge", "Check \(.applicationName) status"],
            shortTitle: "Check Bridge",
            systemImageName: "network"
        )
        AppShortcut(
            intent: RunCarinaCommandIntent(),
            phrases: ["Run a \(.applicationName) command"],
            shortTitle: "Run Command",
            systemImageName: "terminal"
        )
    }
}
