import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: BridgeSettings
    @EnvironmentObject private var bridge: BridgeClient
    @EnvironmentObject private var speech: SpeechRecognitionService
    @EnvironmentObject private var permissions: PermissionManager

    @State private var command = ""
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section("Bridge") {
                    LabeledContent("Status", value: bridge.state.label)
                    LabeledContent("HTTP", value: String(BridgeConfiguration.httpPort))
                    LabeledContent("WebSocket", value: String(BridgeConfiguration.webSocketPort))

                    Button("Connect to Mac") {
                        Task {
                            guard settings.save(), let configuration = try? settings.configuration() else {
                                showingSettings = true
                                return
                            }
                            await bridge.connect(using: configuration)
                        }
                    }
                    .disabled(bridge.state == .connecting)

                    if !bridge.lastMessage.isEmpty {
                        Text(bridge.lastMessage)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                }

                Section("Command") {
                    TextField("Ask CARINA", text: $command, axis: .vertical)
                        .lineLimit(2...6)

                    HStack {
                        Button(speech.isListening ? "Stop Listening" : "Speak") {
                            Task {
                                if speech.isListening {
                                    speech.stop()
                                } else {
                                    await speech.start()
                                }
                            }
                        }

                        Spacer()

                        Button("Send") {
                            Task {
                                await bridge.send(command: command)
                                command = ""
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if let error = speech.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("CARINA")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") {
                        showingSettings = true
                    }
                }
            }
            .onChange(of: speech.transcript) { _, transcript in
                command = transcript
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(settings: settings, permissions: permissions)
            }
        }
    }
}
