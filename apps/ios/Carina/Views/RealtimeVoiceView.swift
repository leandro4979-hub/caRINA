import SwiftUI

struct RealtimeVoiceView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: BridgeSettings
    @EnvironmentObject private var bridge: BridgeClient
    @EnvironmentObject private var credentials: CredentialManager
    @EnvironmentObject private var realtime: RealtimeVoiceService

    @State private var localError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                CarinaBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        hero
                        connectionCard
                        controlButton

                        if let localError {
                            ErrorBanner(text: localError)
                        }
                        if case .failed(let message) = realtime.state {
                            ErrorBanner(text: message)
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Live Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: realtime.callID) { _, callID in
                guard let callID else { return }
                Task {
                    do {
                        try await bridge.attachRealtime(callID: callID)
                    } catch {
                        localError = "Voice is live, but the CARINA sideband could not attach: \(error.localizedDescription)"
                    }
                }
            }
            .onDisappear {
                realtime.disconnect()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var hero: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(CarinaTheme.signal.opacity(realtime.state == .connected ? 0.18 : 0.08))
                    .frame(width: 188, height: 188)
                    .scaleEffect(realtime.state == .connected ? 1.06 : 1)
                    .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: realtime.state == .connected)

                Circle()
                    .stroke(CarinaTheme.signal.opacity(0.28), lineWidth: 1)
                    .frame(width: 150, height: 150)

                Image(systemName: realtime.state == .connected ? "waveform.circle.fill" : "waveform.circle")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(CarinaTheme.signal)
            }

            Text(realtime.state.label.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.8)
                .foregroundStyle(statusColor)

            Text(realtime.state == .connected ? "CARINA is live." : "Call CARINA.")
                .font(.system(size: 39, weight: .regular, design: .serif))
                .tracking(-1)
                .multilineTextAlignment(.center)

            Text("Your microphone audio travels directly from this iPhone to OpenAI Realtime over WebRTC. CARINA’s Mac bridge keeps the standard API key and server control plane off the phone.")
                .font(.subheadline)
                .foregroundStyle(CarinaTheme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .padding(.top, 12)
    }

    private var connectionCard: some View {
        CarinaSurface(accent: realtime.state == .connected ? CarinaTheme.signal : CarinaTheme.warning) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Realtime path", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.headline)
                    Spacer()
                    StatusIndicator(text: realtime.state.label, color: statusColor)
                }

                VStack(spacing: 1) {
                    metricRow("Audio", value: realtime.state == .connected ? "WebRTC direct" : "Not connected", icon: "iphone")
                    Divider().overlay(CarinaTheme.hairline)
                    metricRow("Control plane", value: bridge.realtimeSidebandStatus, icon: "macbook")
                    Divider().overlay(CarinaTheme.hairline)
                    metricRow("Model", value: realtime.model.isEmpty ? "Server selected" : realtime.model, icon: "brain")
                    Divider().overlay(CarinaTheme.hairline)
                    metricRow("Voice", value: realtime.voice.isEmpty ? "Server selected" : realtime.voice, icon: "speaker.wave.2")
                }
                .background(CarinaTheme.recessed, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                if !realtime.lastEvent.isEmpty {
                    Text("Latest event: \(realtime.lastEvent)")
                        .font(.caption.monospaced())
                        .foregroundStyle(CarinaTheme.secondaryText)
                        .lineLimit(2)
                }
            }
        }
    }

    private func metricRow(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(CarinaTheme.signal)
                .frame(width: 24)
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CarinaTheme.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
    }

    private var controlButton: some View {
        Button {
            realtime.state.isActive ? stop() : start()
        } label: {
            HStack(spacing: 11) {
                if isStarting {
                    ProgressView().tint(CarinaTheme.ink)
                } else {
                    Image(systemName: realtime.state.isActive ? "phone.down.fill" : "phone.fill")
                }
                Text(realtime.state.isActive ? "End Live Voice" : "Start Live Voice")
            }
            .font(.headline)
            .foregroundStyle(realtime.state.isActive ? .white : CarinaTheme.ink)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(
                realtime.state.isActive ? CarinaTheme.danger : CarinaTheme.signal,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
        }
        .buttonStyle(CarinaPressButtonStyle())
        .disabled(isStarting)
        .accessibilityLabel(realtime.state.isActive ? "End CARINA Live Voice" : "Start CARINA Live Voice")
    }

    private var isStarting: Bool {
        switch realtime.state {
        case .requestingPermission, .requestingSession, .connecting: return true
        default: return false
        }
    }

    private var statusColor: Color {
        switch realtime.state {
        case .connected: return CarinaTheme.signal
        case .failed: return CarinaTheme.danger
        case .idle: return CarinaTheme.secondaryText
        default: return CarinaTheme.warning
        }
    }

    private func start() {
        localError = nil
        guard settings.save(),
              let configuration = try? settings.configuration(),
              credentials.hasBridgeToken else {
            localError = "Pair CARINA with the Mac bridge in Settings before starting Live Voice."
            return
        }

        Task {
            if bridge.state != .connected {
                await bridge.connect(using: configuration, bearerToken: credentials.bridgeToken)
            }
            guard bridge.state == .connected else {
                localError = "CARINA could not connect to the authenticated Mac bridge."
                return
            }
            await realtime.connect(using: configuration, bearerToken: credentials.bridgeToken)
        }
    }

    private func stop() {
        realtime.disconnect()
        localError = nil
    }
}
