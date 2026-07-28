import Foundation

/// Durable handoff between an App Intent invocation and the SwiftUI queue.
///
/// App Intents can finish before the main window and its AppState have appeared.
/// A receipt stored beside the app-owned copies lets the next app activation
/// recover that handoff without retaining access to the original IntentFile.
enum AppIntentImportInbox {
    struct Request: Codable, Identifiable, Sendable {
        let id: UUID
        let createdAt: Date
        let relativePaths: [String]
        let startsCompression: Bool
    }

    struct PendingRequest: Sendable {
        let request: Request
        let receiptURL: URL
        let fileURLs: [URL]
    }

    struct ScanIssue: Sendable {
        let message: String
    }

    struct ScanResult: Sendable {
        let pendingRequests: [PendingRequest]
        let issues: [ScanIssue]
    }

    private static let receiptFilename = ".appintent-request.json"

    static func enqueue(
        importedURLs: [URL],
        batchDirectory: URL,
        startsCompression: Bool,
        importRoot rootOverride: URL? = nil
    ) throws -> PendingRequest {
        let root = try importRoot(rootOverride)
        let standardizedBatch = try validatedBatchDirectory(
            batchDirectory,
            in: root
        )
        let relativePaths = try importedURLs.map { importedURL in
            let standardizedURL = try validatedRegularFile(
                importedURL,
                in: standardizedBatch
            )
            return standardizedURL.lastPathComponent
        }
        guard !relativePaths.isEmpty else {
            throw InboxError.emptyRequest
        }

        let request = Request(
            id: UUID(),
            createdAt: Date(),
            relativePaths: relativePaths,
            startsCompression: startsCompression
        )
        let receiptURL = standardizedBatch.appendingPathComponent(receiptFilename)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(request).write(to: receiptURL, options: [.atomic])

        return PendingRequest(
            request: request,
            receiptURL: receiptURL,
            fileURLs: try importedURLs.map {
                try validatedRegularFile($0, in: standardizedBatch)
            }
        )
    }

    static func pendingRequests(
        importRoot rootOverride: URL? = nil
    ) throws -> [PendingRequest] {
        try scanPendingRequests(
            importRoot: rootOverride
        ).pendingRequests
    }

    static func scanPendingRequests(
        importRoot rootOverride: URL? = nil
    ) throws -> ScanResult {
        let root = try importRoot(rootOverride)
        guard FileManager.default.fileExists(atPath: root.path) else {
            return ScanResult(pendingRequests: [], issues: [])
        }

        let directories = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey
            ],
            options: [.skipsHiddenFiles]
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var pendingRequests: [PendingRequest] = []
        var issues: [ScanIssue] = []

        for directory in directories {
            guard let standardizedDirectory = try? validatedBatchDirectory(
                directory,
                in: root
            ) else {
                continue
            }

            let receiptURL = standardizedDirectory
                .appendingPathComponent(receiptFilename)
            guard FileManager.default.fileExists(atPath: receiptURL.path) else {
                continue
            }
            guard isSafeRegularFile(receiptURL) else {
                issues.append(
                    ScanIssue(
                        message: "发现不安全的快捷指令导入回执，已停止读取。"
                    )
                )
                continue
            }
            guard let data = try? Data(contentsOf: receiptURL),
                  let request = try? decoder.decode(Request.self, from: data),
                  !request.relativePaths.isEmpty else {
                let quarantined = quarantineReceipt(receiptURL)
                issues.append(
                    ScanIssue(
                        message: quarantined
                            ? "一个损坏的快捷指令导入回执已隔离。"
                            : "一个损坏的快捷指令导入回执无法隔离。"
                    )
                )
                continue
            }

            let fileURLs = request.relativePaths.compactMap { relativePath -> URL? in
                guard relativePath == URL(fileURLWithPath: relativePath).lastPathComponent,
                      relativePath != receiptFilename else {
                    return nil
                }
                return try? validatedRegularFile(
                    standardizedDirectory.appendingPathComponent(relativePath),
                    in: standardizedDirectory
                )
            }
            guard fileURLs.count == request.relativePaths.count else {
                let quarantined = quarantineReceipt(receiptURL)
                issues.append(
                    ScanIssue(
                        message: quarantined
                            ? "一个文件缺失的快捷指令导入回执已隔离。"
                            : "一个文件缺失的快捷指令导入回执无法隔离。"
                    )
                )
                continue
            }

            pendingRequests.append(
                PendingRequest(
                    request: request,
                    receiptURL: receiptURL,
                    fileURLs: fileURLs
                )
            )
        }

