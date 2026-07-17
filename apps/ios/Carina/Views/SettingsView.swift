import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: BridgeSettings
    @ObservedObject var permissions: PermissionManager
    @ObservedObject var credentials: CredentialManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac / OpenClaw Bridge") {
                    TextField("Mac LAN or Tailscale address", text: $settings.host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Bridge bearer token", text: $credentials.bridgeToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    LabeledContent("HTTP port", value: String(BridgeConfiguration.httpPort))
                    LabeledContent("WebSocket port", value: String(BridgeConfiguration.webSocketPort))
                    Text("The OpenAI key stays on the Mac. This iPhone stores only the bridge token in this device's Keychain.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let message = settings.validationMessage ?? credentials.errorMessage {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }
                    if credentials.hasBridgeToken {
                        Button("Remove Saved Bridge Token", role: .destructive) {
                            Task { await credentials.delete() }
                        }
                    }
                }

                Section("Permissions") {
                    LabeledContent("Microphone", value: permissions.microphone.rawValue)
                    LabeledContent("Speech Recognition", value: permissions.speechRecognition.rawValue)
                    Text("Local Network access is requested on first connection. App Intents appear in Shortcuts after installation. Execute commands always require confirmation.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Development Transport") {
                    Text("Local HTTP and WebSocket traffic is allowed only for the authenticated Mac bridge development path. OpenAI requests originate on the Mac over HTTPS.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("CARINA Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            let hostSaved = settings.save()
                            let tokenSaved = await credentials.save()
                            if hostSaved && tokenSaved { dismiss() }
                        }
                    }
                }
            }
            .onAppear { permissions.refresh() }
        }
    }
}
