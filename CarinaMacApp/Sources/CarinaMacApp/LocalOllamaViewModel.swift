import Carina
import Combine
import Foundation

@MainActor
final class LocalOllamaViewModel: ObservableObject {
    @Published var prompt = ""
    @Published private(set) var response = ""
    @Published private(set) var status = ""
    @Published private(set) var isGenerating = false
#if DEBUG
    @Published var useSlowStreamFixture = false
#endif

    private var generationTask: Task<Void, Never>?

#if DEBUG
    init() {
        useSlowStreamFixture = ProcessInfo.processInfo.arguments.contains(
            "--use-slow-stream-fixture"
        )
    }
#endif

    func generate() {
        let submittedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submittedPrompt.isEmpty, !isGenerating else { return }

        response = ""
        status = ""
        isGenerating = true

        generationTask = Task { [weak self, submittedPrompt] in
            defer {
                self?.isGenerating = false
                self?.generationTask = nil
            }

            do {
#if DEBUG
                let stream: AsyncThrowingStream<String, Error> = self?.useSlowStreamFixture == true
                    ? SlowStreamFixture.generate()
                    : OllamaClient().generate(prompt: submittedPrompt)
#else
                let stream = OllamaClient().generate(prompt: submittedPrompt)
#endif
                for try await chunk in stream {
                    try Task.checkCancellation()
                    self?.response += chunk
                }
                try Task.checkCancellation()
                self?.status = "Done"
            } catch is CancellationError {
                self?.status = "Cancelled"
            } catch let error as OllamaError {
                self?.status = error.errorDescription ?? "Ollama error"
            } catch {
                self?.status = "Unexpected error: \(error.localizedDescription)"
            }
        }
    }

    func stop() {
        generationTask?.cancel()
    }
}
