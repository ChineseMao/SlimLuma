import Foundation
import PDFKit

public enum PDFIntegrityRiskSeverity: String, Codable, Equatable, Sendable {
    case critical
}

public enum PDFIntegrityRiskCode: String, Codable, Equatable, Sendable {
    case pageCountChanged
    case outlinesRemoved
    case annotationsRemoved
    case formFieldsRemoved
    case signatureFieldsRemoved
    case digitalSignatureInvalidated
    case encryptionChanged
    case textExtractionCollapsed
    case requiredLinearizationMissing
}

public struct PDFIntegrityRisk: Codable, Equatable, Sendable {
    public let code: PDFIntegrityRiskCode
    public let severity: PDFIntegrityRiskSeverity
    public let message: String
    public let originalValue: Int?
    public let compressedValue: Int?

    public init(
        code: PDFIntegrityRiskCode,
        severity: PDFIntegrityRiskSeverity = .critical,
        message: String,
        originalValue: Int? = nil,
        compressedValue: Int? = nil
    ) {
        self.code = code
        self.severity = severity
        self.message = message
        self.originalValue = originalValue
        self.compressedValue = compressedValue
    }
}

public struct PDFIntegritySnapshot: Codable, Equatable, Sendable {
    public let url: URL
    public let pageCount: Int
    public let outlineCount: Int
    public let annotationCount: Int
    public let formFieldCount: Int
    public let signatureFieldCount: Int
    public let extractableCharacterCount: Int
    public let pagesWithExtractableText: Int
    public let isEncrypted: Bool
    public let isLocked: Bool
    public let isLinearized: Bool

    public init(
        url: URL,
        pageCount: Int,
        outlineCount: Int,
        annotationCount: Int,
        formFieldCount: Int,
        signatureFieldCount: Int,
        extractableCharacterCount: Int,
        pagesWithExtractableText: Int,
        isEncrypted: Bool,
        isLocked: Bool,
        isLinearized: Bool
    ) {
        self.url = url
        self.pageCount = pageCount
        self.outlineCount = outlineCount
        self.annotationCount = annotationCount
        self.formFieldCount = formFieldCount
        self.signatureFieldCount = signatureFieldCount
        self.extractableCharacterCount = extractableCharacterCount
        self.pagesWithExtractableText = pagesWithExtractableText
        self.isEncrypted = isEncrypted
        self.isLocked = isLocked
        self.isLinearized = isLinearized
    }
}

public struct PDFIntegrityExpectations: Codable, Equatable, Sendable {
    public var requireLinearization: Bool
    public var minimumTextCharactersForComparison: Int
    public var minimumRetainedTextRatio: Double

    public init(
        requireLinearization: Bool = false,
        minimumTextCharactersForComparison: Int = 100,
        minimumRetainedTextRatio: Double = 0.2
    ) {
        self.requireLinearization = requireLinearization
        self.minimumTextCharactersForComparison = max(0, minimumTextCharactersForComparison)
        self.minimumRetainedTextRatio = min(max(minimumRetainedTextRatio, 0), 1)
    }
}

public struct PDFIntegrityReport: Codable, Equatable, Sendable {
    public let original: PDFIntegritySnapshot
    public let compressed: PDFIntegritySnapshot
    public let risks: [PDFIntegrityRisk]

    public var hasCriticalRisk: Bool {
        risks.contains { $0.severity == .critical }
    }

    public init(
        original: PDFIntegritySnapshot,
        compressed: PDFIntegritySnapshot,
        risks: [PDFIntegrityRisk]
    ) {
        self.original = original
        self.compressed = compressed
        self.risks = risks
    }
}

public enum PDFIntegrityError: LocalizedError, Equatable {
    case fileMissing(URL)
    case unreadableDocument(URL)

    public var errorDescription: String? {
        switch self {
        case let .fileMissing(url):
            return "找不到 PDF：\(url.lastPathComponent)"
        case let .unreadableDocument(url):
            return "无法读取 PDF：\(url.lastPathComponent)"
        }
    }
}

public struct PDFIntegrityChecker: Sendable {
    public init() {}

