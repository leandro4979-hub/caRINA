import Foundation

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }

    let id = UUID()
    let role: Role
    let text: String
}

/// Mac-only transcript context with deterministic, oldest-first truncation.
struct ConversationStore {
    private(set) var messages: [ChatMessage] = []
    let contextCharacterLimit: Int
    private(set) var didTruncateLastContext = false
    private(set) var promptWasOversize = false

    init(contextCharacterLimit: Int = 6_000) {
        precondition(contextCharacterLimit > 18, "context limit is too small")
        self.contextCharacterLimit = contextCharacterLimit
    }

    mutating func append(_ message: ChatMessage) { messages.append(message) }

    mutating func clear() {
        messages.removeAll()
        didTruncateLastContext = false
        promptWasOversize = false
    }

    mutating func composeContext(newUserPrompt: String) -> String {
        didTruncateLastContext = false
        promptWasOversize = false

        let userPrefix = "User: "
        let assistantSuffix = "\nAssistant:"
        let promptBudget = contextCharacterLimit - userPrefix.count - assistantSuffix.count
        let boundedPrompt: String
        if newUserPrompt.count > promptBudget {
            promptWasOversize = true
            boundedPrompt = String(newUserPrompt.prefix(promptBudget))
        } else {
            boundedPrompt = newUserPrompt
        }

        let userLine = userPrefix + boundedPrompt
        var budget = contextCharacterLimit - userLine.count - assistantSuffix.count
        var included: [String] = []
        for message in messages.reversed() {
            let speaker = message.role == .user ? "User: " : "Assistant: "
            let line = speaker + message.text
            let separatorCost = included.isEmpty ? 0 : 1
            guard line.count + separatorCost <= budget else { break }
            included.append(line)
            budget -= line.count + separatorCost
        }
        didTruncateLastContext = included.count < messages.count
        let history = included.reversed().joined(separator: "\n")
        return (history.isEmpty ? userLine : history + "\n" + userLine) + assistantSuffix
    }
}
