import Foundation
@testable import SlimLumaKit
import XCTest

final class ToolRegistryTests: XCTestCase {
    func testFFmpegRequiresCompanionFFprobeAndUsesReinstallToRepair()
        throws
    {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "slimluma-tool-registry-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let ffmpeg = directory.appendingPathComponent("ffmpeg")
        try makeExecutable(at: ffmpeg)
        let registry = ToolRegistry(searchDirectories: [directory])

        let incomplete = try XCTUnwrap(
            registry.availability().first { $0.kind == .ffmpeg }
        )
        XCTAssertFalse(incomplete.isAvailable)
        XCTAssertEqual(
            incomplete.missingCompanionExecutableName,
            "ffprobe"
        )
        XCTAssertEqual(
            registry.homebrewInstallArguments(for: .ffmpeg),
            ["reinstall", "ffmpeg"]
        )

        try makeExecutable(
            at: directory.appendingPathComponent("ffprobe")
        )
        let complete = try XCTUnwrap(
            registry.availability().first { $0.kind == .ffmpeg }
        )
        XCTAssertTrue(complete.isAvailable)
        XCTAssertNil(complete.missingCompanionExecutableName)
        XCTAssertEqual(
            registry.homebrewInstallArguments(for: .ffmpeg),
            ["install", "ffmpeg"]
        )
    }

    private func makeExecutable(at url: URL) throws {
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }
}
