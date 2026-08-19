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

        var icon: String {
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
            case .terminal: return "1"
            case .problems: return "2"
            case .logs: return "3"
            case .tasks: return "4"
            case .skills: return "5"
            case .security: return "6"
            }
        }
    }

    @StateObject private var viewModel = CarinaTerminalViewModel()
    @State private var selectedPanel: WorkspacePanel = .terminal
    @State private var pulse = false

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
            return "Answer the audit interview or describe a risk…"
        case .codingStandards:
            return "Describe the code change you want reviewed…"
        case nil:
            return "Ask caRINA or type /skills"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().overlay(Color.white.opacity(0.12))

            HStack(spacing: 0) {
                activityRail
                Divider().overlay(Color.white.opacity(0.10))

                VStack(spacing: 0) {
                    panelTabs
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
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var titleBar: some View {
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
            contextChip("CODING_STANDARDS.md", color: .cyan)
            contextChip("CarinaTerminalView.swift", color: .purple)
            statusChip("SKILL: \(viewModel.activeSkillLabel)", color: skillColor)
            statusChip(viewModel.statusText, color: statusColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.035))
    }

    private var activityRail: some View {
        VStack(spacing: 9) {
            ForEach(WorkspacePanel.allCases) { panel in
                Button {
                    haptic()
                    selectedPanel = panel
                } label: {
                    Image(systemName: panel.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(selectedPanel == panel ? Color.purple : Color.secondary)
                        .frame(width: 38, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    selectedPanel == panel ? Color.purple.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .overlay(alignment: .leading) {
                    if selectedPanel == panel {
                        Capsule().fill(Color.purple).frame(width: 2, height: 22)
                    }
                }
                .keyboardShortcut(panel.shortcut, modifiers: [.command])
                .help(panel.rawValue)
            }

            Spacer()

            Image(systemName: "heart.fill")
                .foregroundStyle(.purple)
                .help("She's alive 0.4.0")
        }
        .padding(.vertical, 12)
        .frame(width: 54)
        .background(Color.white.opacity(0.025))
    }

    private var panelTabs: some View {
        HStack(spacing: 0) {
            ForEach(WorkspacePanel.allCases) { panel in
                Button {
                    haptic()
                    selectedPanel = panel
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: panel.icon)
                        Text(panel.rawValue)
                        if let count = badge(for: panel) {
                            Text(count)
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.08), in: Capsule())
                        }
                    }
                    .font(.system(size: 10, weight: selectedPanel == panel ? .bold : .medium, design: .monospaced))
                    .foregroundStyle(selectedPanel == panel ? Color.white : Color.secondary)
                    .padding(.horizontal, 13)
                    .frame(height: 40)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(selectedPanel == panel ? Color.white.opacity(0.045) : Color.clear)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(selectedPanel == panel ? Color.purple : Color.clear)
                        .frame(height: 2)
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
                            Text("carina ›").foregroundStyle(.green)
                            Text(viewModel.liveResponse.isEmpty ? "thinking…" : viewModel.liveResponse)
                            Text("▌")
                                .foregroundStyle(.green)
                                .opacity(pulse ? 1 : 0.25)
                        }
                        .font(.system(size: 14, design: .monospaced))
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
            .onChange(of: viewModel.lines.count) { _ in scrollToBottom(proxy) }
            .onChange(of: viewModel.liveResponse) { _ in scrollToBottom(proxy) }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            control("STATUS", icon: "waveform.path.ecg") {
                selectedPanel = .terminal
                viewModel.showStatus()
            }
            control("SKILLS", icon: "square.stack.3d.up") {
                selectedPanel = .skills
            }
            control("AUDIT", icon: "shield.lefthalf.filled", prominent: viewModel.activeSkill == .securityAudit) {
                selectedPanel = .terminal
                viewModel.startSecurityAudit()
            }
            control("HELP", icon: "questionmark.circle") {
                selectedPanel = .terminal
                viewModel.showHelp()
            }
            control("CLEAR", icon: "sparkles") { viewModel.clear() }
            control("STOP", icon: "stop.fill", prominent: viewModel.isGenerating) { viewModel.stop() }
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
                .font(.system(size: 14, design: .monospaced))
                .disabled(viewModel.isGenerating)
                .onSubmit { send() }

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
            .background(
                viewModel.isGenerating ? Color.white.opacity(0.08) : Color.green,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .disabled(viewModel.isGenerating || viewModel.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(14)
        .background(Color.white.opacity(0.045))
    }

    private var problemsPanel: some View {
        detailPanel(
            title: "PROBLEMS",
            subtitle: "Only verified diagnostics belong here.",
            icon: "exclamationmark.triangle"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                messageCard(
                    level: "VERIFY",
                    title: "Mac build not yet observed",
                    detail: "This branch was edited through the GitHub connector. A successful swift build and app launch have not been observed in this session.",
                    color: .yellow
                )
                messageCard(
                    level: "BOUNDARY",
                    title: "No diagnostics fabricated",
                    detail: "caRINA will not invent compiler errors, test results, ports, deployments, or security findings without trusted evidence.",
                    color: .cyan
                )
            }
        }
    }

    private var logsPanel: some View {
        detailPanel(
            title: "LOGS",
            subtitle: "Privacy-minimized lifecycle state. Prompt and model content is not duplicated into logs.",
            icon: "text.alignleft"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                logRow("runtime", "LOCAL")
                logRow("model endpoint", "127.0.0.1:11434")
                logRow("terminal state", viewModel.statusText)
                logRow("active skill", viewModel.activeSkillLabel)
                logRow("generation", viewModel.isGenerating ? "ACTIVE" : "IDLE")
                logRow("content logging", "DISABLED")
            }
        }
    }

    private var tasksPanel: some View {
        detailPanel(
            title: "TASKS",
            subtitle: "Prototype verification queue. These are development checkpoints, not background jobs.",
            icon: "checklist"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                taskRow("DONE", "Build tactile terminal surface", color: .green)
                taskRow("DONE", "Add Coding Standards + Security Audit skills", color: .green)
                taskRow("DONE", "Add IDE-style six-panel workspace", color: .green)
                taskRow("NEXT", "Run swift build and launch CarinaMacApp on macOS", color: .yellow)
                taskRow("NEXT", "Exercise panels, haptics, Ollama streaming, /audit, /standards", color: .yellow)
                taskRow("HOLD", "Merge PR only after verification", color: .orange)
            }
        }
    }

    private var skillsPanel: some View {
        detailPanel(
            title: "SKILLS",
            subtitle: "Visible reasoning modes. Skills change how caRINA thinks, not what she can execute.",
            icon: "square.stack.3d.up"
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
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }

                            Spacer()
                            Text(viewModel.activeSkill == skill ? "ACTIVE" : "LOAD")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(viewModel.activeSkill == skill ? Color.green : Color.secondary)
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
        detailPanel(
            title: "SECURITY",
            subtitle: "The workspace is visual and conversational. Authority remains behind the existing approval boundary.",
            icon: "shield.lefthalf.filled"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                boundaryRow("Ollama", "Loopback only • 127.0.0.1:11434", state: "LOCAL", color: .green)
                boundaryRow("Shell", "No command executor connected to this terminal", state: "BLOCKED", color: .green)
                boundaryRow("Secrets", "Secret values must never enter logs or model context", state: "PROTECTED", color: .green)
                boundaryRow("Actions", "Execution still requires reviewed capability + approval path", state: "GATED", color: .purple)
                boundaryRow("Remote listener", "No listener or cloud fallback added by this prototype", state: "OFF", color: .green)
                boundaryRow("Build verification", "Mac compile/run remains unverified in this connector session", state: "PENDING", color: .yellow)
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 14) {
            Label("feature/carina-terminal-v0.4.0", systemImage: "arrow.triangle.branch")
            Text("LOCAL").foregroundStyle(.green)
            Text("OLLAMA")
            Text("SKILL \(viewModel.activeSkillLabel)").foregroundStyle(skillColor)
            Spacer()
            Text("⌘1 TERMINAL  ⌘2 PROBLEMS  ⌘3 LOGS  ⌘4 TASKS  ⌘5 SKILLS  ⌘6 SECURITY")
                .foregroundStyle(.secondary)
            Circle().fill(statusColor).frame(width: 7, height: 7)
            Text(viewModel.statusText)
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Color(red: 0.075, green: 0.035, blue: 0.10))
    }

    private func contextChip(_ title: String, color: Color) -> some View {
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

    private func statusChip(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(color.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.32), lineWidth: 1))
    }

    private func badge(for panel: WorkspacePanel) -> String? {
        switch panel {
        case .problems: return "1"
        case .tasks: return "3"
        case .skills: return "2"
        default: return nil
        }
    }

    private func control(
        _ title: String,
        icon: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            haptic()
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(prominent ? Color.black : Color.white.opacity(0.88))
        .background(prominent ? Color.orange : Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    @ViewBuilder
    private func detailPanel<Content: View>(
        title: String,
        subtitle: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.purple)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                        Text(subtitle)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                content()
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

    private func messageCard(level: String, title: String, detail: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(level)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 62, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .semibold, design: .monospaced))
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(color.opacity(0.18), lineWidth: 1))
    }

    private func logRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label.uppercased())
                .foregroundStyle(.secondary)
                .frame(width: 138, alignment: .leading)
            Text(value)
            Spacer()
        }
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .padding(.vertical, 4)
    }

    private func taskRow(_ state: String, _ title: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Text(state)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 44, alignment: .leading)
            Text(title).font(.system(size: 12, weight: .medium, design: .monospaced))
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func boundaryRow(_ title: String, _ detail: String, state: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(color).frame(width: 7, height: 7).padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .bold, design: .monospaced))
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
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
        .font(.system(size: 14, design: .monospaced))
        .textSelection(.enabled)
    }
}
