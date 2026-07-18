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
                    VStack(spacing: 20) {
                        identityHeader
                        bridgeSection
                        permissionsSection
                        securitySection
                        saveButton
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 30)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Secure link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(CarinaTheme.signal)
                }
            }
            .onAppear { permissions.refresh() }
        }
        .preferredColorScheme(.dark)
    }

    private var identityHeader: some View {
        HStack(alignment: .center, spacing: 15) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(CarinaTheme.ink)
                .frame(width: 54, height: 54)
                .background(CarinaTheme.signal, in: RoundedRectangle(cornerRadius: 17, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text("Private by design")
                    .font(.title3.weight(.semibold))
                Text("The iPhone stores only the bridge token. Provider keys remain on your Mac.")
                    .font(.footnote)
                    .foregroundStyle(CarinaTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
    }

    private var bridgeSection: some View {
        SettingsSection(title: "Mac bridge", detail: "Local or Tailscale address", symbol: "macbook.and.iphone") {
            VStack(alignment: .leading, spacing: 16) {
                fieldLabel("Host address")
                TextField("leandros-MacBook-Air.local", text: $settings.host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .background(CarinaTheme.recessed, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(CarinaTheme.hairline)
                    }
                    .accessibilityLabel("Mac LAN or Tailscale address")

                fieldLabel("Device bridge token")
                SecureField("Paste the current bridge token", text: $credentials.bridgeToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .background(CarinaTheme.recessed, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(CarinaTheme.hairline)
                    }
                    .accessibilityLabel("Bridge token")

                HStack(spacing: 10) {
                    portMetric("HTTP", BridgeConfiguration.httpPort)
                    portMetric("WebSocket", BridgeConfiguration.webSocketPort)
                }

                if let message = settings.validationMessage ?? credentials.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(CarinaTheme.warning)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CarinaTheme.warning.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                }

                if credentials.hasBridgeToken {
                    Button(role: .destructive) {
                        Task { await credentials.delete() }
                    } label: {
                        Label("Remove saved bridge token", systemImage: "trash")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(CarinaTheme.danger)
                    .accessibilityHint("Removes the device token from Keychain")
                }
            }
        }
    }

    private var permissionsSection: some View {
        SettingsSection(title: "Device access", detail: "Granted by iOS", symbol: "hand.raised.fill") {
            VStack(spacing: 0) {
                permissionRow("Microphone", icon: "mic.fill", value: permissions.microphone.rawValue)
                separator
                permissionRow("Speech recognition", icon: "waveform", value: permissions.speechRecognition.rawValue)
                separator
                permissionRow("Local network", icon: "network", value: "Requested on connect")
                separator
                permissionRow("App Intents", icon: "shortcuts", value: "Available")
            }
        }
    }

    private var securitySection: some View {
        SettingsSection(title: "Execution safety", detail: "Always enforced", symbol: "lock.shield.fill") {
            VStack(alignment: .leading, spacing: 11) {
                Label("Read actions can run automatically", systemImage: "checkmark")
                Label("Prepared actions show a preview", systemImage: "doc.text.magnifyingglass")
                Label("Execute actions require approval", systemImage: "hand.tap.fill")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(CarinaTheme.secondaryText)
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
            HStack {
                Image(systemName: "checkmark")
                Text("Save secure connection")
                Spacer()
                Image(systemName: "arrow.right")
            }
            .font(.headline)
            .foregroundStyle(CarinaTheme.ink)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(CarinaTheme.signal, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(CarinaPressButtonStyle())
    }

    private var separator: some View {
        Rectangle()
            .fill(CarinaTheme.hairline)
            .frame(height: 1)
            .padding(.leading, 36)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(CarinaTheme.secondaryText)
    }

    private func portMetric(_ title: String, _ port: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(CarinaTheme.secondaryText)
                Text(String(port))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            Spacer()
            Circle()
                .fill(CarinaTheme.signal)
                .frame(width: 6, height: 6)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(CarinaTheme.recessed, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func permissionRow(_ title: String, icon: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(CarinaTheme.signal)
                .frame(width: 24)
            Text(title)
                .font(.subheadline.weight(.medium))
            Spacer(minLength: 8)
            Text(value)
                .font(.caption)
                .foregroundStyle(CarinaTheme.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 12)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let detail: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        CarinaSurface {
            VStack(alignment: .leading, spacing: 17) {
                HStack(spacing: 11) {
                    Image(systemName: symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CarinaTheme.signal)
                        .frame(width: 34, height: 34)
                        .background(CarinaTheme.signalSoft, in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(CarinaTheme.secondaryText)
                    }
                }
                content
            }
        }
    }
}
