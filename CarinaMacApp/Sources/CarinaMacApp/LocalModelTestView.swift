import SwiftUI

struct LocalModelTestView: View {
    @StateObject private var viewModel = LocalOllamaViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Local Model Test")
                .font(.title2.weight(.semibold))

            Text("Uses Ollama only on this Mac. Nothing is sent over the network.")
                .foregroundStyle(.secondary)

#if DEBUG
            Toggle("Slow stream test mode", isOn: $viewModel.useSlowStreamFixture)
                .accessibilityIdentifier("SlowStreamToggle")
                .disabled(viewModel.isGenerating)
#endif

            TextEditor(text: $viewModel.prompt)
                .font(.body)
                .frame(minHeight: 88, maxHeight: 110)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                .accessibilityIdentifier("PromptTextEditor")
                .disabled(viewModel.isGenerating)

            HStack {
                Button(viewModel.isGenerating ? "Stop" : "Generate") {
                    viewModel.isGenerating ? viewModel.stop() : viewModel.generate()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("GenerateStopButton")
                .disabled(viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isGenerating)

                if !viewModel.status.isEmpty {
                    Text(viewModel.status)
                        .foregroundStyle(viewModel.status == "Done" ? .green : .secondary)
                        .accessibilityIdentifier("StatusLabel")
                }
            }

            ScrollView {
                Text(viewModel.response.isEmpty ? "The response will appear here." : viewModel.response)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("ResponseArea")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .frame(minHeight: 180)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(20)
    }
}