    public func inspect(
        _ url: URL,
        password: String? = nil
    ) throws -> PDFIntegritySnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PDFIntegrityError.fileMissing(url)
        }
        guard let document = PDFDocument(url: url) else {
            throw PDFIntegrityError.unreadableDocument(url)
        }
        if document.isLocked,
           let password,
           !password.isEmpty {
            _ = document.unlock(withPassword: password)
        }

        let isLocked = document.isLocked
        var outlineCount = 0
        var annotationCount = 0
        var formFieldCount = 0
        var signatureFieldCount = 0
        var extractableCharacterCount = 0
        var pagesWithExtractableText = 0

        if !isLocked {
            outlineCount = countOutlines(in: document)

            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex) else { continue }

                for annotation in page.annotations {
                    if annotation.type == "Widget" {
                        formFieldCount += 1
                        if annotation.widgetFieldType == .signature {
                            signatureFieldCount += 1
                        }
                    } else {
                        annotationCount += 1
                    }
                }

                let characterCount = countExtractableCharacters(in: page.string)
                extractableCharacterCount += characterCount
                if characterCount > 0 {
                    pagesWithExtractableText += 1
                }
            }
        }

        return PDFIntegritySnapshot(
            url: url.standardizedFileURL,
            pageCount: document.pageCount,
            outlineCount: outlineCount,
            annotationCount: annotationCount,
            formFieldCount: formFieldCount,
            signatureFieldCount: signatureFieldCount,
            extractableCharacterCount: extractableCharacterCount,
            pagesWithExtractableText: pagesWithExtractableText,
            isEncrypted: document.isEncrypted,
            isLocked: isLocked,
            isLinearized: isLinearized(url)
        )
    }

    public func compare(
        originalURL: URL,
        compressedURL: URL,
        expectations: PDFIntegrityExpectations = PDFIntegrityExpectations(),
        password: String? = nil
    ) throws -> PDFIntegrityReport {
        try compare(
            original: inspect(originalURL, password: password),
            compressed: inspect(compressedURL, password: password),
            expectations: expectations
        )
    }

    public func compare(
        original: PDFIntegritySnapshot,
        compressed: PDFIntegritySnapshot,
        expectations: PDFIntegrityExpectations = PDFIntegrityExpectations()
    ) -> PDFIntegrityReport {
        var risks: [PDFIntegrityRisk] = []

        if original.isEncrypted != compressed.isEncrypted {
            risks.append(
                PDFIntegrityRisk(
                    code: .encryptionChanged,
                    message: original.isEncrypted
                        ? "压缩结果移除了原 PDF 的加密保护"
                        : "压缩结果意外改变了 PDF 的加密状态"
                )
            )
        }

        if !original.isLocked, !compressed.isLocked {
            appendChangedRisk(
                to: &risks,
                when: original.pageCount != compressed.pageCount,
                code: .pageCountChanged,
                message: "压缩前后页数不一致",
                originalValue: original.pageCount,
                compressedValue: compressed.pageCount
            )
            appendChangedRisk(
                to: &risks,
                when: compressed.outlineCount < original.outlineCount,
                code: .outlinesRemoved,
                message: "压缩结果丢失了 PDF 书签",
                originalValue: original.outlineCount,
                compressedValue: compressed.outlineCount
            )
            appendChangedRisk(
                to: &risks,
                when: compressed.annotationCount < original.annotationCount,
                code: .annotationsRemoved,
                message: "压缩结果丢失了 PDF 批注或链接",
                originalValue: original.annotationCount,
                compressedValue: compressed.annotationCount
            )
            appendChangedRisk(
                to: &risks,
                when: compressed.formFieldCount < original.formFieldCount,
                code: .formFieldsRemoved,
                message: "压缩结果丢失了 PDF 表单字段",
                originalValue: original.formFieldCount,
                compressedValue: compressed.formFieldCount
            )
            appendChangedRisk(
                to: &risks,
                when: compressed.signatureFieldCount < original.signatureFieldCount,
                code: .signatureFieldsRemoved,
                message: "压缩结果丢失了 PDF 签名字段",
                originalValue: original.signatureFieldCount,
                compressedValue: compressed.signatureFieldCount
            )

            if original.signatureFieldCount > 0 {
                risks.append(
                    PDFIntegrityRisk(
                        code: .digitalSignatureInvalidated,
                        message: "原 PDF 含签名字段；重写文件会使现有数字签名失效",
                        originalValue: original.signatureFieldCount,
                        compressedValue: compressed.signatureFieldCount
                    )
                )
            }

            if textExtractionCollapsed(
                original: original,
                compressed: compressed,
                expectations: expectations
            ) {
                risks.append(
                    PDFIntegrityRisk(
                        code: .textExtractionCollapsed,
                        message: "压缩结果中的可提取文本大幅减少，可能影响搜索和复制",
                        originalValue: original.extractableCharacterCount,
                        compressedValue: compressed.extractableCharacterCount
                    )
                )
            }
        }

        if expectations.requireLinearization, !compressed.isLinearized {
            risks.append(
                PDFIntegrityRisk(
                    code: .requiredLinearizationMissing,
                    message: "已要求网页快速打开，但压缩结果没有线性化"
                )
            )
        }

        return PDFIntegrityReport(
            original: original,
            compressed: compressed,
            risks: risks
        )
    }

    private func countOutlines(in document: PDFDocument) -> Int {
        guard let root = document.outlineRoot else { return 0 }

        var stack: [PDFOutline] = (0..<root.numberOfChildren).compactMap {
            root.child(at: $0)
        }
        var visited: Set<ObjectIdentifier> = []
        var count = 0

        while let outline = stack.popLast(), count < 100_000 {
            let identifier = ObjectIdentifier(outline)
            guard visited.insert(identifier).inserted else { continue }
            count += 1
            for index in 0..<outline.numberOfChildren {
                if let child = outline.child(at: index) {
                    stack.append(child)
                }
            }
        }
        return count
    }

    private func countExtractableCharacters(in text: String?) -> Int {
        guard let text else { return 0 }
        return text.unicodeScalars.reduce(into: 0) { count, scalar in
            if !CharacterSet.whitespacesAndNewlines.contains(scalar) {
                count += 1
            }
        }
    }

    private func isLinearized(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: 4_096),
              let text = String(data: prefix, encoding: .isoLatin1) else {
            return false
        }
        return text.contains("/Linearized")
    }

    private func textExtractionCollapsed(
        original: PDFIntegritySnapshot,
        compressed: PDFIntegritySnapshot,
        expectations: PDFIntegrityExpectations
    ) -> Bool {
        let originalCount = original.extractableCharacterCount
        guard originalCount >= expectations.minimumTextCharactersForComparison else {
            return false
        }

        let retainedRatio = Double(compressed.extractableCharacterCount)
            / Double(max(originalCount, 1))
        return retainedRatio < expectations.minimumRetainedTextRatio
    }

    private func appendChangedRisk(
        to risks: inout [PDFIntegrityRisk],
        when condition: Bool,
        code: PDFIntegrityRiskCode,
        message: String,
        originalValue: Int,
        compressedValue: Int
    ) {
        guard condition else { return }
        risks.append(
            PDFIntegrityRisk(
                code: code,
                message: message,
                originalValue: originalValue,
                compressedValue: compressedValue
            )
        )
    }
}
