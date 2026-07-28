import AVFoundation
import Foundation
import PDFKit

enum FileValidator {
    static func validate(
        url: URL,
        kind: MediaKind,
        sourceURL: URL? = nil,
        ffprobeURL: URL? = nil,
        processRunner: ProcessRunner? = nil,
        videoExpectations: VideoIntegrityExpectations = .init(),
        pdfPassword: String? = nil
    ) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CompressionError.outputMissing
        }

        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) > 0 else {
            throw CompressionError.outputInvalid("输出为空或不是普通文件")
        }

        switch kind {
        case .image:
            do {
                let checker = ImageIntegrityChecker()
                if let sourceURL {
                    let report = try checker.compare(
                        originalURL: sourceURL,
                        compressedURL: url
                    )
                    if report.hasCriticalRisk {
                        throw CompressionError.outputInvalid(report.summary)
                    }
                } else {
                    _ = try checker.inspect(url)
                }
            } catch let error as CompressionError {
                throw error
            } catch {
                throw CompressionError.outputInvalid(
                    error.localizedDescription
                )
            }
        case .video:
            do {
                let registry = ToolRegistry()
                let resolvedFFprobe = ffprobeURL
                    ?? registry.locateFFprobe(
                        companionTo: registry.locate(.ffmpeg)
                    )
                let checker = VideoIntegrityChecker(
                    ffprobeURL: resolvedFFprobe,
                    runner: processRunner ?? ProcessRunner()
                )
                if let sourceURL {
                    let report = try await checker.compare(
                        originalURL: sourceURL,
                        compressedURL: url,
                        expectations: videoExpectations
                    )
                    if report.hasCriticalRisk {
                        throw CompressionError.outputInvalid(report.summary)
                    }
                } else {
                    let snapshot = try await checker.inspect(url)
                    guard snapshot.isPlayable,
                          snapshot.videoTrackCount > 0 else {
                        throw CompressionError.outputInvalid(
                            "视频不可播放或不包含画面轨道"
                        )
                    }
                }
            } catch is CancellationError {
                throw CompressionError.cancelled
            } catch let error as CompressionError {
                throw error
            } catch {
                throw CompressionError.outputInvalid(
                    error.localizedDescription
                )
            }
        case .pdf:
            guard let document = PDFDocument(url: url) else {
                throw CompressionError.outputInvalid("PDF 没有可读取页面")
            }
            if document.isLocked,
               let pdfPassword,
               !pdfPassword.isEmpty {
                _ = document.unlock(withPassword: pdfPassword)
            }
            guard !document.isLocked, document.pageCount > 0 else {
                throw CompressionError.outputInvalid(
                    document.isLocked
                        ? "PDF 输出仍处于锁定状态，无法完成完整性验证"
                        : "PDF 没有可读取页面"
                )
            }
        case .unknown:
            throw CompressionError.unsupportedFile(url.lastPathComponent)
        }
    }
}
