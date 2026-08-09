import OSLog

/// Privacy-minimized local diagnostics. Never pass prompt or response text here.
enum LocalDiagnostics {
    private static let logger = Logger(
        subsystem: "com.leandrofajardo.carina.localmodeltest",
        category: "conversation"
    )

    static func generationStarted() { logger.info("generation started") }
    static func generationCancelled() { logger.info("generation cancelled") }
    static func generationCompleted() { logger.info("generation completed") }
    static func generationFailed() { logger.error("generation failed") }
}
