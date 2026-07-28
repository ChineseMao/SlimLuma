import Foundation
import XCTest
@testable import SlimLuma

final class ClipboardImportServiceTests: XCTestCase {
    func testSymbolicLinkImportRootIsRejected() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SlimLumaClipboardImportTests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let outsideRoot = temporaryDirectory
            .appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outsideRoot,
            withIntermediateDirectories: true
        )
        let source = temporaryDirectory.appendingPathComponent("sample.pdf")
        try Data("%PDF-1.7\n".utf8).write(to: source, options: [.atomic])

        let linkedRoot = temporaryDirectory
            .appendingPathComponent("LinkedImports", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: linkedRoot,
            withDestinationURL: outsideRoot
        )
        let service = ClipboardImportService(importRoot: linkedRoot)

        do {
            _ = try await service.importFiles([source])
            XCTFail("Expected a symbolic-link import root to be rejected")
        } catch let error as ClipboardImportService.ImportError {
            guard case .unsafeImportDirectory = error else {
                return XCTFail("Unexpected import error: \(error)")
            }
        }

        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: outsideRoot,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
    }
}
