import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: BridgeSettings
    @ObservedObject var permissions: PermissionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Mac Bridge") {
                    TextField("Mac LAN or Tailscale address", text: $settings.host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    LabeledContent("HTTP port", value: String(BridgeConfiguration.httpPort))
                    LabeledContent("WebSocket port", value: String(BridgeConfiguration.webSocketPort))
                    Text("Use the Mac's LAN address, .local name, or Tailscale address. Loopback addresses are rejected because they point to the iPhone itself.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let message = settings.validationMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("Permissions") {
                    LabeledContent("Microphone", value: permissions.microphone.rawValue)
                    LabeledContent("Speech Recognition", value: permissions.speechRecognition.rawValue)
                    Text("Local Network access is requested by iOS when CARINA first connects to the Mac bridge. App Intents appear automatically in Shortcuts after installation.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Development Transport Security") {
                    Text("Local HTTP and WebSocket traffic is enabled for development. Use a trusted LAN or Tailscale network and migrate the bridge to TLS before public distribution.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("CARINA Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if settings.save() {
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                permissions.refresh()
            }
        }
    }
}
