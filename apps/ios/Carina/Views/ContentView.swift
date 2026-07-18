import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: BridgeSettings
    @EnvironmentObject private var bridge: BridgeClient
    @EnvironmentObject private var credentials: CredentialManager
    @EnvironmentObject private var agent: CarinaAgentService
    @EnvironmentObject private var speech: SpeechRecognitionService
    @EnvironmentObject private var permissions: PermissionManager

    @State private var command = ""
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                CarinaBackground()

                ScrollView {
                    LazyVStack(spacing: 22) {
                        hero
                        routeSelector
                        connectionPanel
                        conversationPanel

                        if let approval = agent.pendingApproval {
                            approvalPanel(approval)
                        }

                        Color.clear.frame(height: 112)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(bridge.state == .connected ? CarinaTheme.signal : CarinaTheme.muted)
                            .frame(width: 7, height: 7)
                            .shadow(color: bridge.state == .connected ? CarinaTheme.signal.opacity(0.8) : .clear, radius: 5)
                        Text("CARINA")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .tracking(2.8)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 40, height: 40)
                            .background(CarinaTheme.control, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(CarinaPressButtonStyle())
                    .accessibilityLabel("CARINA Settings")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .onChange(of: speech.transcript) { _, transcript in command = transcript }
            .sheet(isPresented: $showingSettings) {
                SettingsView(settings: settings, permissions: permissions, credentials: credentials)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                Text(agent.state == .sending ? "PROCESSING REQUEST" : "AGENT COMMAND CENTER")
                    .font(.caption2.weight(.bold))
                    .tracking(1.7)
                    .foregroundStyle(CarinaTheme.signal)

                Text(agent.state == .sending ? "Thinking with\n\(agent.route.displayName)" : "Your agents,\none clear channel.")
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .tracking(-0.9)
                    .lineSpacing(-2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 7) {
                    Image(systemName: agent.route.symbolName)
                    Text(routeDetail)
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(CarinaTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            CarinaCore(isActive: agent.state == .sending)
                .frame(width: 78, height: 98)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
    }

    private var routeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Route", detail: "Choose who handles this request")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(AgentRoute.allCases) { route in
                        Button {
                            withAnimation(.snappy(duration: 0.24)) { agent.route = route }
                        } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                Image(systemName: route.symbolName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(agent.route == route ? CarinaTheme.ink : CarinaTheme.signal)
                                Text(route.displayName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(agent.route == route ? CarinaTheme.ink : .primary)
                                    .lineLimit(1)
                            }
                            .frame(width: 82, height: 62, alignment: .leading)
                            .padding(.horizontal, 13)
                            .background(
                                agent.route == route ? CarinaTheme.signal : CarinaTheme.control,
                                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 15, style: .continuous)
                                    .stroke(agent.route == route ? CarinaTheme.signal : CarinaTheme.hairline, lineWidth: 1)
                            }
                        }
                        .buttonStyle(CarinaPressButtonStyle())
                        .accessibilityLabel("Use \(route.displayName)")
                        .accessibilityAddTraits(agent.route == route ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private var connectionPanel: some View {
        CarinaSurface(accent: bridge.state == .connected ? CarinaTheme.signal : CarinaTheme.warning) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Agent network")
                            .font(.title3.weight(.semibold))
                        Text(connectionSummary)
                            .font(.footnote)
                            .foregroundStyle(CarinaTheme.secondaryText)
                    }
                    Spacer()
                    StatusIndicator(
                        text: bridge.state == .connected ? "Connected" : bridge.state.label,
                        color: bridge.state == .connected ? CarinaTheme.signal : CarinaTheme.warning
                    )
                }

                HStack(spacing: 1) {
                    NetworkMetric(
                        title: "Mac bridge",
                        value: bridge.state.label,
                        icon: "macbook"
                    )
                    Rectangle()
                        .fill(CarinaTheme.hairline)
                        .frame(width: 1, height: 38)
                    NetworkMetric(
                        title: "Device token",
                        value: credentials.hasBridgeToken ? "Secured" : "Setup needed",
                        icon: credentials.hasBridgeToken ? "checkmark.seal.fill" : "key"
                    )
                }
                .background(CarinaTheme.recessed, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                Button(action: connect) {
                    HStack(spacing: 10) {
                        if bridge.state == .connecting {
                            ProgressView().tint(CarinaTheme.ink)
                        } else {
                            Image(systemName: bridge.state == .connected ? "arrow.clockwise" : "link")
                        }
                        Text(bridge.state == .connected ? "Refresh connection" : "Connect Mac + OpenClaw")
                        Spacer()
                        Text("\(BridgeConfiguration.httpPort) · \(BridgeConfiguration.webSocketPort)")
                            .font(.caption.monospacedDigit().weight(.medium))
                            .foregroundStyle(CarinaTheme.ink.opacity(0.62))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CarinaTheme.ink)
                    .padding(.horizontal, 15)
                    .frame(minHeight: 50)
                    .background(CarinaTheme.signal, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(CarinaPressButtonStyle())
                .disabled(bridge.state == .connecting)

                if !bridge.lastMessage.isEmpty {
                    Label(bridge.lastMessage, systemImage: bridge.state == .connected ? "checkmark.circle" : "info.circle")
                        .font(.caption)
                        .foregroundStyle(CarinaTheme.secondaryText)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var conversationPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Conversation", detail: agent.route.displayName)

            if agent.messages.isEmpty {
                CarinaSurface {
                    HStack(alignment: .center, spacing: 16) {
                        Image(systemName: agent.route.symbolName)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(CarinaTheme.signal)
                            .frame(width: 48, height: 48)
                            .background(CarinaTheme.signalSoft, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Ready for \(agent.route.displayName)")
                                .font(.headline)
                            Text(emptyConversationDetail)
                                .font(.footnote)
                                .foregroundStyle(CarinaTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else {
                ForEach(agent.messages) { message in
                    MessageBubble(message: message)
                }
            }

            if agent.state == .sending {
                HStack(spacing: 10) {
                    ProgressView().tint(CarinaTheme.signal)
                    Text("Routing through \(agent.route.displayName)…")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(CarinaTheme.secondaryText)
                }
                .padding(.horizontal, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if case .failed(let error) = agent.state {
                ErrorBanner(text: error)
            }
            if let error = speech.errorMessage {
                ErrorBanner(text: error)
            }
        }
    }

    private func approvalPanel(_ approval: PreparedAction) -> some View {
        CarinaSurface(accent: CarinaTheme.warning) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .font(.title3)
                        .foregroundStyle(CarinaTheme.warning)
                        .frame(width: 42, height: 42)
                        .background(CarinaTheme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Approval required")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(CarinaTheme.warning)
                        Text(approval.summary)
                            .font(.headline)
                    }
                    Spacer()
                }

                HStack {
                    Label(approval.command, systemImage: "terminal")
                    Spacer()
                    Label(approval.expiresAt.formatted(date: .omitted, time: .shortened), systemImage: "timer")
                }
                .font(.caption)
                .foregroundStyle(CarinaTheme.secondaryText)

                if !approval.payload.isEmpty {
                    Text(approval.payload.keys.sorted().map { "\($0): \(approval.payload[$0] ?? "")" }.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .foregroundStyle(CarinaTheme.secondaryText)
                        .lineLimit(5)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CarinaTheme.recessed, in: RoundedRectangle(cornerRadius: 13))
                }

                HStack(spacing: 10) {
                    Button("Deny", role: .destructive) { agent.deny() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                    Button("Approve once") {
                        agent.approve(configuration: try? settings.configuration(), bearerToken: credentials.bridgeToken)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CarinaTheme.warning)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 9) {
            Button {
                Task { speech.isListening ? speech.stop() : await speech.start() }
            } label: {
                Image(systemName: speech.isListening ? "stop.fill" : "waveform")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 46, height: 46)
                    .foregroundStyle(speech.isListening ? .white : CarinaTheme.signal)
                    .background(
                        speech.isListening ? CarinaTheme.danger : CarinaTheme.control,
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                    )
            }
            .buttonStyle(CarinaPressButtonStyle())
            .accessibilityLabel(speech.isListening ? "Stop listening" : "Speak")

            TextField("Ask \(agent.route.displayName)…", text: $command, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .background(CarinaTheme.control, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(CarinaTheme.hairline, lineWidth: 1)
                }
                .submitLabel(.send)
                .onSubmit(send)

            Button {
                agent.state == .sending ? agent.cancel() : send()
            } label: {
                Image(systemName: agent.state == .sending ? "xmark" : "arrow.up")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 46, height: 46)
                    .foregroundStyle(CarinaTheme.ink)
                    .background(CarinaTheme.signal, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(CarinaPressButtonStyle())
            .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && agent.state != .sending)
            .opacity(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && agent.state != .sending ? 0.45 : 1)
            .accessibilityLabel(agent.state == .sending ? "Cancel" : "Send")
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 7)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(CarinaTheme.hairline).frame(height: 1)
        }
    }

    private var routeDetail: String {
        switch agent.route {
        case .apple: "Private on-device reasoning · no API usage"
        case .clever: "Secure handoff to your Clever AI subscription"
        case .ollama: "Local model through your authenticated Mac"
        case .openclaw: "Maya, Hermes, Karina and tools"
        default: "Active route · \(agent.route.displayName)"
        }
    }

    private var connectionSummary: String {
        switch bridge.state {
        case .connected: "Mac bridge and live agent channel are ready."
        case .connecting: "Checking HTTP and WebSocket channels…"
        default: "Connect securely to OpenClaw and your local agents."
        }
    }

    private var emptyConversationDetail: String {
        switch agent.route {
        case .apple: "Runs with Apple’s on-device Foundation Model when available."
        case .clever: "CARINA copies your prompt and opens Clever AI after one approval."
        case .openclaw: "Connect your Mac bridge to reach agents, tools and local models."
        default: "Requests stay on this route. Execute actions still require approval."
        }
    }

    private func connect() {
        Task {
            guard settings.save(), let configuration = try? settings.configuration(), credentials.hasBridgeToken else {
                showingSettings = true
                return
            }
            await bridge.connect(using: configuration, bearerToken: credentials.bridgeToken)
        }
    }

    private func send() {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        command = ""

        if agent.route == .clever {
            agent.prepareClever(message: trimmed)
            return
        }
        if agent.route == .apple {
            agent.send(message: trimmed, configuration: nil, bearerToken: "")
            return
        }
        guard settings.save(), let configuration = try? settings.configuration(), credentials.hasBridgeToken else {
            command = trimmed
            showingSettings = true
            return
        }
        agent.send(message: trimmed, configuration: configuration, bearerToken: credentials.bridgeToken)
    }
}

enum CarinaTheme {
    static let ink = Color(red: 0.025, green: 0.05, blue: 0.055)
    static let canvas = Color(red: 0.025, green: 0.035, blue: 0.045)
    static let canvasLifted = Color(red: 0.045, green: 0.06, blue: 0.07)
    static let signal = Color(red: 0.45, green: 0.93, blue: 0.83)
    static let signalSoft = signal.opacity(0.11)
    static let control = Color.white.opacity(0.07)
    static let recessed = Color.black.opacity(0.16)
    static let hairline = Color.white.opacity(0.095)
    static let secondaryText = Color.white.opacity(0.58)
    static let muted = Color.white.opacity(0.28)
    static let warning = Color(red: 0.95, green: 0.67, blue: 0.33)
    static let danger = Color(red: 0.88, green: 0.30, blue: 0.32)
}

struct CarinaBackground: View {
    var body: some View {
        ZStack {
            CarinaTheme.canvas.ignoresSafeArea()
            RadialGradient(
                colors: [CarinaTheme.signal.opacity(0.10), .clear],
                center: UnitPoint(x: 0.86, y: 0.02),
                startRadius: 0,
                endRadius: 430
            )
            .ignoresSafeArea()
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.16)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

struct CarinaSurface<Content: View>: View {
    var accent: Color = CarinaTheme.signal
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            styledContent
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            styledContent
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var styledContent: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CarinaTheme.canvasLifted.opacity(0.42), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [accent.opacity(0.30), CarinaTheme.hairline, .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.black.opacity(0.22), radius: 24, y: 12)
    }
}

struct CarinaPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct CarinaCore: View {
    let isActive: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(CarinaTheme.control)
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(CarinaTheme.hairline)
            Circle()
                .stroke(CarinaTheme.signal.opacity(0.2), lineWidth: 12)
                .blur(radius: 8)
                .padding(12)
            Circle()
                .fill(CarinaTheme.signal)
                .frame(width: isActive ? 20 : 12, height: isActive ? 20 : 12)
                .shadow(color: CarinaTheme.signal.opacity(0.9), radius: isActive ? 18 : 9)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isActive)
            Image(systemName: isActive ? "waveform" : "sparkles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(CarinaTheme.ink)
                .symbolEffect(.pulse, isActive: isActive)
        }
    }
}

private struct SectionLabel: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer()
            Text(detail)
                .font(.caption.weight(.medium))
                .foregroundStyle(CarinaTheme.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 3)
    }
}

private struct StatusIndicator: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct NetworkMetric: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(CarinaTheme.signal)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(CarinaTheme.secondaryText)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
    }
}

private struct MessageBubble: View {
    let message: AgentMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 52) }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(message.role == .user ? "You" : (message.agent ?? "CARINA"))
                        .font(.caption.weight(.semibold))
                    if let route = message.route {
                        Image(systemName: route.symbolName)
                            .foregroundStyle(CarinaTheme.signal)
                    }
                    Spacer(minLength: 0)
                    Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2.monospacedDigit())
                }
                .foregroundStyle(CarinaTheme.secondaryText)

                Text(message.text)
                    .font(.body)
                    .textSelection(.enabled)
            }
            .padding(15)
            .background(
                message.role == .user ? CarinaTheme.signalSoft : CarinaTheme.control,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(message.role == .user ? CarinaTheme.signal.opacity(0.18) : CarinaTheme.hairline)
            }

            if message.role != .user { Spacer(minLength: 38) }
        }
    }
}

private struct ErrorBanner: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CarinaTheme.danger.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14).stroke(CarinaTheme.danger.opacity(0.32))
            }
    }
}

extension AgentRoute {
    var symbolName: String {
        switch self {
        case .openclaw: "point.3.connected.trianglepath.dotted"
        case .openai: "sparkles"
        case .ollama: "desktopcomputer"
        case .maya: "map.fill"
        case .hermes: "hammer.fill"
        case .karina: "waveform.badge.mic"
        case .clever: "brain.head.profile.fill"
        case .apple: "apple.intelligence"
        }
    }

    var tint: Color { CarinaTheme.signal }
}
