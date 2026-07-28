import CoreGraphics
import CoreText
import Foundation
import PDFKit
@testable import SlimLumaKit
import XCTest

final class PDFIntegrityCheckerTests: XCTestCase {
    func testInspectCapturesInteractiveAndExtractableContent() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("source.pdf")
        try makePDF(
            at: source,
            pageTexts: [
                String(repeating: "SlimLuma keeps searchable document text. ", count: 8),
                "Second searchable page"
            ],
            addOutline: true,
            addAnnotation: true,
            addTextField: true,
            addSignatureField: true
        )

        let snapshot = try PDFIntegrityChecker().inspect(source)

        XCTAssertEqual(snapshot.pageCount, 2)
        XCTAssertEqual(snapshot.outlineCount, 1)
        XCTAssertEqual(snapshot.annotationCount, 2)
        XCTAssertEqual(snapshot.formFieldCount, 2)
        XCTAssertEqual(snapshot.signatureFieldCount, 1)
        XCTAssertGreaterThan(snapshot.extractableCharacterCount, 100)
        XCTAssertEqual(snapshot.pagesWithExtractableText, 2)
        XCTAssertFalse(snapshot.isEncrypted)
        XCTAssertFalse(snapshot.isLocked)
        XCTAssertFalse(snapshot.isLinearized)
    }

    func testCompareReportsStrictStructuralLosses() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = directory.appendingPathComponent("original.pdf")
        let compressed = directory.appendingPathComponent("compressed.pdf")
        try makePDF(
            at: original,
            pageTexts: ["Page one searchable text", "Page two searchable text"],
            addOutline: true,
            addAnnotation: true,
            addTextField: true,
            addSignatureField: true
        )
        try makePDF(at: compressed, pageTexts: ["Page one searchable text"])

        let report = try PDFIntegrityChecker().compare(
            originalURL: original,
            compressedURL: compressed
        )

        XCTAssertTrue(report.hasCriticalRisk)
        XCTAssertTrue(report.risks.contains { $0.code == .pageCountChanged })
        XCTAssertTrue(report.risks.contains { $0.code == .outlinesRemoved })
        XCTAssertTrue(report.risks.contains { $0.code == .annotationsRemoved })
        XCTAssertTrue(report.risks.contains { $0.code == .formFieldsRemoved })
        XCTAssertTrue(report.risks.contains { $0.code == .signatureFieldsRemoved })
        XCTAssertTrue(report.risks.contains { $0.code == .digitalSignatureInvalidated })
        XCTAssertTrue(report.risks.allSatisfy { $0.severity == .critical })
    }

    func testModerateTextExtractionDifferenceIsNotTreatedAsLoss() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = directory.appendingPathComponent("original.pdf")
        let compressed = directory.appendingPathComponent("compressed.pdf")
        try makePDF(
            at: original,
            pageTexts: [String(repeating: "Searchable words ", count: 40)]
        )
        try makePDF(
            at: compressed,
            pageTexts: [String(repeating: "Searchable words ", count: 34)]
        )

        let report = try PDFIntegrityChecker().compare(
            originalURL: original,
            compressedURL: compressed
        )

        XCTAssertFalse(report.risks.contains { $0.code == .textExtractionCollapsed })
        XCTAssertFalse(report.hasCriticalRisk)
    }

    func testCatastrophicTextExtractionCollapseIsCritical() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = directory.appendingPathComponent("original.pdf")
        let compressed = directory.appendingPathComponent("compressed.pdf")
        try makePDF(
            at: original,
            pageTexts: [String(repeating: "Searchable document content ", count: 40)]
        )
        try makePDF(at: compressed, pageTexts: [""])

        let report = try PDFIntegrityChecker().compare(
            originalURL: original,
            compressedURL: compressed
        )

        XCTAssertTrue(report.hasCriticalRisk)
        XCTAssertEqual(
            report.risks.first { $0.code == .textExtractionCollapsed }?.severity,
            .critical
        )
    }

    func testRequiredLinearizationIsCriticalWhenMissing() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = directory.appendingPathComponent("original.pdf")
        let compressed = directory.appendingPathComponent("compressed.pdf")
        try makePDF(at: original, pageTexts: ["Searchable text"])
        try makePDF(at: compressed, pageTexts: ["Searchable text"])

        let report = try PDFIntegrityChecker().compare(
            originalURL: original,
            compressedURL: compressed,
            expectations: PDFIntegrityExpectations(requireLinearization: true)
        )

        XCTAssertTrue(report.hasCriticalRisk)
        XCTAssertEqual(
            report.risks.first { $0.code == .requiredLinearizationMissing }?.severity,
            .critical
        )
    }

    func testEncryptionRemovalIsCriticalEvenWhenSourceIsLocked() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let plain = directory.appendingPathComponent("plain.pdf")
        let encrypted = directory.appendingPathComponent("encrypted.pdf")
        try makePDF(at: plain, pageTexts: ["Protected document"])

        guard let document = PDFDocument(url: plain) else {
            return XCTFail("Could not reopen fixture")
        }
        XCTAssertTrue(
            document.write(
                to: encrypted,
                withOptions: [
                    .ownerPasswordOption: "owner-secret",
                    .userPasswordOption: "user-secret"
                ]
            )
        )

        let encryptedSnapshot = try PDFIntegrityChecker().inspect(encrypted)
        XCTAssertTrue(encryptedSnapshot.isEncrypted)
        XCTAssertTrue(encryptedSnapshot.isLocked)

        let report = try PDFIntegrityChecker().compare(
            originalURL: encrypted,
            compressedURL: plain
        )
        XCTAssertTrue(report.risks.contains { $0.code == .encryptionChanged })
        XCTAssertTrue(report.hasCriticalRisk)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SlimLumaPDFIntegrity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func makePDF(
        at url: URL,
        pageTexts: [String],
        addOutline: Bool = false,
        addAnnotation: Bool = false,
        addTextField: Bool = false,
        addSignatureField: Bool = false
    ) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw FixtureError.creationFailed
        }

        for text in pageTexts {
            context.beginPDFPage(nil)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String):
                    CTFontCreateWithName("Helvetica" as CFString, 14, nil)
            ]
            let attributedText = NSAttributedString(string: text, attributes: attributes)
            let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
            let path = CGPath(
                rect: CGRect(x: 42, y: 80, width: 528, height: 640),
                transform: nil
            )
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: 0, length: attributedText.length),
                path,
                nil
            )
            CTFrameDraw(frame, context)
            context.endPDFPage()
        }
        context.closePDF()

        guard let document = PDFDocument(url: url),
              let firstPage = document.page(at: 0) else {
            throw FixtureError.creationFailed
        }

        if addOutline {
            let root = PDFOutline()
            let child = PDFOutline()
            child.label = "First page"
            child.destination = PDFDestination(
                page: firstPage,
                at: CGPoint(x: 0, y: firstPage.bounds(for: .cropBox).height)
            )
            root.insertChild(child, at: 0)
            document.outlineRoot = root
        }

        if addAnnotation {
            let note = PDFAnnotation(
                bounds: CGRect(x: 40, y: 640, width: 24, height: 24),
                forType: .text,
                withProperties: nil
            )
            firstPage.addAnnotation(note)
        }

        if addTextField {
            let field = PDFAnnotation(
                bounds: CGRect(x: 80, y: 580, width: 180, height: 28),
                forType: .widget,
                withProperties: nil
            )
            field.widgetFieldType = .text
            field.fieldName = "customer-name"
            firstPage.addAnnotation(field)
        }

        if addSignatureField {
            let signature = PDFAnnotation(
                bounds: CGRect(x: 80, y: 520, width: 180, height: 38),
                forType: .widget,
                withProperties: nil
            )
            signature.widgetFieldType = .signature
            signature.fieldName = "approval-signature"
            firstPage.addAnnotation(signature)
        }

        guard document.write(to: url) else {
            throw FixtureError.creationFailed
        }
    }
}

private enum FixtureError: Error {
    case creationFailed
}