        return ScanResult(
            pendingRequests: pendingRequests.sorted {
                $0.request.createdAt < $1.request.createdAt
            },
            issues: issues
        )
    }

    static func consume(
        _ pendingRequest: PendingRequest,
        importRoot rootOverride: URL? = nil
    ) throws {
        let root = try importRoot(rootOverride)
        let receiptURL = pendingRequest.receiptURL.standardizedFileURL
        let batchDirectory = try validatedBatchDirectory(
            receiptURL.deletingLastPathComponent(),
            in: root
        )
        guard receiptURL.lastPathComponent == receiptFilename,
              receiptURL.deletingLastPathComponent() == batchDirectory else {
            throw InboxError.invalidReceipt
        }
        if FileManager.default.fileExists(atPath: receiptURL.path) {
            guard isSafeRegularFile(receiptURL) else {
                throw InboxError.invalidReceipt
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let data = try? Data(contentsOf: receiptURL),
                  let storedRequest = try? decoder.decode(
                    Request.self,
                    from: data
                  ),
                  storedRequest.id == pendingRequest.request.id else {
                throw InboxError.receiptChanged
            }
            try FileManager.default.removeItem(at: receiptURL)
        }
    }

    private static func importRoot(_ override: URL?) throws -> URL {
        let root: URL
        if let override {
            root = override.standardizedFileURL
        } else {
            root = try ClipboardImportService.defaultImportRoot()
                .standardizedFileURL
        }

        if FileManager.default.fileExists(atPath: root.path) {
            let values = try root.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            guard values.isDirectory == true,
                  values.isSymbolicLink != true else {
                throw InboxError.invalidImportRoot
            }
        }
        return root
    }

    private static func validatedBatchDirectory(
        _ batchDirectory: URL,
        in root: URL
    ) throws -> URL {
        let standardizedBatch = batchDirectory.standardizedFileURL
        guard standardizedBatch.deletingLastPathComponent() == root else {
            throw InboxError.invalidImportedFile
        }
        let values = try standardizedBatch.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        guard values.isDirectory == true,
              values.isSymbolicLink != true else {
            throw InboxError.invalidImportedFile
        }
        return standardizedBatch
    }

    private static func validatedRegularFile(
        _ fileURL: URL,
        in batchDirectory: URL
    ) throws -> URL {
        let standardizedURL = fileURL.standardizedFileURL
        guard standardizedURL.deletingLastPathComponent() == batchDirectory,
              standardizedURL.lastPathComponent != receiptFilename,
              isSafeRegularFile(standardizedURL) else {
            throw InboxError.invalidImportedFile
        }
        return standardizedURL
    }

    private static func isSafeRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        ) else {
            return false
        }
        return values.isRegularFile == true
            && values.isSymbolicLink != true
    }

    private static func quarantineReceipt(_ receiptURL: URL) -> Bool {
        guard isSafeRegularFile(receiptURL) else { return false }
        let quarantineURL = receiptURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                "\(receiptFilename).invalid-\(UUID().uuidString)"
            )
        do {
            try FileManager.default.moveItem(
                at: receiptURL,
                to: quarantineURL
            )
            return true
        } catch {
            return false
        }
    }

    enum InboxError: LocalizedError {
        case emptyRequest
        case invalidImportedFile
        case invalidReceipt
        case invalidImportRoot
        case receiptChanged

        var errorDescription: String? {
            switch self {
            case .emptyRequest:
                "快捷指令没有提供可导入文件。"
            case .invalidImportedFile:
                "快捷指令导入文件不在 SlimLuma 的安全暂存目录中。"
            case .invalidReceipt:
                "快捷指令导入回执不在 SlimLuma 的安全目录中。"
            case .invalidImportRoot:
                "SlimLuma 的快捷指令暂存目录不安全或不可用。"
            case .receiptChanged:
                "快捷指令导入回执已被另一项请求替换，未执行清理。"
            }
        }
    }
}
