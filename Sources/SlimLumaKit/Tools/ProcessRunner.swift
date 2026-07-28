import Foundation

public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String
}

public enum ProcessOutputChannel: Equatable, Sendable {
    case standardOutput
    case standardError
}

public struct ProcessOutputEvent: Sendable {
    public let channel: ProcessOutputChannel
    public let text: String

    public init(channel: ProcessOutputChannel, text: String) {
        self.channel = channel
        self.text = text
    }
}

private final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let maximumBytes: Int

    init(maximumBytes: Int = 1_048_576) {
        self.maximumBytes = maximumBytes
    }

    func append(_ newData: Data) {
        guard !newData.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        let remaining = maximumBytes - data.count
        guard remaining > 0 else { return }
        data.append(newData.prefix(remaining))
    }

    func string() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}

public actor ProcessRunner {
    private var activeProcesses: [UUID: Process] = [:]
    private var isSuspended = false

    public init() {}

    public func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = [:],
        onOutput: (@Sendable (ProcessOutputEvent) -> Void)? = nil
    ) async throws -> ProcessResult {
        try Task.checkCancellation()

        let id = UUID()
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputBuffer = LockedDataBuffer()
        let errorBuffer = LockedDataBuffer()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        var mergedEnvironment = ProcessInfo.processInfo.environment
        environment.forEach { mergedEnvironment[$0.key] = $0.value }
        process.environment = mergedEnvironment

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            outputBuffer.append(data)
            guard !data.isEmpty else { return }
            onOutput?(
                ProcessOutputEvent(
                    channel: .standardOutput,
                    text: String(decoding: data, as: UTF8.self)
                )
            )
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            errorBuffer.append(data)
            guard !data.isEmpty else { return }
            onOutput?(
                ProcessOutputEvent(
                    channel: .standardError,
                    text: String(decoding: data, as: UTF8.self)
                )
            )
        }

        activeProcesses[id] = process
        defer {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            activeProcesses[id] = nil
        }

        let startsSuspended = isSuspended
        return try await withTaskCancellationHandler {
            let exitCode: Int32 = try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { completedProcess in
                    continuation.resume(returning: completedProcess.terminationStatus)
                }

                do {
                    try process.run()
                    if startsSuspended {
                        _ = process.suspend()
                    }
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }

            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            outputBuffer.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
            errorBuffer.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

            if Task.isCancelled {
                throw CompressionError.cancelled
            }

            return ProcessResult(
                exitCode: exitCode,
                standardOutput: outputBuffer.string(),
                standardError: errorBuffer.string()
            )
        } onCancel: {
            Task { await self.terminateProcess(id: id) }
        }
    }

    public func cancelAll() {
        if isSuspended {
            for process in activeProcesses.values where process.isRunning {
                _ = process.resume()
            }
            isSuspended = false
        }
        for process in activeProcesses.values where process.isRunning {
            process.terminate()
        }
    }

    public func pauseAll() {
        guard !isSuspended else { return }
        isSuspended = true
        for process in activeProcesses.values where process.isRunning {
            _ = process.suspend()
        }
    }

    public func resumeAll() {
        guard isSuspended else { return }
        for process in activeProcesses.values where process.isRunning {
            _ = process.resume()
        }
        isSuspended = false
    }

    var activeProcessCount: Int {
        activeProcesses.count
    }

    private func terminateProcess(id: UUID) {
        guard let process = activeProcesses[id], process.isRunning else { return }
        if isSuspended {
            _ = process.resume()
        }
        process.terminate()
    }
}
