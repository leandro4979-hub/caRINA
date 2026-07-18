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
                    LazyVStack(spacing: 18) {
                        hero
                        routeSelector
                        connectionPanel
                        conversationPanel
                        if let approval = agent.pendingApproval {
                            approvalPanel(approval)
                        }
                        Color.clear.frame(height: 116)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("CARINA")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .tracking(2.2)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.headline)
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.plain)
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
        CarinaSurface {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [.cyan, .indigo, .purple, .cyan],
                                center: .center
                            )
                        )
                        .blur(radius: agent.state == .sending ? 8 : 3)
                    Circle()
                        .fill(Color(red: 0.035, green: 0.055, blue: 0.12))
                        .padding(5)
                    Image(systemName: agent.state == .sending ? "waveform" : "sparkles")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, isActive: agent.state == .sending)
                }
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text(agent.state == .sending ? "CARINA IS THINKING" : "CARINA COMMAND CORE")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(.cyan)
                    Text(agent.state.label)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .lineLimit(2)
                    Text(routeDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var routeSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CHOOSE THE BRAIN")
                .font(.caption2.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(AgentRoute.allCases) { route in
                        Button {
                            withAnimation(.snappy) { agent.route = route }
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: route.symbolName)
                                Text(route.displayName)
                                    .lineLimit(1)
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(agent.route == route ? .white : .secondary)
                            .padding(.horizontal, 14)
                            .frame(height: 42)
                            .background(
                                agent.route == route ? route.tint.opacity(0.7) : Color.white.opacity(0.07),
                                in: Capsule()
                            )
                            .overlay(Capsule().stroke(route.tint.opacity(agent.route == route ? 0.9 : 0.2)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private var connectionPanel: some View {
        CarinaSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Agent Network", systemImage: "network")
                        .font(.headline)
                    Spacer()
                    StatusPill(
                        text: bridge.state == .connected ? "LIVE" : "OFFLINE",
                        color: bridge.state == .connected ? .green : .orange
                    )
                }

                HStack(spacing: 10) {
                    NetworkMetric(title: "Mac Bridge", value: bridge.state.label, icon: "desktopcomputer")
                    NetworkMetric(
                        title: "Secure Token",
                        value: credentials.hasBridgeToken ? "Keychain" : "Setup",
                        icon: credentials.hasBridgeToken ? "lock.fill" : "key"
                    )
                }

                Button(action: connect) {
                    HStack {
                        if bridge.state == .connecting { ProgressView().tint(.white) }
                        Image(systemName: bridge.state == .connected ? "checkmark.circle.fill" : "bolt.horizontal.circle.fill")
                        Text(bridge.state == .connected ? "Refresh Connection" : "Connect Mac + OpenClaw")
                        Spacer()
                        Text("(BridgeConfiguration.httpPort) / (BridgeConfiguration.webSocketPort)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(Color.indigo.opacity(0.72), in: RoundedRectangle(cornerRadius: 15))
                }
                .buttonStyle(.plain)
                .disabled(bridge.state == .connecting)

                if !bridge.lastMessage.isEmpty {
                    Text(bridge.lastMessage)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var conversationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Conversation", systemImage: "message.fill")
                    .font(.headline)
                Spacer()
                Text(agent.route.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(agent.route.tint)
            }
            .padding(.horizontal, 4)

            if agent.messages.isEmpty {
                CarinaSurface {
                    VStack(spacing: 12) {
                        Image(systemName: agent.route.symbolName)
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(agent.route.tint)
                        Text("Ready for (agent.route.displayName)")
                            .font(.title3.weight(.bold))
                        Text(emptyConversationDetail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
            } else {
                ForEach(agent.messages) { message in
                    MessageBubble(message: message)
                }
            }

            if agent.state == .sending {
                HStack(spacing: 10) {
                    ProgressView().tint(agent.route.tint)
                    Text("Routing through (agent.route.displayName)…")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6)
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
        CarinaSurface(accent: .orange) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("APPROVAL REQUIRED")
                            .font(.caption.weight(.bold))
                            .tracking(1.2)
                            .foregroundStyle(.orange)
                        Text(approval.summary).font(.headline)
                    }
                    Spacer()
                }
                HStack {
                    Label(approval.command, systemImage: "terminal")
                    Spacer()
                    Label(approval.expiresAt.formatted(date: .omitted, time: .shortened), systemImage: "timer")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if !approval.payload.isEmpty {
                    Text(approval.payload.keys.sorted().map { "\($0): \(approval.payload[$0] ?? "")" }.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                }

                HStack(spacing: 12) {
                    Button("Deny", role: .destructive) { agent.deny() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                    Button("Approve Once") {
                        agent.approve(configuration: try? settings.configuration(), bearerToken: credentials.bridgeToken)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    Task { speech.isListening ? speech.stop() : await speech.start() }
                } label: {
                    Image(systemName: speech.isListening ? "stop.fill" : "mic.fill")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(speech.isListening ? Color.red.opacity(0.8) : Color.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(speech.isListening ? "Stop listening" : "Speak")

                TextField("Ask (agent.route.displayName)…", text: $command, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 20))
                    .submitLabel(.send)
                    .onSubmit(send)

                Button {
                    agent.state == .sending ? agent.cancel() : send()
                } label: {
                    Image(systemName: agent.state == .sending ? "xmark" : "arrow.up")
                        .font(.headline.weight(.bold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(.white)
                        .background(agent.route.tint, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && agent.state != .sending)
                .accessibilityLabel(agent.state == .sending ? "Cancel" : "Send")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.3) }
    }

    private var routeDetail: String {
        switch agent.route {
        case .apple: "Private on-device reasoning · no API usage"
        case .clever: "Secure handoff to your Clever AI subscription"
        case .ollama: "Local model through your authenticated Mac"
        case .openclaw: "Orchestrating Maya, Hermes, Karina and tools"
        default: "Active route: \(agent.route.displayName)"
        }
    }

    private var emptyConversationDetail: String {
        switch agent.route {
        case .apple: "Runs with Apple’s on-device Foundation Model when available."
        case .clever: "CARINA copies your prompt and opens Clever AI after one approval."
        case .openclaw: "Connect your Mac bridge to reach agents, tools and local models."
        default: "Your request stays on the selected route and every execute action still needs approval."
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

struct CarinaBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.018, green: 0.027, blue: 0.065).ignoresSafeArea()
            RadialGradient(
                colors: [Color.indigo.opacity(0.32), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 520
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [Color.cyan.opacity(0.12), .clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 420
            )
            .ignoresSafeArea()
        }
    }
}

struct CarinaSurface<Content: View>: View {
    var accent: Color = .indigo
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            content
                .padding(17)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(accent.opacity(0.22)))
        } else {
            content
                .padding(17)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26).stroke(accent.opacity(0.22)))
        }
    }
}

private struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
        }
        .font(.caption2.weight(.bold))
        .tracking(0.8)
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
    }
}

private struct NetworkMetric: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.caption.weight(.semibold)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct MessageBubble: View {
    let message: AgentMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 46) }
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(message.role == .user ? "YOU" : (message.agent ?? "CARINA").uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                    if let route = message.route {
                        Image(systemName: route.symbolName).foregroundStyle(route.tint)
                    }
                }
                .foregroundStyle(.secondary)
                Text(message.text)
                    .font(.body)
                    .textSelection(.enabled)
            }
            .padding(14)
            .background(
                message.role == .user ? Color.indigo.opacity(0.38) : Color.white.opacity(0.075),
                in: RoundedRectangle(cornerRadius: 19, style: .continuous)
            )
            if message.role != .user { Spacer(minLength: 34) }
        }
    }
}

private struct ErrorBanner: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
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

    var tint: Color {
        switch self {
        case .openclaw: .cyan
        case .openai: .green
        case .ollama: .mint
        case .maya: .purple
        case .hermes: .orange
        case .karina: .pink
        case .clever: .blue
        case .apple: .indigo
        }
    }
}
