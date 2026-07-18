import SwiftUI

private enum CarinaArea: String, CaseIterable, Identifiable {
    case conversation
    case control

    var id: String { rawValue }

    var label: String {
        switch self {
        case .conversation: "Conversation"
        case .control: "Control"
        }
    }

    var symbol: String {
        switch self {
        case .conversation: "waveform"
        case .control: "switch.2"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var settings: BridgeSettings
    @EnvironmentObject private var bridge: BridgeClient
    @EnvironmentObject private var credentials: CredentialManager
    @EnvironmentObject private var agent: CarinaAgentService
    @EnvironmentObject private var speech: SpeechRecognitionService
    @EnvironmentObject private var voice: NativeVoiceSynthesisService
    @EnvironmentObject private var permissions: PermissionManager

    @AppStorage("carina.autoSpeakResponses") private var autoSpeakResponses = true
    @State private var area: CarinaArea = .conversation
    @State private var command = ""
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            ZStack {
                CarinaBackground()

                ScrollView {
                    LazyVStack(spacing: 24) {
                        if area == .conversation {
                            conversationHome
                        } else {
                            controlHome
                        }
                        Color.clear.frame(height: area == .conversation ? 176 : 88)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar { navigationToolbar }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomDock }
            .sheet(isPresented: $showingSettings) {
                SettingsView(settings: settings, permissions: permissions, credentials: credentials)
            }
            .onChange(of: speech.transcript) { _, transcript in command = transcript }
            .onChange(of: agent.messages.count) { _, _ in speakLatestResponseIfNeeded() }
        }
        .preferredColorScheme(.dark)
    }

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 9) {
                Circle()
                    .fill(bridge.state == .connected ? CarinaTheme.signal : CarinaTheme.muted)
                    .frame(width: 7, height: 7)
                    .shadow(color: bridge.state == .connected ? CarinaTheme.signal.opacity(0.7) : .clear, radius: 6)
                Text("CARINA")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .tracking(2.6)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("CARINA, \(bridge.state == .connected ? "connected" : "offline")")
        }

        ToolbarItem(placement: .principal) {
            Menu {
                delegateButton(nil)
                Divider()
                ForEach(CarinaDelegate.allCases) { delegate in delegateButton(delegate) }
            } label: {
                HStack(spacing: 6) {
                    Text(agent.selectedDelegate?.displayName ?? "CARINA")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(CarinaTheme.secondaryText)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 38)
                .background(CarinaTheme.control, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .accessibilityLabel("Choose CARINA delegate")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button { showingSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(CarinaTheme.control, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(CarinaPressButtonStyle())
            .accessibilityLabel("CARINA settings")
        }
    }

    @ViewBuilder
    private func delegateButton(_ delegate: CarinaDelegate?) -> some View {
        Button {
            agent.selectedDelegate = delegate
        } label: {
            Label(
                delegate?.displayName ?? "CARINA direct",
                systemImage: delegate?.symbolName ?? "sparkles"
            )
        }
    }

    private var conversationHome: some View {
        VStack(spacing: 26) {
            VStack(spacing: 11) {
                Text(voiceState.label.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(voiceState == .failed ? CarinaTheme.danger : CarinaTheme.signal)

                Text(conversationTitle)
                    .font(.system(size: 46, weight: .regular, design: .serif))
                    .tracking(-1.4)
                    .multilineTextAlignment(.center)
                    .lineSpacing(-5)
                    .accessibilityAddTraits(.isHeader)

                Text(delegationLine)
                    .font(.subheadline)
                    .foregroundStyle(CarinaTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 10)

            CarinaPresence(state: voiceState)
                .frame(width: 210, height: 210)
                .accessibilityLabel("CARINA is \(voiceState.label.lowercased())")

            liveThought
            delegateRail

            if let approval = agent.pendingApproval {
                approvalPanel(approval)
            }

            recentConversation
            inlineErrors
        }
    }

    private var liveThought: some View {
        Group {
            if speech.isListening {
                CarinaSurface(accent: CarinaTheme.signal) {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("Live transcript", systemImage: "waveform")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CarinaTheme.signal)
                        Text(speech.transcript.isEmpty ? "I’m listening…" : speech.transcript)
                            .font(.system(.title3, design: .serif))
                            .foregroundStyle(speech.transcript.isEmpty ? CarinaTheme.secondaryText : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else if let latest = agent.messages.last, latest.role == .assistant {
                CarinaSurface {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("CARINA")
                                .font(.caption.weight(.bold))
                                .tracking(1.2)
                            if let route = latest.route, let delegate = route.delegate {
                                Text("with \(delegate.displayName)")
                                    .font(.caption)
                                    .foregroundStyle(CarinaTheme.secondaryText)
                            }
                        }
                        Text(latest.text)
                            .font(.system(.body, design: .serif))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                }
            } else {
                Text("Speak naturally or type below. CARINA can bring in a specialist without handing away the conversation.")
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(CarinaTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 14)
            }
        }
    }

    private var delegateRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Bring in", detail: "CARINA stays with you")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    delegateChip(nil, title: "Just CARINA", symbol: "sparkles")
                    ForEach(CarinaDelegate.allCases) { delegate in
                        delegateChip(delegate, title: delegate.displayName, symbol: delegate.symbolName)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private func delegateChip(_ delegate: CarinaDelegate?, title: String, symbol: String) -> some View {
        let selected = agent.selectedDelegate == delegate
        return Button {
            withAnimation(.snappy(duration: 0.24)) { agent.selectedDelegate = delegate }
        } label: {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? CarinaTheme.ink : .primary)
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .background(
                    selected ? CarinaTheme.signal : CarinaTheme.control,
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(selected ? CarinaTheme.signal : CarinaTheme.hairline)
                }
        }
        .buttonStyle(CarinaPressButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var recentConversation: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !agent.messages.isEmpty {
                SectionLabel(title: "Conversation", detail: "CARINA")
                ForEach(agent.messages.suffix(6)) { message in MessageBubble(message: message) }
            }
        }
    }

    private var controlHome: some View {
        VStack(spacing: 22) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CARINA CONTROL")
                        .font(.caption2.weight(.bold))
                        .tracking(1.8)
                        .foregroundStyle(CarinaTheme.signal)
                    Text("The network\nbehind her voice.")
                        .font(.system(size: 34, weight: .regular, design: .serif))
                        .tracking(-0.8)
                        .lineSpacing(-3)
                }
                Spacer()
                StatusIndicator(
                    text: bridge.state == .connected ? "Connected" : bridge.state.label,
                    color: bridge.state == .connected ? CarinaTheme.signal : CarinaTheme.warning
                )
            }

            providerSelector
            delegateControl
            connectionPanel

            if let approval = agent.pendingApproval { approvalPanel(approval) }

            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(title: "Transcript", detail: "\(agent.messages.count) messages")
                if agent.messages.isEmpty {
                    CarinaSurface {
                        Text("Conversation activity will appear here with its provider and delegate source.")
                            .font(.body)
                            .foregroundStyle(CarinaTheme.secondaryText)
                    }
                } else {
                    ForEach(agent.messages) { message in MessageBubble(message: message) }
                }
            }
            inlineErrors
        }
    }

    private var providerSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Provider", detail: "How CARINA reasons")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(ProviderRoute.allCases) { provider in
                        let selected = agent.providerRoute == provider
                        Button {
                            withAnimation(.snappy(duration: 0.24)) { agent.providerRoute = provider }
                        } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                Image(systemName: provider.symbolName)
                                    .font(.subheadline.weight(.semibold))
                                Text(provider.displayName)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(selected ? CarinaTheme.ink : .primary)
                            .frame(width: 104, height: 62, alignment: .leading)
                            .padding(.horizontal, 14)
                            .background(
                                selected ? CarinaTheme.signal : CarinaTheme.control,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                        }
                        .buttonStyle(CarinaPressButtonStyle())
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private var delegateControl: some View {
        CarinaSurface {
            HStack(spacing: 14) {
                Image(systemName: agent.selectedDelegate?.symbolName ?? "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(CarinaTheme.signal)
                    .frame(width: 48, height: 48)
                    .background(CarinaTheme.signalSoft, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("CARINA is primary")
                        .font(.headline)
                    Text(delegationLine)
                        .font(.footnote)
                        .foregroundStyle(CarinaTheme.secondaryText)
                }
                Spacer()
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
                    NetworkMetric(title: "Mac bridge", value: bridge.state.label, icon: "macbook")
                    Rectangle().fill(CarinaTheme.hairline).frame(width: 1, height: 38)
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

                Toggle("Speak CARINA responses", isOn: $autoSpeakResponses)
                    .font(.subheadline.weight(.medium))
                    .tint(CarinaTheme.signal)

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

    @ViewBuilder
    private var inlineErrors: some View {
        if case .failed(let error) = agent.state { ErrorBanner(text: error) }
        if let error = speech.errorMessage { ErrorBanner(text: error) }
        if let error = voice.errorMessage { ErrorBanner(text: error) }
    }

    private var bottomDock: some View {
        VStack(spacing: 10) {
            if area == .conversation { composer }
            areaSwitcher
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 7)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(CarinaTheme.hairline).frame(height: 1) }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 9) {
            Button(action: toggleListening) {
                Image(systemName: speech.isListening ? "stop.fill" : "waveform")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .foregroundStyle(speech.isListening ? .white : CarinaTheme.signal)
                    .background(
                        speech.isListening ? CarinaTheme.danger : CarinaTheme.control,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
            }
            .buttonStyle(CarinaPressButtonStyle())
            .accessibilityLabel(speech.isListening ? "Stop listening" : "Talk to CARINA")

            TextField("Message CARINA", text: $command, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(.horizontal, 15)
                .padding(.vertical, 14)
                .background(CarinaTheme.control, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 17).stroke(CarinaTheme.hairline) }
                .submitLabel(.send)
                .onSubmit(send)

            Button {
                agent.state == .sending || voice.isSpeaking ? stopAll() : send()
            } label: {
                Image(systemName: agent.state == .sending || voice.isSpeaking ? "stop.fill" : "arrow.up")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 48, height: 48)
                    .foregroundStyle(CarinaTheme.ink)
                    .background(CarinaTheme.signal, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(CarinaPressButtonStyle())
            .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && agent.state != .sending && !voice.isSpeaking)
            .opacity(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && agent.state != .sending && !voice.isSpeaking ? 0.42 : 1)
            .accessibilityLabel(agent.state == .sending || voice.isSpeaking ? "Stop CARINA" : "Send to CARINA")
        }
    }

    private var areaSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(CarinaArea.allCases) { destination in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { area = destination }
                } label: {
                    Label(destination.label, systemImage: destination.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(area == destination ? CarinaTheme.ink : CarinaTheme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(
                            area == destination ? CarinaTheme.signal : .clear,
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                }
                .buttonStyle(CarinaPressButtonStyle())
                .accessibilityAddTraits(area == destination ? .isSelected : [])
            }
        }
        .padding(4)
        .background(CarinaTheme.recessed, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }

    private var voiceState: VoiceSessionState {
        VoiceSessionState.resolve(
            isListening: speech.isListening,
            transcript: speech.transcript,
            isThinking: agent.state == .sending,
            isSpeaking: voice.isSpeaking,
            wasInterrupted: voice.wasInterrupted,
            hasError: speech.errorMessage != nil || voice.errorMessage != nil || agentFailed
        )
    }

    private var agentFailed: Bool {
        if case .failed = agent.state { return true }
        return false
    }

    private var conversationTitle: String {
        switch voiceState {
        case .listening, .transcribing: "I’m listening."
        case .thinking: "Let me think."
        case .speaking: "Here with you."
        case .interrupted: "We can pause."
        case .failed: "Let’s reconnect."
        case .idle: "Talk it through."
        }
    }

    private var delegationLine: String {
        guard let delegate = agent.selectedDelegate else {
            return "CARINA is handling this directly with \(agent.providerRoute.displayName)."
        }
        switch delegate {
        case .maya: return "CARINA is planning with Maya through \(agent.providerRoute.displayName)."
        case .hermes: return "CARINA is asking Hermes for read-only system help."
        case .karina: return "CARINA is working with Karina on voice and device-safe actions."
        case .clever: return "CARINA will prepare an approved handoff to Clever AI."
        }
    }

    private var connectionSummary: String {
        switch bridge.state {
        case .connected: "Mac bridge and live agent channel are ready."
        case .connecting: "Checking HTTP and WebSocket channels…"
        default: "Connect securely to OpenClaw and your local agents."
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

    private func toggleListening() {
        if speech.isListening {
            speech.stop()
            return
        }
        voice.stop()
        voice.clearInterruption()
        Task { await speech.start() }
    }

    private func stopAll() {
        speech.stop()
        voice.stop()
        agent.cancel()
    }

    private func send() {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        command = ""
        speech.stop()
        voice.stop()
        voice.clearInterruption()

        if agent.selectedDelegate == .clever {
            agent.prepareClever(message: trimmed)
            return
        }
        if agent.providerRoute == .apple {
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

    private func speakLatestResponseIfNeeded() {
        guard autoSpeakResponses, area == .conversation,
              let message = agent.messages.last,
              message.role == .assistant else { return }
        voice.speak(message.text)
    }
}

enum CarinaTheme {
    static let ink = Color(red: 0.10, green: 0.045, blue: 0.065)
    static let canvas = Color(red: 0.055, green: 0.022, blue: 0.035)
    static let canvasLifted = Color(red: 0.105, green: 0.045, blue: 0.065)
    static let signal = Color(red: 0.91, green: 0.79, blue: 0.64)
    static let signalSoft = signal.opacity(0.12)
    static let control = Color.white.opacity(0.075)
    static let recessed = Color.black.opacity(0.17)
    static let hairline = Color.white.opacity(0.10)
    static let secondaryText = Color.white.opacity(0.62)
    static let muted = Color.white.opacity(0.30)
    static let warning = Color(red: 0.96, green: 0.67, blue: 0.34)
    static let danger = Color(red: 0.90, green: 0.32, blue: 0.34)
}

struct CarinaBackground: View {
    var body: some View {
        ZStack {
            CarinaTheme.canvas.ignoresSafeArea()
            RadialGradient(
                colors: [Color(red: 0.33, green: 0.10, blue: 0.16).opacity(0.78), .clear],
                center: UnitPoint(x: 0.82, y: 0.02),
                startRadius: 0,
                endRadius: 470
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [CarinaTheme.signal.opacity(0.07), .clear],
                center: UnitPoint(x: 0.08, y: 0.78),
                startRadius: 0,
                endRadius: 360
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
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        } else {
            styledContent
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        }
    }

    private var styledContent: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CarinaTheme.canvasLifted.opacity(0.44), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [accent.opacity(0.28), CarinaTheme.hairline, .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .shadow(color: CarinaTheme.canvas.opacity(0.62), radius: 24, y: 12)
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

private struct CarinaPresence: View {
    let state: VoiceSessionState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var active: Bool {
        [.listening, .transcribing, .thinking, .speaking].contains(state)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(CarinaTheme.signal.opacity(0.045))
                .overlay { Circle().stroke(CarinaTheme.signal.opacity(0.10)) }
            Circle()
                .fill(
                    RadialGradient(
                        colors: [CarinaTheme.signal, CarinaTheme.signal.opacity(0.15), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 74
                    )
                )
                .frame(width: active ? 150 : 122, height: active ? 150 : 122)
                .blur(radius: active ? 2 : 7)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.15).repeatForever(autoreverses: true), value: active)
            Circle()
                .fill(CarinaTheme.signal)
                .frame(width: active ? 54 : 42, height: active ? 54 : 42)
                .shadow(color: CarinaTheme.signal.opacity(0.75), radius: active ? 30 : 17)
            Image(systemName: state.symbolName)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(CarinaTheme.ink)
                .symbolEffect(.pulse, isActive: active && !reduceMotion)
        }
    }
}

private struct SectionLabel: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
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
                    Text(message.role == .user ? "You" : "CARINA")
                        .font(.caption.weight(.semibold))
                    if message.role != .user, let route = message.route, let delegate = route.delegate {
                        Text("with \(delegate.displayName)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(CarinaTheme.signal)
                    }
                    Spacer(minLength: 0)
                    Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2.monospacedDigit())
                }
                .foregroundStyle(CarinaTheme.secondaryText)
                Text(message.text)
                    .font(.body)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
            .padding(15)
            .background(
                message.role == .user ? CarinaTheme.signalSoft : CarinaTheme.control,
                in: RoundedRectangle(cornerRadius: 19, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 19)
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
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(CarinaTheme.danger.opacity(0.32)) }
    }
}

extension ProviderRoute {
    var symbolName: String {
        switch self {
        case .openclaw: "point.3.connected.trianglepath.dotted"
        case .openai: "sparkles"
        case .ollama: "desktopcomputer"
        case .apple: "apple.intelligence"
        }
    }
}

extension CarinaDelegate {
    var symbolName: String {
        switch self {
        case .maya: "map.fill"
        case .hermes: "hammer.fill"
        case .karina: "waveform.badge.mic"
        case .clever: "brain.head.profile.fill"
        }
    }
}

extension VoiceSessionState {
    var symbolName: String {
        switch self {
        case .idle: "sparkles"
        case .listening, .transcribing: "waveform"
        case .thinking: "ellipsis"
        case .speaking: "speaker.wave.2.fill"
        case .interrupted: "pause.fill"
        case .failed: "exclamationmark"
        }
    }
}
