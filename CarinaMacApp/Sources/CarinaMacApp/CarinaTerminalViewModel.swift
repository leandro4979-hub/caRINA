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
    @Published private(set) var activeSkill: CarinaSkill?

    private let client: OllamaClient
    private var generationTask: Task<Void, Never>?
    private let maxContextLines = 12
    private let maxContextCharacters = 8_000

    var activeSkillLabel: String {
        activeSkill?.displayName ?? "GENERAL"
    }

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

        let priorContext = Array(lines.suffix(maxContextLines))
        lines.append(Line(role: .user, text: submitted))
        liveResponse = ""
        isGenerating = true
        statusText = "THINKING"

        let prompt = buildPrompt(userText: submitted, priorLines: priorContext)

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

    func showSkills() {
        guard !isGenerating else { return }
        runLocalCommand("/skills")
    }

    func startSecurityAudit() {
        guard !isGenerating else { return }
        runLocalCommand("/audit")
    }

    func activateCodingStandards() {
        guard !isGenerating else { return }
        runLocalCommand("/standards")
    }

    func disableSkill() {
        guard !isGenerating else { return }
        runLocalCommand("/skill off")
    }

    private func buildPrompt(userText: String, priorLines: [Line]) -> String {
        let skillInstructions = activeSkill?.systemInstructions ?? """
        Active skill: GENERAL.
        Help with ordinary conversation and coding questions while preserving the terminal's conversation-only authority.
        """

        let context = boundedContext(from: priorLines)

        return """
        You are caRINA 0.4.0, a local-first personal assistant running on the user's Mac.
        Be concise, direct, useful, and transparent about what you can and cannot do.
        This terminal is a conversation surface only. Do not claim that shell commands,
        files, network services, approvals, deployments, tests, or device actions were
        executed unless another trusted subsystem explicitly reports that result.

        \(skillInstructions)

        Recent terminal context:
        \(context.isEmpty ? "(none)" : context)

        Current user message:
        \(userText)

        caRINA:
        """
    }

    private func boundedContext(from source: [Line]) -> String {
        var remaining = maxContextCharacters
        var selected: [String] = []

        for line in source.reversed() {
            guard line.role == .user || line.role == .carina else { continue }
            let speaker = line.role == .user ? "User" : "caRINA"
            let entry = "\(speaker): \(line.text)"

            guard entry.count <= remaining else { break }
            selected.append(entry)
            remaining -= entry.count
        }

        return selected.reversed().joined(separator: "\n")
    }

    private func boot() {
        statusText = "READY"
        lines.append(Line(role: .system, text: "caRINA 0.4.0 // LOCAL CONSOLE"))
        lines.append(Line(role: .system, text: "Engine: Ollama @ 127.0.0.1:11434"))
        lines.append(Line(role: .system, text: "Boundary: conversation only • no shell execution"))
        lines.append(Line(role: .system, text: "Skills: CODING STANDARDS • SECURITY AUDIT"))
        lines.append(Line(role: .system, text: "Type /skills to feel the skill layer."))
    }

    private func runLocalCommand(_ rawCommand: String) {
        let command = rawCommand
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if command == "/help" {
            lines.append(Line(
                role: .system,
                text: "Commands: /status  /skills  /audit  /standards  /skill <name|off>  /about  /clear  /stop  /help"
            ))
            return
        }

        if command == "/status" {
            lines.append(Line(
                role: .system,
                text: "v0.4.0 • LOCAL • \(statusText) • skill=\(activeSkill?.rawValue ?? "general") • conversation-only authority"
            ))
            return
        }

        if command == "/skills" {
            let skillList = CarinaSkill.allCases
                .map { "\($0.displayName): \($0.summary)" }
                .joined(separator: "\n")
            lines.append(Line(role: .system, text: "INSTALLED SKILLS\n\(skillList)\nUse /audit, /standards, or /skill off."))
            return
        }

        if command == "/audit" {
            activate(.securityAudit)
            lines.append(Line(
                role: .system,
                text: "AUDIT INTERVIEW ARMED\nQ1 What changed or became remote?\nQ2 Rank the worst outcomes: data loss/corruption, unpublished-content disclosure, cost/database abuse, cloud-to-local path.\nQ3 Scope: remote only, remote+core, full monorepo, external deploy settings?\nQ4 Deliverable: report, issues, report→accepted issues, or report+separately approved fixes?"
            ))
            return
        }

        if command == "/standards" {
            activate(.codingStandards)
            lines.append(Line(
                role: .system,
                text: "CODING_STANDARDS.md loaded as terminal guidance: smallest safe change • typed state • fail closed • protect secrets/data • never fake execution • verify what actually ran."
            ))
            return
        }

        if command == "/skill" {
            lines.append(Line(role: .system, text: "Usage: /skill coding-standards | /skill security-audit | /skill off"))
            return
        }

        if command.hasPrefix("/skill ") {
            let token = String(command.dropFirst("/skill ".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if token == "off" || token == "general" {
                activeSkill = nil
                lines.append(Line(role: .system, text: "Skill layer set to GENERAL."))
            } else if let skill = CarinaSkill.resolve(token) {
                activate(skill)
            } else {
                lines.append(Line(role: .error, text: "Unknown skill: \(token). Type /skills."))
            }
            return
        }

        if command == "/about" {
            lines.append(Line(
                role: .system,
                text: "caRINA is awake locally. This surface talks to the loopback Ollama client, keeps bounded in-memory conversation context, and can load reasoning skills. It still does not expose a shell, listener, remote fallback, or action executor."
            ))
            return
        }

        if command == "/clear" {
            clear()
            return
        }

        if command == "/stop" {
            stop()
            return
        }

        lines.append(Line(role: .error, text: "Unknown local command: \(rawCommand)"))
    }

    private func activate(_ skill: CarinaSkill) {
        activeSkill = skill
        lines.append(Line(role: .system, text: "Skill armed: \(skill.displayName) • analysis authority only"))
    }
}
