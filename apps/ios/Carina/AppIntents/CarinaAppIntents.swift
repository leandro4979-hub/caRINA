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
        let host = UserDefaults.standard.string(forKey: BridgeDefaults.hostKey) ?? BridgeDefaults.defaultHost
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
            let runtime = try await IntentBridgeRuntime.load()
            let response = try await runtime.send(command: serializedCommand())
            return .result(dialog: "\(response.text)")
        case .requireApproval:
            try await requestConfirmation()
            let runtime = try await IntentBridgeRuntime.load()
            let prepared = try await runtime.send(command: serializedCommand())
            guard let action = prepared.preparedAction else {
                throw AgentError.approval("The bridge did not return an approval-bound action.")
            }
            guard case .requireApproval = CommandPermissionEngine().validate(action) else {
                throw AgentError.approval("The bridge returned an invalid execute action.")
            }
            let response = try await runtime.provider.execute(action, conversationID: runtime.conversationID)
            return .result(dialog: "\(response.text)")
        case .deny(let reason):
            return .result(dialog: "CARINA rejected the command: \(reason)")
        }
    }

    private func serializedCommand() -> String {
        let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanValue.isEmpty ? command.rawValue : "\(command.rawValue) \(cleanValue)"
    }
}

private struct IntentBridgeRuntime {
    let provider: BridgeAgentProvider
    let conversationID: UUID

    static func load() async throws -> Self {
        let host = UserDefaults.standard.string(forKey: BridgeDefaults.hostKey) ?? BridgeDefaults.defaultHost
        let configuration = try BridgeConfiguration(host: host)
        guard let token = try await SecureCredentialStore.shared.load(account: CredentialManager.bridgeTokenAccount),
              !token.isEmpty else {
            throw AgentError.missingBridgeToken
        }
        return Self(
            provider: BridgeAgentProvider(configuration: configuration, bearerToken: token),
            conversationID: UUID()
        )
    }

    func send(command: String) async throws -> AgentResponse {
        try await provider.send(
            AgentRequest(
                conversationID: conversationID,
                route: .openclaw,
                message: command,
                systemInstruction: "Execute only registered CARINA commands and preserve permission boundaries."
            )
        )
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
