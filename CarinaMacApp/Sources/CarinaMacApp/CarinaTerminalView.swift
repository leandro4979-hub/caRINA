import AppKit
import SwiftUI

struct CarinaTerminalView: View {
    @StateObject private var viewModel = CarinaTerminalViewModel()
    @State private var pulse = false

    private var statusColor: Color {
        switch viewModel.statusText {
        case "READY": return .green
        case "THINKING": return .orange
        case "OFFLINE", "ERROR": return .red
        default: return .yellow
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.12))
            console
            Divider().overlay(Color.white.opacity(0.12))
            controls
            composer
        }
        .background(Color.black)
        .foregroundStyle(.white)
        .frame(minWidth: 760, minHeight: 560)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.16))
                    .frame(width: 30, height: 30)
                    .scaleEffect(pulse ? 1.08 : 0.92)
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: statusColor.opacity(0.9), radius: 8)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("caRINA")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                    Text("0.4.0")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text("LOCAL CONSOLE • 127.0.0.1:11434")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(viewModel.statusText)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(statusColor.opacity(0.11), in: Capsule())
                .overlay(Capsule().stroke(statusColor.opacity(0.35), lineWidth: 1))

            Text("CONVERSATION SANDBOX")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.035))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var console: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.lines) { line in
                        TerminalLineView(line: line)
                            .id(line.id)
                    }

                    if viewModel.isGenerating {
                        HStack(alignment: .top, spacing: 10) {
                            Text("carina ›")
                                .foregroundStyle(.green)
                            Text(viewModel.liveResponse.isEmpty ? "thinking…" : viewModel.liveResponse)
                                .foregroundStyle(.white)
                            Text("▌")
                                .foregroundStyle(.green)
                                .opacity(pulse ? 1 : 0.25)
                        }
                        .font(.system(size: 14, weight: .regular, design: .monospaced))
                        .textSelection(.enabled)
                        .id("live-response")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            .background(
                LinearGradient(
                    colors: [Color.black, Color(red: 0.025, green: 0.035, blue: 0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onChange(of: viewModel.lines.count) { _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.liveResponse) { _ in
                scrollToBottom(proxy)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            TerminalControlButton(title: "STATUS", systemImage: "waveform.path.ecg") {
                haptic()
                viewModel.showStatus()
            }
            TerminalControlButton(title: "HELP", systemImage: "questionmark.circle") {
                haptic()
                viewModel.showHelp()
            }
            TerminalControlButton(title: "CLEAR", systemImage: "sparkles") {
                haptic()
                viewModel.clear()
            }
            TerminalControlButton(
                title: "STOP",
                systemImage: "stop.fill",
                isProminent: viewModel.isGenerating
            ) {
                haptic()
                viewModel.stop()
            }
            .disabled(!viewModel.isGenerating)
            .keyboardShortcut(KeyEquivalent("."), modifiers: [.command])

            Spacer()

            Text("⌘↩ SEND   ⌘. STOP")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.028))
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Text("❯")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(.green)

            TextField("Ask caRINA or type /help", text: $viewModel.input)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .disabled(viewModel.isGenerating)
                .onSubmit {
                    send()
                }

            Button {
                send()
            } label: {
                Label(viewModel.isGenerating ? "Working" : "Send", systemImage: "arrow.up.circle.fill")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.isGenerating ? Color.secondary : Color.black)
            .background(viewModel.isGenerating ? Color.white.opacity(0.08) : Color.green, in: RoundedRectangle(cornerRadius: 8))
            .disabled(viewModel.isGenerating || viewModel.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(14)
        .background(Color.white.opacity(0.045))
    }

    private func send() {
        guard !viewModel.isGenerating else { return }
        haptic()
        viewModel.submit()
    }

    private func haptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if viewModel.isGenerating {
            withAnimation(.easeOut(duration: 0.12)) {
                proxy.scrollTo("live-response", anchor: .bottom)
            }
        } else if let lastID = viewModel.lines.last?.id {
            withAnimation(.easeOut(duration: 0.12)) {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }
}

private struct TerminalLineView: View {
    let line: CarinaTerminalViewModel.Line

    private var prefix: String {
        switch line.role {
        case .system: return "sys    ›"
        case .user: return "amo    ›"
        case .carina: return "carina ›"
        case .error: return "error  ›"
        }
    }

    private var prefixColor: Color {
        switch line.role {
        case .system: return .secondary
        case .user: return .cyan
        case .carina: return .green
        case .error: return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(prefix)
                .foregroundStyle(prefixColor)
                .frame(width: 72, alignment: .leading)
            Text(line.text)
                .foregroundStyle(line.role == .system ? Color.white.opacity(0.72) : .white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 14, weight: .regular, design: .monospaced))
        .textSelection(.enabled)
    }
}

private struct TerminalControlButton: View {
    let title: String
    let systemImage: String
    var isProminent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isProminent ? Color.black : Color.white.opacity(0.88))
        .background(
            isProminent ? Color.orange : Color.white.opacity(0.065),
            in: RoundedRectangle(cornerRadius: 7)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}
