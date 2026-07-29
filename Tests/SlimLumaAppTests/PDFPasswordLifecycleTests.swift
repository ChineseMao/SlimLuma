import Foundation
@testable import SlimLuma
import XCTest

final class PDFPasswordLifecycleTests: XCTestCase {
    func testBatchCleanupPreservesPasswordForWaitingItemAddedAfterSnapshot() {
        var batchItem = CompressionQueueItem(
            url: URL(fileURLWithPath: "/tmp/batch.pdf")
        )
        batchItem.pdfPassword = "batch-password"

        let candidateIDs = PDFPasswordQueueLifecycle.candidateIDs(
            in: [batchItem],
            includingFailuresAndCancellations: true
        )

        var laterItem = CompressionQueueItem(
            url: URL(fileURLWithPath: "/tmp/later.pdf")
        )
        laterItem.pdfPassword = "later-password"
        var queue = [batchItem, laterItem]

        PDFPasswordQueueLifecycle.clearPasswords(
            for: Set(candidateIDs),
            in: &queue
        )

        XCTAssertNil(queue[0].pdfPassword)
        XCTAssertEqual(queue[1].pdfPassword, "later-password")
    }

    func testTakingPasswordForStartedJobRemovesQueueCopyImmediately() {
        var item = CompressionQueueItem(
            url: URL(fileURLWithPath: "/tmp/encrypted.pdf")
        )
        item.pdfPassword = "job-password"
        var queue = [item]

        let password = PDFPasswordQueueLifecycle.takePassword(
            for: item.id,
            from: &queue
        )

        XCTAssertEqual(password, "job-password")
        XCTAssertNil(queue[0].pdfPassword)
    }

    func testWaitingBatchCandidateKeepsPasswordUntilItsJobStarts() {
        var first = CompressionQueueItem(
            url: URL(fileURLWithPath: "/tmp/first.pdf")
        )
        first.pdfPassword = "first-password"
        var second = CompressionQueueItem(
            url: URL(fileURLWithPath: "/tmp/second.pdf")
        )
        second.pdfPassword = "second-password"
        var queue = [first, second]

        let candidateIDs = PDFPasswordQueueLifecycle.candidateIDs(
            in: queue,
            includingFailuresAndCancellations: true
        )
        _ = PDFPasswordQueueLifecycle.takePassword(
            for: candidateIDs[0],
            from: &queue
        )

        XCTAssertNil(queue[0].pdfPassword)
        XCTAssertEqual(queue[1].pdfPassword, "second-password")
    }
}
