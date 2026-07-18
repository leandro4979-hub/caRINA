import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: BridgeSettings
    @ObservedObject var permissions: PermissionManager
    @ObservedObject var credentials: CredentialManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                CarinaBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        identityCard
                        bridgeCard
                        permissionsCard
                        securityCard
                        saveButton
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear { permissions.refresh() }
        }
        .preferredColorScheme(.dark)
    }

    private var identityCard: some View {
        CarinaSurface(accent: .cyan) {
            HStack(spacing: 15) {
                Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.cyan)
                    .frame(width: 54, height: 54)
                    .background(Color.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 17))
                VStack(alignment: .leading, spacing: 4) {
                    Text("CARINA SECURE LINK")
                        .font(.caption.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(.cyan)
                    Text("Your AI keys never live in this app.")
                        .font(.headline)
                    Text("Only the device bridge token is stored in Keychain.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var bridgeCard: some View {
        CarinaSurface {
            VStack(alignment: .leading, spacing: 15) {
                Label("Mac + OpenClaw Bridge", systemImage: "macbook.and.iphone")
                    .font(.headline)

                fieldLabel("MAC LAN OR TAILSCALE ADDRESS")
                TextField("leandros-MacBook-Air.local", text: $settings.host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(13)
                    .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 14))

                fieldLabel("BRIDGE TOKEN")
                SecureField("Paste the device bridge token", text: $credentials.bridgeToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(13)
                    .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 14))

                HStack(spacing: 10) {
                    portMetric("HTTP", BridgeConfiguration.httpPort)
                    portMetric("WebSocket", BridgeConfiguration.webSocketPort)
                }

                if let message = settings.validationMessage ?? credentials.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if credentials.hasBridgeToken {
                    Button(role: .destructive) {
                        Task { await credentials.delete() }
                    } label: {
                        Label("Remove Saved Bridge Token", systemImage: "trash")
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private var permissionsCard: some View {
        CarinaSurface(accent: .purple) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Device Permissions", systemImage: "hand.raised.fill")
                    .font(.headline)
                permissionRow("Microphone", icon: "mic.fill", value: permissions.microphone.rawValue)
                Divider().opacity(0.25)
                permissionRow("Speech Recognition", icon: "waveform", value: permissions.speechRecognition.rawValue)
                Divider().opacity(0.25)
                permissionRow("Local Network", icon: "network", value: "Requested on connect")
                Divider().opacity(0.25)
                permissionRow("App Intents", icon: "shortcuts", value: "Available in Shortcuts")
                Text("Execute commands always pause for your explicit approval.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var securityCard: some View {
        CarinaSurface(accent: .green) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Transport Security", systemImage: "lock.shield.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text("Local HTTP and WebSocket access is limited to the authenticated Mac development bridge. OpenAI requests originate on your Mac over HTTPS.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var saveButton: some View {
        Button {
            Task {
                let hostSaved = settings.save()
                let tokenSaved = await credentials.save()
                if hostSaved && tokenSaved { dismiss() }
            }
        } label: {
            Label("Save Secure Connection", systemImage: "checkmark.shield.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    LinearGradient(colors: [.indigo, .purple], startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 18)
                )
        }
        .buttonStyle(.plain)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .tracking(1)
            .foregroundStyle(.secondary)
    }

    private func portMetric(_ title: String, _ port: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(String(port)).font(.subheadline.monospacedDigit().weight(.semibold))
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
    }

    private func permissionRow(_ title: String, icon: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.purple)
                .frame(width: 24)
            Text(title).font(.subheadline.weight(.medium))
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
