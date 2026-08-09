import Foundation
@testable import Carina

func makeEnvelope(
    requestID: UUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
    sessionID: UUID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
    sequence: UInt64 = 9,
    nonce: UUID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
    payload: [String: String] = [
        "scope": "documents",
        "idempotencyKey": "sync-001"
    ],
    target: String? = nil
) -> CommandEnvelope {
    CommandEnvelope(
        version: 1,
        requestID: requestID,
        sessionID: sessionID,
        sequence: sequence,
        nonce: nonce,
        source: .userInterface,
        request: CommandRequest(intentID: .workspaceSync, payload: payload, target: target)
    )
}

actor RecordingAdapter: AppIntentAdapter {
    private(set) var executionCount = 0

    func execute(_ request: CommandRequest) async throws -> String {
        executionCount += 1
        return request.intentID.rawValue
    }
}
