import Carina
import Combine
import Foundation

@MainActor
final class CarinaTerminalViewModel: ObservableObject {
    enum Role: String, Sendable {
        case system
        case user
        case carina
        case error
    }

    struct Line: Identifiable, Sendable {
        let id = UUID()
        let role: Role
        let text: String
        let timestamp = Date()
    }

    @Published var input = ""
    @Published private(set) var lines: [Line] = []
    @Published private(set) var liveResponse = ""
    @Published private(set) var isGenerating = false
    @Published private(set) var statusText = "READY"

    private let client: OllamaClient
    private var generationTask: Task<Void, Never>?

    init(client: OllamaClient = OllamaClient()) {
        self.client = client
        boot()
    }

    func submit() {
        let submitted = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submitted.isEmpty, !isGenerating else { return }

        input = ""

        if submitted.hasPrefix("/") {
            runLocalCommand(submitted)
            return
        }

        lines.append(Line(role: .user, text: submitted))
        liveResponse = ""
        isGenerating = true
        statusText = "THINKING"

        let prompt = """
        You are caRINA 0.4.0, a local-first personal assistant running on the user's Mac.
        Be concise, direct, useful, and transparent about what you can and cannot do.
        This terminal is a conversation surface only. Do not claim that shell commands,
        files, network services, approvals, or device actions were executed unless another
        trusted subsystem explicitly reports that result.

        User: \(submitted)
        caRINA:
        """

        generationTask = Task { [weak self, client] in
            guard let self else { return }

            defer {
                self.isGenerating = false
                self.generationTask = nil
            }

            do {
                for try await chunk in client.generate(prompt: prompt) {
                    try Task.checkCancellation()
                    self.liveResponse += chunk
                }

                try Task.checkCancellation()
                let completed = self.liveResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                if !completed.isEmpty {
                    self.lines.append(Line(role: .carina, text: completed))
                }
                self.liveResponse = ""
                self.statusText = "READY"
            } catch is CancellationError {
                self.liveResponse = ""
                self.statusText = "STOPPED"
                self.lines.append(Line(role: .system, text: "Generation stopped."))
            } catch let error as OllamaError {
                self.liveResponse = ""
                self.statusText = "OFFLINE"
                self.lines.append(Line(role: .error, text: error.errorDescription ?? "Ollama error"))
            } catch {
                self.liveResponse = ""
                self.statusText = "ERROR"
                self.lines.append(Line(role: .error, text: "Unexpected error: \(error.localizedDescription)"))
            }
        }
    }

    func stop() {
        generationTask?.cancel()
    }

    func clear() {
        guard !isGenerating else { return }
        lines.removeAll(keepingCapacity: true)
        boot()
    }

    func showHelp() {
        guard !isGenerating else { return }
        runLocalCommand("/help")
    }

    func showStatus() {
        guard !isGenerating else { return }
        runLocalCommand("/status")
    }

    private func boot() {
        statusText = "READY"
        lines.append(Line(role: .system, text: "caRINA 0.4.0 // LOCAL CONSOLE"))
        lines.append(Line(role: .system, text: "Engine: Ollama @ 127.0.0.1:11434"))
        lines.append(Line(role: .system, text: "Boundary: conversation only • no shell execution"))
        lines.append(Line(role: .system, text: "Type /help for local console commands."))
    }

    private func runLocalCommand(_ rawCommand: String) {
        let command = rawCommand
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch command {
        case "/help":
            lines.append(Line(
                role: .system,
                text: "Commands: /status  /about  /clear  /stop  /help"
            ))
        case "/status":
            lines.append(Line(
                role: .system,
                text: "v0.4.0 • LOCAL • \(statusText) • conversation-only authority"
            ))
        case "/about":
            lines.append(Line(
                role: .system,
                text: "caRINA is awake locally. This surface talks to the existing loopback Ollama client and does not expose a shell, listener, remote fallback, or action executor."
            ))
        case "/clear":
            clear()
        case "/stop":
            stop()
        default:
            lines.append(Line(role: .error, text: "Unknown local command: \(rawCommand)"))
        }
    }
}
