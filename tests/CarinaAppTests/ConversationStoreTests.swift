import XCTest
@testable import CarinaMacApp

final class ConversationStoreTests: XCTestCase {
    func testStartsEmpty() {
        let store = ConversationStore()
        XCTAssertTrue(store.messages.isEmpty)
    }

    func testAppendPreservesMessage() {
        var store = ConversationStore()
        let message = ChatMessage(role: .user, text: "Hello")
        store.append(message)
        XCTAssertEqual(store.messages, [message])
    }

    func testClearRemovesMessages() {
        var store = ConversationStore()
        store.append(ChatMessage(role: .user, text: "Hello"))
        store.clear()
        XCTAssertTrue(store.messages.isEmpty)
    }

    func testContextContainsPromptAndAssistantMarker() {
        var store = ConversationStore()
        let context = store.composeContext(newUserPrompt: "Hello")
        XCTAssertEqual(context, "User: Hello\nAssistant:")
    }

    func testContextUsesUserAndAssistantLabels() {
        var store = ConversationStore()
        store.append(ChatMessage(role: .user, text: "Earlier"))
        store.append(ChatMessage(role: .assistant, text: "Reply"))
        let context = store.composeContext(newUserPrompt: "Next")
        XCTAssertEqual(context, "User: Earlier\nAssistant: Reply\nUser: Next\nAssistant:")
    }

    func testOversizePromptIsBounded() {
        var store = ConversationStore(contextCharacterLimit: 30)
        let context = store.composeContext(newUserPrompt: String(repeating: "x", count: 100))
        XCTAssertLessThanOrEqual(context.count, 30)
        XCTAssertTrue(store.promptWasOversize)
    }

    func testExactLimitPromptIsNotOversize() {
        var store = ConversationStore(contextCharacterLimit: 30)
        _ = store.composeContext(newUserPrompt: String(repeating: "x", count: 13))
        XCTAssertFalse(store.promptWasOversize)
    }

    func testOldestHistoryIsDroppedFirst() {
        var store = ConversationStore(contextCharacterLimit: 45)
        store.append(ChatMessage(role: .user, text: "old old old"))
        store.append(ChatMessage(role: .assistant, text: "new"))
        let context = store.composeContext(newUserPrompt: "now")
        XCTAssertFalse(context.contains("old old old"))
        XCTAssertTrue(context.contains("Assistant: new"))
        XCTAssertTrue(store.didTruncateLastContext)
    }

    func testHistoryOrderRemainsChronological() {
        var store = ConversationStore()
        store.append(ChatMessage(role: .user, text: "One"))
        store.append(ChatMessage(role: .assistant, text: "Two"))
        let context = store.composeContext(newUserPrompt: "Three")
        XCTAssertLessThan(
            context.range(of: "User: One")!.lowerBound,
            context.range(of: "Assistant: Two")!.lowerBound
        )
    }

    func testClearResetsFlags() {
        var store = ConversationStore(contextCharacterLimit: 30)
        _ = store.composeContext(newUserPrompt: String(repeating: "x", count: 100))
        store.clear()
        XCTAssertFalse(store.promptWasOversize)
        XCTAssertFalse(store.didTruncateLastContext)
    }

    func testEmptyHistoryDoesNotReportTruncation() {
        var store = ConversationStore()
        _ = store.composeContext(newUserPrompt: "Hello")
        XCTAssertFalse(store.didTruncateLastContext)
    }
}
