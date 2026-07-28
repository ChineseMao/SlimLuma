import Foundation
import PDFKit

enum NativePDFOptimizer {
    static func rewrite(inputURL: URL, outputURL: URL) throws {
        guard let document = PDFDocument(url: inputURL), document.pageCount > 0 else {
            throw CompressionError.outputInvalid("PDFKit 无法读取输入文档")
        }

        guard !document.isLocked else {
            throw CompressionError.outputInvalid("PDF 已加密，请先解锁后再压缩")
        }

        guard document.write(to: outputURL) else {
            throw CompressionError.outputInvalid("PDFKit 无法写出文档")
        }
    }
}
