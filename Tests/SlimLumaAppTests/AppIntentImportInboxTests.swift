import Foundation
import XCTest
@testable import SlimLuma

final class AppIntentImportInboxTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var importRoot: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SlimLumaAppIntentImportInboxTests-\(UUID().uuidString)",
                isDirectory: true
            )
        importRoot = temporaryDirectory
            .appendingPathComponent("Imports", isDirectory: true)
        try FileManager.default.createDirectory(
            at: importRoot,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        importRoot = nil
    }

    func testEnqueuePendingAndConsumeRoundTrip() throws {
        let batch = try makeBatch(named: "batch")
        let source = try makeFile(named: "sample.pdf", in: batch)

        let enqueued = try AppIntentImportInbox.enqueue(
            importedURLs: [source],
            batchDirectory: batch,
            startsCompression: true,
            importRoot: importRoot
        )

        let pending = try XCTUnwrap(
            AppIntentImportInbox.pendingRequests(importRoot: importRoot).first
        )
        XCTAssertEqual(pending.request.id, enqueued.request.id)
        XCTAssertEqual(pending.fileURLs, [source.standardizedFileURL])
        XCTAssertTrue(pending.request.startsCompression)

        try AppIntentImportInbox.consume(pending, importRoot: importRoot)
        XCTAssertTrue(
            try AppIntentImportInbox.pendingRequests(
                importRoot: importRoot
            ).isEmpty
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testEnqueueRejectsSymbolicLinkFile() throws {
        let batch = try makeBatch(named: "batch")
        let outside = try makeFile(
            named: "outside.pdf",
            in: temporaryDirectory
        )
        let link = batch.appendingPathComponent("linked.pdf")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: outside
        )

        XCTAssertThrowsError(
            try AppIntentImportInbox.enqueue(
                importedURLs: [link],
                batchDirectory: batch,
                startsCompression: false,
                importRoot: importRoot
            )
        )
    }

    func testPendingRequestsIgnoreSymbolicLinkBatch() throws {
        let outsideRoot = temporaryDirectory
            .appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outsideRoot,
            withIntermediateDirectories: true
        )
        let outsideBatch = outsideRoot
            .appendingPathComponent("outside-batch", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outsideBatch,
            withIntermediateDirectories: true
        )
        let source = try makeFile(named: "sample.pdf", in: outsideBatch)
        _ = try AppIntentImportInbox.enqueue(
            importedURLs: [source],
            batchDirectory: outsideBatch,
            startsCompression: false,
            importRoot: outsideRoot
        )

        let linkedBatch = importRoot.appendingPathComponent("linked-batch")
        try FileManager.default.createSymbolicLink(
            at: linkedBatch,
            withDestinationURL: outsideBatch
        )

        XCTAssertTrue(
            try AppIntentImportInbox.pendingRequests(
                importRoot: importRoot
            ).isEmpty
        )
    }

    func testSymbolicLinkImportRootIsRejected() throws {
        let outsideRoot = temporaryDirectory
            .appendingPathComponent("OutsideRoot", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outsideRoot,
            withIntermediateDirectories: true
        )
        let linkedRoot = temporaryDirectory
            .appendingPathComponent("LinkedRoot", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: linkedRoot,
            withDestinationURL: outsideRoot
        )
        let batch = linkedRoot
            .appendingPathComponent("batch", isDirectory: true)
        try FileManager.default.createDirectory(
            at: batch,
            withIntermediateDirectories: true
        )
        let source = try makeFile(named: "sample.pdf", in: batch)

        XCTAssertThrowsError(
            try AppIntentImportInbox.enqueue(
                importedURLs: [source],
                batchDirectory: batch,
                startsCompression: false,
                importRoot: linkedRoot
            )
        )
    }

    func testConsumingStaleRequestKeepsReplacementReceipt() throws {
        let batch = try makeBatch(named: "batch")
        let source = try makeFile(named: "sample.pdf", in: batch)
        let first = try AppIntentImportInbox.enqueue(
            importedURLs: [source],
            batchDirectory: batch,
            startsCompression: false,
            importRoot: importRoot
        )
        let replacement = try AppIntentImportInbox.enqueue(
            importedURLs: [source],
            batchDirectory: batch,
            startsCompression: true,
            importRoot: importRoot
        )

        XCTAssertThrowsError(
            try AppIntentImportInbox.consume(first, importRoot: importRoot)
        )

        let pending = try XCTUnwrap(
            AppIntentImportInbox.pendingRequests(importRoot: importRoot).first
        )
        XCTAssertEqual(pending.request.id, replacement.request.id)
        XCTAssertTrue(pending.request.startsCompression)
    }

    func testCorruptReceiptIsQuarantinedWithoutSuppressingValidRequest() throws {
        let corruptBatch = try makeBatch(named: "corrupt")
        let corruptSource = try makeFile(
            named: "corrupt.pdf",
            in: corruptBatch
        )
        let corrupt = try AppIntentImportInbox.enqueue(
            importedURLs: [corruptSource],
            batchDirectory: corruptBatch,
            startsCompression: false,
            importRoot: importRoot
        )
        try Data("not-json".utf8).write(
            to: corrupt.receiptURL,
            options: [.atomic]
        )

        let validBatch = try makeBatch(named: "valid")
        let validSource = try makeFile(named: "valid.pdf", in: validBatch)
        let valid = try AppIntentImportInbox.enqueue(
            importedURLs: [validSource],
            batchDirectory: validBatch,
            startsCompression: true,
            importRoot: importRoot
        )

        let result = try AppIntentImportInbox.scanPendingRequests(
            importRoot: importRoot
        )
        XCTAssertEqual(result.pendingRequests.map(\.request.id), [valid.request.id])
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: corrupt.receiptURL.path)
        )
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: corruptBatch,
                includingPropertiesForKeys: nil
            ).contains {
                $0.lastPathComponent.hasPrefix(
                    ".appintent-request.json.invalid-"
                )
            }
        )
    }

    func testReceiptWithMissingFileIsQuarantined() throws {
        let batch = try makeBatch(named: "missing")
        let source = try makeFile(named: "missing.pdf", in: batch)
        let enqueued = try AppIntentImportInbox.enqueue(
            importedURLs: [source],
            batchDirectory: batch,
            startsCompression: false,
            importRoot: importRoot
        )
        try FileManager.default.removeItem(at: source)

        let result = try AppIntentImportInbox.scanPendingRequests(
            importRoot: importRoot
        )
        XCTAssertTrue(result.pendingRequests.isEmpty)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: enqueued.receiptURL.path)
        )
    }

    private func makeBatch(named name: String) throws -> URL {
        let batch = importRoot.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: batch,
            withIntermediateDirectories: false
        )
        return batch
    }

    private func makeFile(named name: String, in directory: URL) throws -> URL {
        let file = directory.appendingPathComponent(name)
        try Data("%PDF-1.7\n".utf8).write(to: file, options: [.atomic])
        return file
    }
}
