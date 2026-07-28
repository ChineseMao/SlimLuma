import Foundation
@testable import SlimLuma
import SlimLumaKit
import XCTest

final class JobOutcomeTests: XCTestCase {
    func testCancellationUsesTypedFailureKindInsteadOfMessageText() {
        let outcome = JobOutcome.failure(
            itemID: UUID(),
            error: CompressionError.cancelled
        )

        XCTAssertEqual(outcome.failureKind, .cancelled)
        XCTAssertNil(outcome.recoveryTool)
    }

    func testCancellationErrorUsesTypedFailureKind() {
        let outcome = JobOutcome.failure(
            itemID: UUID(),
            error: CancellationError()
        )

        XCTAssertEqual(outcome.failureKind, .cancelled)
    }

    func testOutputValidationUsesTypedFailureKind() {
        let outcome = JobOutcome.failure(
            itemID: UUID(),
            error: CompressionError.outputInvalid("arbitrary message")
        )

        XCTAssertEqual(outcome.failureKind, .outputValidation)
    }

    func testRecoveryToolDoesNotDependOnDisplayName() {
        let outcome = JobOutcome.failure(
            itemID: UUID(),
            error: CompressionError.missingTool(
                name: "translated or custom name",
                installCommand: "brew install qpdf",
                tool: .qpdf
            )
        )

        XCTAssertEqual(outcome.failureKind, .missingTool(.qpdf))
        XCTAssertEqual(outcome.recoveryTool, .qpdf)
    }
}
