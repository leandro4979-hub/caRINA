import Carina
import Combine
import SwiftUI

private enum ModelStatus: Equatable {
    case unknown
    case checking
    case ready
    case ollamaUnavailable
    case modelMissing(String)
}

@MainActor
private final class LocalConversationViewModel: ObservableObject {
    @Published var draft = ""
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var status = ""
    @Published private(set) var isGenerating = false
    @Published private(set) var showTruncationNotice = false
    @Published private(set) var showPromptOversizeNotice = false
    @Published private(set) var modelStatus: ModelStatus = .unknown

    private var generationTask: Task<Void, Never>?
    private var store = ConversationStore()

    func send() {
        let submittedText = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submittedText.isEmpty, !isGenerating else { return }

        draft = ""
        status = ""
        let modelPrompt = store.composeContext(newUserPrompt: submittedText)
        showTruncationNotice = store.didTruncateLastContext
        showPromptOversizeNotice = store.promptWasOversize
        let userMessage = ChatMessage(role: .user, text: submittedText)
        store.append(userMessage)
        messages.append(userMessage)
        messages.append(ChatMessage(role: .assistant, text: ""))
        let assistantIndex = messages.index(before: messages.endIndex)
        isGenerating = true
        LocalDiagnostics.generationStarted()

        generationTask = Task { [weak self, modelPrompt] in
            defer {
                self?.isGenerating = false
                self?.generationTask = nil
                self?.refreshHealth()
            }
            do {
                for try await fragment in OllamaClient().generate(prompt: modelPrompt) {
                    try Task.checkCancellation()
                    guard let self else { throw CancellationError() }
                    self.messages[assistantIndex] = ChatMessage(
                        role: .assistant,
                        text: self.messages[assistantIndex].text + fragment
                    )
                }
                try Task.checkCancellation()
                if let reply = self?.messages[assistantIndex].text, !reply.isEmpty {
                    self?.store.append(ChatMessage(role: .assistant, text: reply))
                }
                self?.status = "Done"
                LocalDiagnostics.generationCompleted()
            } catch is CancellationError {
                self?.status = "Cancelled"
                LocalDiagnostics.generationCancelled()
            } catch let error as OllamaError {
                self?.status = error.errorDescription ?? "Ollama error"
                LocalDiagnostics.generationFailed()
            } catch {
                self?.status = "Unexpected error: \(error.localizedDescription)"
                LocalDiagnostics.generationFailed()
            }
        }
    }

    func stop() { generationTask?.cancel() }

    func refreshHealth() {
        Task { [weak self] in
            self?.modelStatus = .checking
            do {
                try await OllamaHealth.verify()
                self?.modelStatus = .ready
            } catch is CancellationError {
                self?.modelStatus = .unknown
            } catch let OllamaError.modelMissing(name) {
                self?.modelStatus = .modelMissing(name)
            } catch {
                self?.modelStatus = .ollamaUnavailable
            }
        }
    }

    func clearChat() {
        guard !isGenerating else { return }
        messages = []
        store.clear()
        status = ""
        showTruncationNotice = false
        showPromptOversizeNotice = false
    }
}

struct LocalConversationView: View {
    @StateObject private var viewModel = LocalConversationViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Local Conversation")
                .font(.title2.weight(.semibold))
            Text("Mac-only conversation. It does not access approval or action-execution features.")
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 10, height: 10)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ModelStatusIndicator")
                if showsRetry {
                    Button("Check Ollama", action: viewModel.refreshHealth)
                        .font(.caption)
                        .accessibilityIdentifier("RetryHealthButton")
                        .disabled(viewModel.isGenerating)
                }
            }
            HStack {
                Button("New Chat", action: viewModel.clearChat)
                    .disabled(viewModel.isGenerating || viewModel.messages.isEmpty)
                if viewModel.showTruncationNotice {
                    Text("Older messages were omitted from this request.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if viewModel.showPromptOversizeNotice {
                Text("Your prompt was shortened to fit the local context limit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if viewModel.messages.isEmpty {
                        Text("Start a private, local conversation.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(viewModel.messages) { message in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(message.role == .user ? "You" : "caRINA")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(message.text.isEmpty ? "Thinking…" : message.text)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(message.role == .user ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            HStack(alignment: .bottom) {
                TextField("Ask caRINA", text: $viewModel.draft, axis: .vertical)
                    .lineLimit(1 ... 4)
                    .disabled(viewModel.isGenerating)
                if viewModel.isGenerating {
                    Button("Stop", action: viewModel.stop)
                        .keyboardShortcut(".", modifiers: .command)
                } else {
                    Button("Send", action: viewModel.send)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if !viewModel.status.isEmpty { Text(viewModel.status).foregroundStyle(.secondary) }
        }
        .padding(20)
        .onAppear(perform: viewModel.refreshHealth)
    }

    private var statusColor: Color {
        switch viewModel.modelStatus {
        case .ready: .green
        case .checking: .yellow
        case .ollamaUnavailable, .modelMissing: .red
        case .unknown: .gray
        }
    }

    private var statusText: String {
        switch viewModel.modelStatus {
        case .unknown: "Status unknown"
        case .checking: "Checking Ollama…"
        case .ready: "Model ready"
        case .ollamaUnavailable: "Ollama is not running"
        case let .modelMissing(name): "Model missing — run: ollama pull \(name)"
        }
    }

    private var showsRetry: Bool {
        switch viewModel.modelStatus {
        case .ollamaUnavailable, .modelMissing: true
        default: false
        }
    }
}
