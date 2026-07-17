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
            List {
                connectionSection
                conversationSection
                if let approval = agent.pendingApproval {
                    approvalSection(approval)
                }
                commandSection
            }
            .navigationTitle("CARINA")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
            }
            .onChange(of: speech.transcript) { _, transcript in command = transcript }
            .sheet(isPresented: $showingSettings) {
                SettingsView(settings: settings, permissions: permissions, credentials: credentials)
            }
        }
    }

    private var connectionSection: some View {
        Section("Agent Network") {
            Picker("Route", selection: $agent.route) {
                ForEach(AgentRoute.allCases) { route in
                    Text(route.displayName).tag(route)
                }
            }
            LabeledContent("Agent", value: agent.state.label)
            LabeledContent("Mac bridge", value: bridge.state.label)
            LabeledContent("WebSocket", value: String(BridgeConfiguration.webSocketPort))
            LabeledContent("Credentials", value: credentials.hasBridgeToken ? "Keychain" : "Setup required")

            Button("Connect and Check Bridge") {
                Task {
                    guard settings.save(), let configuration = try? settings.configuration() else {
                        showingSettings = true
                        return
                    }
                    guard credentials.hasBridgeToken else {
                        showingSettings = true
                        return
                    }
                    await bridge.connect(using: configuration, bearerToken: credentials.bridgeToken)
                }
            }
            .disabled(bridge.state == .connecting)

            if !bridge.lastMessage.isEmpty {
                Text(bridge.lastMessage)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }
        }
    }

    private var conversationSection: some View {
        Section("Conversation") {
            if agent.messages.isEmpty {
                ContentUnavailableView(
                    "Ready for OpenClaw",
                    systemImage: "sparkles",
                    description: Text("CARINA routes through your Mac or hands prompts to Clever AI on this iPhone.")
                )
            } else {
                ForEach(agent.messages) { message in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(message.role == .user ? "You" : (message.agent ?? "CARINA"))
                                .font(.caption.weight(.semibold))
                            Spacer()
                            if let route = message.route {
                                Text(route.displayName).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Text(message.text).textSelection(.enabled)
                    }
                    .padding(.vertical, 3)
                }
            }
            if agent.state == .sending {
                HStack { ProgressView(); Text("Routing through \(agent.route.displayName)…") }
            }
        }
    }

    private func approvalSection(_ approval: PreparedAction) -> some View {
        Section("Approval Required") {
            Label(approval.summary, systemImage: "exclamationmark.shield")
                .foregroundStyle(.orange)
            LabeledContent("Command", value: approval.command)
            LabeledContent("Expires", value: approval.expiresAt.formatted(date: .omitted, time: .standard))
            if !approval.payload.isEmpty {
                Text(approval.payload.keys.sorted().map { "\($0): \(approval.payload[$0] ?? "")" }.joined(separator: "\n"))
                    .font(.footnote.monospaced())
            }
            HStack {
                Button("Deny", role: .destructive) { agent.deny() }
                Spacer()
                Button("Approve Once") {
                    agent.approve(configuration: try? settings.configuration(), bearerToken: credentials.bridgeToken)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var commandSection: some View {
        Section("Message") {
            TextField("Ask CARINA", text: $command, axis: .vertical)
                .lineLimit(2...6)

            HStack {
                Button(speech.isListening ? "Stop" : "Speak", systemImage: speech.isListening ? "stop.circle" : "mic") {
                    Task {
                        if speech.isListening { speech.stop() } else { await speech.start() }
                    }
                }

                if agent.state == .sending {
                    Button("Cancel", systemImage: "xmark.circle", role: .cancel) { agent.cancel() }
                }

                Spacer()

                Button("Send", systemImage: "arrow.up.circle.fill") { send() }
                    .buttonStyle(.borderedProminent)
                    .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || agent.state == .sending)
            }

            if let error = speech.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            if case .failed(let error) = agent.state {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private func send() {
        if agent.route == .clever {
            let message = command
            command = ""
            agent.prepareClever(message: message)
            return
        }
        guard settings.save(), let configuration = try? settings.configuration(), credentials.hasBridgeToken else {
            showingSettings = true
            return
        }
        let message = command
        command = ""
        agent.send(message: message, configuration: configuration, bearerToken: credentials.bridgeToken)
    }
}
