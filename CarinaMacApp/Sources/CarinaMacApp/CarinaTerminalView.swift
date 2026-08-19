import AppKit
import SwiftUI

struct CarinaTerminalView: View {
    private enum WorkspacePanel: String, CaseIterable, Identifiable {
        case terminal = "TERMINAL"
        case problems = "PROBLEMS"
        case logs = "LOGS"
        case tasks = "TASKS"
        case skills = "SKILLS"
        case security = "SECURITY"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .terminal: return "terminal"
            case .problems: return "exclamationmark.triangle"
            case .logs: return "text.alignleft"
            case .tasks: return "checklist"
            case .skills: return "square.stack.3d.up"
            case .security: return "shield.lefthalf.filled"
            }
        }

        var shortcut: KeyEquivalent {
            switch self {
            case .terminal: return KeyEquivalent("1")
            case .problems: return KeyEquivalent("2")
            case .logs: return KeyEquivalent("3")
            case .tasks: return KeyEquivalent("4")
            case .skills: return KeyEquivalent("5")
            case .security: return KeyEquivalent("6")
            }
        }
    }

    @StateObject private var viewModel = CarinaTerminalViewModel()
    @State private var pulse = false
    @State private var selectedPanel: WorkspacePanel = .terminal

    private var statusColor: Color {
        switch viewModel.statusText {
        case "READY": return .green
        case "THINKING": return .orange
        case "OFFLINE", "ERROR": return .red
        default: return .yellow
        }
    }

    private var skillColor: Color {
        switch viewModel.activeSkill {
        case .securityAudit: return .purple
        case .codingStandards: return .cyan
        case nil: return .secondary
        }
    }

    private var composerPlaceholder: String {
        switch viewModel.activeSkill {
        case .securityAudit:
            return "Answer the audit interview or ask caRINA to inspect a risk…"
        case .codingStandards:
            return "Describe the code change you want reviewed or designed…"
        case nil:
            return "Ask caRINA or type /skills"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            workspaceTitleBar
            Divider().overlay(Color.white.opacity(0.12))

            HStack(spacing: 0) {
                activityRail
                Divider().overlay(Color.white.opacity(0.10))

                VStack(spacing: 0) {
                    workspaceTabs
                    Divider().overlay(Color.white.opacity(0.10))
                    panelContent
                }
            }

            Divider().overlay(Color.white.opacity(0.12))
            statusBar
        }
        .background(Color.black)
        .foregroundStyle(.white)
        .frame(minWidth: 980, minHeight: 680)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var workspaceTitleBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.16))
                    .frame(width: 30, height: 30)
                    .scaleEffect(pulse ? 1.08 : 0.92)
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: statusColor.opacity(0.9), radius: 8)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("caRINA")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                    Text("SHE'S ALIVE 0.4.0")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.purple)
                }
                Text("CARINA WORKSPACE • LOCAL • 127.0.0.1:11434")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            contextChip(title: "CODING_STANDARDS.md", color: .cyan)
            contextChip(title: "CarinaTerminalView.swift", color: .purple)

            Text("SKILL: \(viewModel.activeSkillLabel)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(skillColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(skillColor.opacity(0.10), in: Capsule())
                .overlay(Capsule().stroke(skillColor.opacity(0.32), lineWidth: 1))

            Text(viewModel.statusText)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(statusColor.opacity(0.11), in: Capsule())
                .overlay(Capsule().stroke(statusColor.opacity(0.35), lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.035))
    }

    private var activityRail: some View {
        VStack(spacing: 10) {
            ForEach(WorkspacePanel.allCases) { panel in
                WorkspaceIconButton(
                    systemImage: panel.systemImage,
                    title: panel.rawValue,
                    isSelected: selectedPanel == panel
                ) {
                    haptic()
                    selectedPanel = panel
                }
                .keyboardShortcut(panel.shortcut, modifiers: [.command])
            }

            Spacer()

            Image(systemName: "heart.fill")
                .foregroundStyle(.purple)
                .font(.system(size: 14))
                .help("She's alive 0.4.0")
        }
        .padding(.vertical, 12)
        .frame(width: 54)
        .background(Color.white.opacity(0.025))
    }

    private var workspaceTabs: some View {
        HStack(spacing: 0) {
            ForEach(WorkspacePanel.allCases) { panel in
                WorkspaceTabButton(
                    title: panel.rawValue,
                    systemImage: panel.systemImage,
                    isSelected: selectedPanel == panel,
                    badge: badge(for: panel)
                ) {
                    haptic()
                    selectedPanel = panel
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 40)
        .background(Color.white.opacity(0.025))
    }

    @ViewBuilder
    private var panelContent: some View {
        switch selectedPanel {
        case .terminal:
            terminalPanel
        case .problems:
            problemsPanel
        case .logs:
            logsPanel
        case .tasks:
            tasksPanel
        case .skills:
            skillsPanel
        case .security:
            securityPanel
        }
    }

    private var terminalPanel: some View {
        VStack(spacing: 0) {
            console
            Divider().overlay(Color.white.opacity(0.10))
            controls
            composer
        }
    }

    private var console: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.lines) { line in
                        TerminalLineView(line: line)
                            .id(line.id)
                    }

                    if viewModel.isGenerating {
                        HStack(alignment: .top, spacing: 10) {
                            Text("carina ›")
                                .foregroundStyle(.green)
                            Text(viewModel.liveResponse.isEmpty ? "thinking…" : viewModel.liveResponse)
                                .foregroundStyle(.white)
                            Text("▌")
                                .foregroundStyle(.green)
                                .opacity(pulse ? 1 : 0.25)
                        }
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .textSelection(.enabled)
                        .id("live-response")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            .background(
                LinearGradient(
                    colors: [Color.black, Color(red: 0.025, green: 0.035, blue: 0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onChange(of: viewModel.lines.count) { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.liveResponse) { _ in
                scrollToBottom(proxy)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            TerminalControlButton(title: "STATUS", systemImage: "waveform.path.ecg") {
                haptic()
                selectedPanel = .terminal
                viewModel.showStatus()
            }
            TerminalControlButton(title: "SKILLS", systemImage: "square.stack.3d.up") {
                haptic()
                selectedPanel = .skills
            }
            TerminalControlButton(
                title: "AUDIT",
                systemImage: "shield.lefthalf.filled",
                isProminent: viewModel.activeSkill == .securityAudit
            ) {
                haptic()
                selectedPanel = .terminal
                viewModel.startSecurityAudit()
            }
            TerminalControlButton(title: "HELP", systemImage: "questionmark.circle") {
                haptic()
                selectedPanel = .terminal
                viewModel.showHelp()
            }
            TerminalControlButton(title: "CLEAR", systemImage: "sparkles") {
                haptic()
                viewModel.clear()
            }
            TerminalControlButton(
                title: "STOP",
                systemImage: "stop.fill",
                isProminent: viewModel.isGenerating
            ) {
                haptic()
                viewModel.stop()
            }
            .disabled(!viewModel.isGenerating)
            .keyboardShortcut(KeyEquivalent("."), modifiers: [.command])

            Spacer()

            Text("⌘1…⌘6 PANELS   /audit   /standards   ⌘↩ SEND   ⌘. STOP")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.028))
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Text("❯")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(.green)

            TextField(composerPlaceholder, text: $viewModel.input)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .disabled(viewModel.isGenerating)
                .onSubmit {
                    send()
                }

            Button {
                send()
            } label: {
                Label(viewModel.isGenerating ? "Working" : "Send", systemImage: "arrow.up.circle.fill")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.isGenerating ? Color.secondary : Color.black)
            .background(viewModel.isGenerating ? Color.white.opacity(0.08) : Color.green, in: RoundedRectangle(cornerRadius: 8))
            .disabled(viewModel.isGenerating || viewModel.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(14)
        .background(Color.white.opacity(0.045))
    }

    private var problemsPanel: some View {
        WorkspaceDetailPanel(
            title: "PROBLEMS",
            subtitle: "Only verified diagnostics belong here.",
            systemImage: "exclamationmark.triangle"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                WorkspaceMessageCard(
                    level: "VERIFY",
                    title: "Mac build not yet observed",
                    detail: "This prototype branch was edited through the GitHub connector. A successful `swift build` / app launch has not been observed in this session.",
                    color: .yellow
                )
                WorkspaceMessageCard(
                    level: "BOUNDARY",
                    title: "No execution diagnostics fabricated",
                    detail: "caRINA will not invent compiler errors, test results, ports, deployment state, or security findings without a trusted subsystem reporting them.",
                    color: .cyan
                )
            }
        }
    }

    private var logsPanel: some View {
        WorkspaceDetailPanel(
            title: "LOGS",
            subtitle: "Privacy-minimized lifecycle state. Prompts and model responses are not copied into logs.",
            systemImage: "text.alignleft"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                LogRow(label: "runtime", value: "LOCAL")
                LogRow(label: "model endpoint", value: "127.0.0.1:11434")
                LogRow(label: "terminal state", value: viewModel.statusText)
                LogRow(label: "active skill", value: viewModel.activeSkillLabel)
                LogRow(label: "generation", value: viewModel.isGenerating ? "ACTIVE" : "IDLE")
                LogRow(label: "content logging", value: "DISABLED")
            }
        }
    }

    private var tasksPanel: some View {
        WorkspaceDetailPanel(
            title: "TASKS",
            subtitle: "Prototype verification queue. These are local development checkpoints, not background jobs.",
            systemImage: "checklist"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                TaskRow(state: "DONE", title: "Build tactile terminal surface", color: .green)
                TaskRow(state: "DONE", title: "Add Coding Standards + Security Audit skills", color: .green)
                TaskRow(state: "DONE", title: "Add IDE-style Terminal / Problems / Logs / Tasks / Skills / Security workspace", color: .green)
                TaskRow(state: "NEXT", title: "Run `swift build` and launch CarinaMacApp on macOS", color: .yellow)
                TaskRow(state: "NEXT", title: "Exercise panel switching, haptics, Ollama streaming, /audit, and /standards", color: .yellow)
                TaskRow(state: "HOLD", title: "Merge PR only after verification", color: .orange)
            }
        }
    }

    private var skillsPanel: some View {
        WorkspaceDetailPanel(
            title: "SKILLS",
            subtitle: "Visible reasoning modes. Skills change how caRINA thinks, not what she is authorized to execute.",
            systemImage: "square.stack.3d.up"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(CarinaSkill.allCases) { skill in
                    Button {
                        haptic()
                        selectedPanel = .terminal
                        if skill == .securityAudit {
                            viewModel.startSecurityAudit()
                        } else {
                            viewModel.activateCodingStandards()
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: skill == .securityAudit ? "shield.lefthalf.filled" : "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(skill == .securityAudit ? Color.purple : Color.cyan)
                                .frame(width: 26)

                            VStack(alignment: .leading, spacing: 5) {
                                Text(skill.displayName)
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                Text(skill.summary)
                                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer()

                            if viewModel.activeSkill == skill {
                                Text("ACTIVE")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.green)
                            } else {
                                Image(systemName: "arrow.right.circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
                }

                Button("Disable active skill") {
                    haptic()
                    selectedPanel = .terminal
                    viewModel.disableSkill()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .disabled(viewModel.activeSkill == nil)
            }
        }
    }

    private var securityPanel: some View {
        WorkspaceDetailPanel(
            title: "SECURITY",
            subtitle: "The workspace is visual and conversational. Authority remains behind the existing approval boundary.",
            systemImage: "shield.lefthalf.filled"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                SecurityBoundaryRow(title: "Ollama", detail: "Loopback only • 127.0.0.1:11434", state: "LOCAL", color: .green)
                SecurityBoundaryRow(title: "Shell", detail: "No command executor connected to this terminal", state: "BLOCKED", color: .green)
                SecurityBoundaryRow(title: "Secrets", detail: "Secret values must never be printed or copied into model context", state: "PROTECTED", color: .green)
                SecurityBoundaryRow(title: "Actions", detail: "Execution still requires reviewed capability + approval path", state: "GATED", color: .purple)
                SecurityBoundaryRow(title: "Remote listener", detail: "No listener or cloud fallback added by this prototype", state: "OFF", color: .green)
                SecurityBoundaryRow(title: "Build verification", detail: "Mac compile/run remains unverified in this connector session", state: "PENDING", color: .yellow)
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 14) {
            Label("feature/carina-terminal-v0.4.0", systemImage: "arrow.triangle.branch")
            Text("LOCAL")
                .foregroundStyle(.green)
            Text("OLLAMA")
            Text("SKILL \(viewModel.activeSkillLabel)")
                .foregroundStyle(skillColor)

            Spacer()

            Text("⌘1 TERMINAL  ⌘2 PROBLEMS  ⌘3 LOGS  ⌘4 TASKS  ⌘5 SKILLS  ⌘6 SECURITY")
                .foregroundStyle(.secondary)
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(viewModel.statusText)
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Color(red: 0.075, green: 0.035, blue: 0.10))
    }

    private func contextChip(title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title)
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }

    private func badge(for panel: WorkspacePanel) -> String? {
        switch panel {
        case .problems: return "1"
        case .tasks: return "3"
        case .skills: return "2"
        default: return nil
        }
    }

    private func send() {
        guard !viewModel.isGenerating else { return }
        haptic()
        selectedPanel = .terminal
        viewModel.submit()
    }

    private func haptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if viewModel.isGenerating {
            withAnimation(.easeOut(duration: 0.12)) {
                proxy.scrollTo("live-response", anchor: .bottom)
            }
        } else if let lastID = viewModel.lines.last?.id {
            withAnimation(.easeOut(duration: 0.12)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }
}

private struct TerminalLineView: View {
    let line: CarinaTerminalViewModel.Line

    private var prefix: String {
        switch line.role {
        case .system: return "sys    ›"
        case .user: return "amo    ›"
        case .carina: return "carina ›"
        case .error: return "error  ›"
        }
    }

    private var prefixColor: Color {
        switch line.role {
        case .system: return .secondary
        case .user: return .cyan
        case .carina: return .green
        case .error: return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(prefix)
                .foregroundStyle(prefixColor)
                .frame(width: 72, alignment: .leading)
            Text(line.text)
                .foregroundStyle(line.role == .system ? Color.white.opacity(0.72) : .white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 14, weight: .regular, design: .monospaced))
        .textSelection(.enabled)
    }
}

private struct TerminalControlButton: View {
    let title: String
    let systemImage: String
    var isProminent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isProminent ? Color.black : Color.white.opacity(0.88))
        .background(
            isProminent ? Color.orange : Color.white.opacity(0.065),
            in: RoundedRectangle(cornerRadius: 7)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

private struct WorkspaceIconButton: View {
    let systemImage: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isSelected ? Color.purple : Color.secondary)
                .frame(width: 38, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.purple.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule().fill(Color.purple).frame(width: 2, height: 22)
            }
        }
        .help(title)
    }
}

private struct WorkspaceTabButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
                if let badge {
                    Text(badge)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
            }
            .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .monospaced))
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .padding(.horizontal, 13)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.white.opacity(0.045) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isSelected ? Color.purple : Color.clear)
                .frame(height: 2)
        }
    }
}

private struct WorkspaceDetailPanel<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.purple)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                        Text(subtitle)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
        }
        .background(
            LinearGradient(
                colors: [Color.black, Color(red: 0.02, green: 0.02, blue: 0.03)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

private struct WorkspaceMessageCard: View {
    let level: String
    let title: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(level)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 62, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                Text(detail)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(color.opacity(0.18), lineWidth: 1))
    }
}

private struct LogRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(label.uppercased())
                .foregroundStyle(.secondary)
                .frame(width: 138, alignment: .leading)
            Text(value)
                .foregroundStyle(.white)
            Spacer()
        }
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .padding(.vertical, 4)
    }
}

private struct TaskRow: View {
    let state: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Text(state)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 44, alignment: .leading)
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

private struct SecurityBoundaryRow: View {
    let title: String
    let detail: String
    let state: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                Text(detail)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(state)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.10), in: Capsule())
        }
        .padding(12)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
    }
}
