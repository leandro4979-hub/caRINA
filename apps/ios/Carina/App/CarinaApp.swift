import SwiftUI

@main
struct CarinaApp: App {
    @StateObject private var settings = BridgeSettings()
    @StateObject private var bridge = BridgeClient()
    @StateObject private var credentials = CredentialManager()
    @StateObject private var agent = CarinaAgentService()
    @StateObject private var speech = SpeechRecognitionService()
    @StateObject private var voice = NativeVoiceSynthesisService()
    @StateObject private var realtime = RealtimeVoiceService()
    @StateObject private var permissions = PermissionManager()
    @State private var showingRealtimeVoice = false

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .bottomTrailing) {
                ContentView()

                Button {
                    showingRealtimeVoice = true
                } label: {
                    Label("Live", systemImage: "waveform.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CarinaTheme.ink)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 46)
                        .background(CarinaTheme.signal, in: Capsule())
                        .shadow(color: CarinaTheme.canvas.opacity(0.65), radius: 16, y: 8)
                }
                .buttonStyle(CarinaPressButtonStyle())
                .padding(.trailing, 18)
                .padding(.bottom, 118)
                .accessibilityLabel("Open CARINA Live Voice")
            }
            .environmentObject(settings)
            .environmentObject(bridge)
            .environmentObject(credentials)
            .environmentObject(agent)
            .environmentObject(speech)
            .environmentObject(voice)
            .environmentObject(realtime)
            .environmentObject(permissions)
            .sheet(isPresented: $showingRealtimeVoice) {
                RealtimeVoiceView()
                    .environmentObject(settings)
                    .environmentObject(bridge)
                    .environmentObject(credentials)
                    .environmentObject(realtime)
            }
        }
    }
}
