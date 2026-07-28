import Foundation
@testable import SlimLumaKit
import XCTest

final class ProcessRunnerTests: XCTestCase {
    func testLaunchFailureRemovesRegisteredProcess() async {
        let runner = ProcessRunner()
        let missingExecutable = URL(
            fileURLWithPath:
                "/slimluma-test-missing-\(UUID().uuidString)/executable"
        )

        do {
            _ = try await runner.run(
                executableURL: missingExecutable,
                arguments: []
            )
            XCTFail("A missing executable must fail to launch")
        } catch {
            // The launch error is expected; the registry cleanup is the assertion.
        }

        let activeProcessCount = await runner.activeProcessCount
        XCTAssertEqual(activeProcessCount, 0)
    }

    func testPauseAndResumeActuallySuspendsTheRunningProcess() async throws {
        let runner = ProcessRunner()
        let outputCounter = LockedByteCounter()
        let task = Task {
            try await runner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/yes"),
                arguments: [],
                onOutput: {
                    outputCounter.add($0.text.utf8.count)
                }
            )
        }

        try await Task.sleep(for: .milliseconds(100))
        await runner.pauseAll()
        // Let already-buffered pipe data drain before taking the baseline.
        try await Task.sleep(for: .milliseconds(100))
        let pausedBaseline = outputCounter.value
        try await Task.sleep(for: .milliseconds(200))
        let pausedValue = outputCounter.value
        XCTAssertEqual(pausedValue, pausedBaseline)

        await runner.resumeAll()
        try await Task.sleep(for: .milliseconds(100))
        let resumedValue = outputCounter.value
        XCTAssertGreaterThan(resumedValue, pausedValue)
        await runner.cancelAll()

        let result = try await task.value
        let activeProcessCount = await runner.activeProcessCount
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertEqual(activeProcessCount, 0)
    }
}

private final class LockedByteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func add(_ count: Int) {
        lock.lock()
        storage += count
        lock.unlock()
    }
}
