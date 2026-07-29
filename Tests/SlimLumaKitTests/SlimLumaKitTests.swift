import CoreGraphics
import Darwin
import Foundation
import ImageIO
@testable import SlimLumaKit
import UniformTypeIdentifiers
import XCTest

final class SlimLumaKitTests: XCTestCase {
    func testMediaKindDetectsSupportedExtensionsCaseInsensitively() {
        XCTAssertEqual(
            MediaKind.detect(url: URL(fileURLWithPath: "/tmp/photo.AVIF")),
            .image
        )
        XCTAssertEqual(
            MediaKind.detect(url: URL(fileURLWithPath: "/tmp/clip.MOV")),
            .video
        )
        XCTAssertEqual(
            MediaKind.detect(url: URL(fileURLWithPath: "/tmp/book.PDF")),
            .pdf
        )
        XCTAssertEqual(
            MediaKind.detect(url: URL(fileURLWithPath: "/tmp/archive.zip")),
            .unknown
        )
    }

    func testOutputPlannerNeverReturnsInputPathAndAvoidsCollisions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SlimLumaTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("photo.jpg")
        try Data([0x01]).write(to: input)
        let existingOutput = directory.appendingPathComponent("photo-slim.jpg")
        try Data([0x02]).write(to: existingOutput)

        let destination = try OutputPlanner().destinationURL(
            for: input,
            kind: .image,
            settings: .default
        )

        XCTAssertEqual(destination.lastPathComponent, "photo-slim-2.jpg")
        XCTAssertNotEqual(destination.standardizedFileURL, input.standardizedFileURL)
    }

    func testOutputPlannerUsesConvertedImageExtension() throws {
        var settings = CompressionSettings.default
        settings.image.format = .webp
        let input = URL(fileURLWithPath: "/tmp/a picture.png")
        let destination = try OutputPlanner().destinationURL(
            for: input,
            kind: .image,
            settings: settings
        )
        XCTAssertEqual(destination.pathExtension, "webp")
    }

    func testOutputPlannerCreatesPrivateTemporaryWorkspace() throws {
        let planner = OutputPlanner()
        let input = URL(fileURLWithPath: "/tmp/private-source.pdf")
        let lease = try planner.temporaryWorkspace(
            for: input,
            kind: .pdf,
            settings: .default
        )
        let temporary = lease.outputURL
        let workspace = temporary.deletingLastPathComponent()
        defer { try? lease.remove() }

        let permissions = try FileManager.default.attributesOfItem(
            atPath: workspace.path
        )[.posixPermissions] as? NSNumber
        let lockPermissions = try FileManager.default.attributesOfItem(
            atPath: workspace.appendingPathComponent(".workspace.lock").path
        )[.posixPermissions] as? NSNumber

        XCTAssertEqual(permissions?.intValue, 0o700)
        XCTAssertEqual(lockPermissions?.intValue, 0o600)
        XCTAssertTrue(workspace.lastPathComponent.hasPrefix("work-"))
        XCTAssertEqual(temporary.pathExtension, "pdf")
    }

    func testOutputPlannerRemovesOnlyStaleTemporaryWorkspaces() throws {
        let planner = OutputPlanner()
        let input = URL(fileURLWithPath: "/tmp/stale-source.pdf")
        var staleLease: TemporaryWorkspaceLease? =
            try planner.temporaryWorkspace(
                for: input,
                kind: .pdf,
                settings: .default
            )
        let activeLease = try planner.temporaryWorkspace(
            for: input,
            kind: .pdf,
            settings: .default
        )
        let staleWorkspace = try XCTUnwrap(staleLease).outputURL
            .deletingLastPathComponent()
        let activeWorkspace = activeLease.outputURL.deletingLastPathComponent()
        defer {
            try? FileManager.default.removeItem(at: staleWorkspace)
            try? activeLease.remove()
        }

        let now = Date()
        staleLease = nil
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-120)],
            ofItemAtPath: staleWorkspace.path
        )
        planner.removeStaleTemporaryWorkspaces(
            now: now,
            maximumAge: 60
        )

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: staleWorkspace.path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: activeWorkspace.path)
        )
    }

    func testOutputPlannerPreservesOldButLockedTemporaryWorkspace() throws {
        let planner = OutputPlanner()
        let input = URL(fileURLWithPath: "/tmp/long-running-source.pdf")
        let activeLease = try planner.temporaryWorkspace(
            for: input,
            kind: .pdf,
            settings: .default
        )
        let activeWorkspace = activeLease.outputURL.deletingLastPathComponent()
        defer { try? activeLease.remove() }

        let now = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-120)],
            ofItemAtPath: activeWorkspace.path
        )
        planner.removeStaleTemporaryWorkspaces(
            now: now,
            maximumAge: 60
        )

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: activeWorkspace.path)
        )
    }

    func testOutputPlannerRemovesInactiveWorkspaceOnNextJob() throws {
        let planner = OutputPlanner()
        let input = URL(fileURLWithPath: "/tmp/restarted-source.pdf")
        var abandonedLease: TemporaryWorkspaceLease? =
            try planner.temporaryWorkspace(
                for: input,
                kind: .pdf,
                settings: .default
            )
        let abandonedWorkspace = try XCTUnwrap(abandonedLease).outputURL
            .deletingLastPathComponent()
        defer {
            try? FileManager.default.removeItem(at: abandonedWorkspace)
        }

        abandonedLease = nil
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-1)],
            ofItemAtPath: abandonedWorkspace.path
        )
        let nextLease = try planner.temporaryWorkspace(
            for: input,
            kind: .pdf,
            settings: .default
        )
        defer { try? nextLease.remove() }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: abandonedWorkspace.path)
        )
    }

    func testOutputPlannerDoesNotDeleteUnmarkedLookalikeWorkspace() throws {
        let planner = OutputPlanner()
        let input = URL(fileURLWithPath: "/tmp/lookalike-source.pdf")
        let lease = try planner.temporaryWorkspace(
            for: input,
            kind: .pdf,
            settings: .default
        )
        let root = lease.outputURL.deletingLastPathComponent()
            .deletingLastPathComponent()
        try lease.remove()

        let lookalike = root.appendingPathComponent(
            "work-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: lookalike,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: lookalike) }

        let now = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-120)],
            ofItemAtPath: lookalike.path
        )
        planner.removeStaleTemporaryWorkspaces(
            now: now,
            maximumAge: 60
        )

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: lookalike.path)
        )
    }

    func testOutputPlannerExposesTheSameSanitizedSuffixUsedForLoopPrevention() {
        let planner = OutputPlanner()

        XCTAssertEqual(
            planner.sanitizedFilenameSuffix(" /private:share\\ "),
            "-private-share-"
        )
        XCTAssertEqual(planner.sanitizedFilenameSuffix("   "), "-slim")
    }

    func testOutputFinalizerRefusesCancelledTaskBeforeMove() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SlimLumaFinalizeTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("source.mp4")
        let temporary = directory.appendingPathComponent(".pending.mp4")
        try Data([0x01]).write(to: input)
        try Data([0x02]).write(to: temporary)

        var settings = CompressionSettings.default
        settings.output.location = .customDirectory
        settings.output.customDirectoryPath = directory.path

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await OutputFinalizer().finalize(
                temporaryURL: temporary,
                inputURL: input,
                kind: .video,
                settings: settings,
                planner: OutputPlanner()
            )
        }

        do {
            _ = try await task.value
            XCTFail("A cancelled task must not finalize an output")
        } catch is CancellationError {
            // Expected.
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: temporary.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("source-slim.mp4").path
            )
        )
    }

    func testOutputFinalizerCopiesToSiblingBeforeAtomicRename() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SlimLumaFinalizeTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let workspace = root.appendingPathComponent(
            "private-workspace",
            isDirectory: true
        )
        let outputDirectory = root.appendingPathComponent(
            "selected-output",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: workspace,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let input = root.appendingPathComponent("source.pdf")
        let temporary = workspace.appendingPathComponent("pending.pdf")
        let expected = Data([0x25, 0x50, 0x44, 0x46])
        try Data([0x01]).write(to: input)
        try expected.write(to: temporary)

        var settings = CompressionSettings.default
        settings.output.location = .customDirectory
        settings.output.customDirectoryPath = outputDirectory.path

        let finalURL = try await OutputFinalizer().finalize(
            temporaryURL: temporary,
            inputURL: input,
            kind: .pdf,
            settings: settings,
            planner: OutputPlanner()
        )

        XCTAssertEqual(finalURL.lastPathComponent, "source-slim.pdf")
        XCTAssertEqual(try Data(contentsOf: finalURL), expected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(
                atPath: outputDirectory.path
            ).contains { $0.hasPrefix(".slimluma-finalize-") }
        )
    }

    func testOutputFinalizerReturnsMovedOutputDirectoryPath() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SlimLumaFinalizeTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let workspace = root.appendingPathComponent(
            "private-workspace",
            isDirectory: true
        )
        let originalOutputDirectory = root.appendingPathComponent(
            "selected-output",
            isDirectory: true
        )
        let movedOutputDirectory = root.appendingPathComponent(
            "renamed-output",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: workspace,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: originalOutputDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let input = root.appendingPathComponent("source.pdf")
        let temporary = workspace.appendingPathComponent("pending.pdf")
        try Data([0x01]).write(to: input)
        try Data(repeating: 0x41, count: 32 * 1_024 * 1_024).write(
            to: temporary
        )
        var settings = CompressionSettings.default
        settings.output.location = .customDirectory
        settings.output.customDirectoryPath =
            originalOutputDirectory.path

        let finalizeTask = Task {
            try await OutputFinalizer().finalize(
                temporaryURL: temporary,
                inputURL: input,
                kind: .pdf,
                settings: settings,
                planner: OutputPlanner()
            )
        }

        var observedStagingDirectory: URL?
        for _ in 0..<2_000 {
            let names = try FileManager.default.contentsOfDirectory(
                atPath: originalOutputDirectory.path
            )
            if let name = names.first(where: {
                $0.hasPrefix(".slimluma-finalize-")
            }) {
                let candidate = originalOutputDirectory
                    .appendingPathComponent(name, isDirectory: true)
                if FileManager.default.fileExists(
                    atPath: candidate.appendingPathComponent(
                        ".staging.lock"
                    ).path
                ),
                FileManager.default.fileExists(
                    atPath: candidate.appendingPathComponent(
                        "payload"
                    ).path
                ) {
                    observedStagingDirectory = candidate
                    break
                }
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let stagingDirectory = try XCTUnwrap(
            observedStagingDirectory
        )
        let stagingPermissions =
            try FileManager.default.attributesOfItem(
                atPath: stagingDirectory.path
            )[.posixPermissions] as? NSNumber
        let markerPermissions =
            try FileManager.default.attributesOfItem(
                atPath: stagingDirectory.appendingPathComponent(
                    ".staging.lock"
                ).path
            )[.posixPermissions] as? NSNumber
        let payloadPermissions =
            try FileManager.default.attributesOfItem(
                atPath: stagingDirectory.appendingPathComponent(
                    "payload"
                ).path
            )[.posixPermissions] as? NSNumber
        XCTAssertEqual(stagingPermissions?.intValue, 0o700)
        XCTAssertEqual(markerPermissions?.intValue, 0o600)
        XCTAssertEqual(payloadPermissions?.intValue, 0o600)
        try FileManager.default.moveItem(
            at: originalOutputDirectory,
            to: movedOutputDirectory
        )

        let finalURL = try await finalizeTask.value

        XCTAssertEqual(
            finalURL.deletingLastPathComponent().standardizedFileURL,
            movedOutputDirectory.standardizedFileURL
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: finalURL.path)
        )
    }

    func testOutputFinalizerRemovesOldInactiveStagingFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SlimLumaFinalizeTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let oldStaging = try createFinalizationStagingFixture(
            in: directory,
            modifiedAt: Date().addingTimeInterval(-25 * 60 * 60)
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o400],
            ofItemAtPath: oldStaging.payload.path
        )

        let input = directory.appendingPathComponent("source.pdf")
        let temporary = directory.appendingPathComponent("pending.pdf")
        try Data([0x01]).write(to: input)
        try Data([0x25, 0x50, 0x44, 0x46]).write(to: temporary)
        var settings = CompressionSettings.default
        settings.output.location = .customDirectory
        settings.output.customDirectoryPath = directory.path

        _ = try await OutputFinalizer().finalize(
            temporaryURL: temporary,
            inputURL: input,
            kind: .pdf,
            settings: settings,
            planner: OutputPlanner()
        )

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: oldStaging.payload.path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: oldStaging.marker.path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: oldStaging.directory.path
            )
        )
    }

    func testOutputFinalizerPreservesUnownedStagingLookalikes() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SlimLumaFinalizeTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let unmarked = directory.appendingPathComponent(
            ".slimluma-finalize-\(UUID().uuidString).stage",
            isDirectory: true
        )
        let invalidlyMarked = directory.appendingPathComponent(
            ".slimluma-finalize-\(UUID().uuidString).stage",
            isDirectory: true
        )
        let prefixedMarker = directory.appendingPathComponent(
            ".slimluma-finalize-\(UUID().uuidString).stage",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: unmarked,
            withIntermediateDirectories: false
        )
        try FileManager.default.createDirectory(
            at: invalidlyMarked,
            withIntermediateDirectories: false
        )
        try FileManager.default.createDirectory(
            at: prefixedMarker,
            withIntermediateDirectories: false
        )
        try Data([0x10]).write(
            to: unmarked.appendingPathComponent("payload")
        )
        try Data([0x20]).write(
            to: invalidlyMarked.appendingPathComponent("payload")
        )
        try Data([0x30]).write(
            to: prefixedMarker.appendingPathComponent("payload")
        )
        let invalidMarker = invalidlyMarked.appendingPathComponent(
            ".staging.lock"
        )
        try Data("not a SlimLuma marker\n".utf8).write(to: invalidMarker)
        let validPrefixMarker = prefixedMarker.appendingPathComponent(
            ".staging.lock"
        )
        try Data(
            "SlimLuma finalization staging v1\nuntrusted suffix".utf8
        ).write(to: validPrefixMarker)
        let oldDate = Date().addingTimeInterval(-25 * 60 * 60)
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: unmarked.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: invalidlyMarked.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: oldDate],
            ofItemAtPath: prefixedMarker.path
        )

        let input = directory.appendingPathComponent("source.pdf")
        let temporary = directory.appendingPathComponent("pending.pdf")
        try Data([0x01]).write(to: input)
        try Data([0x25, 0x50, 0x44, 0x46]).write(to: temporary)
        var settings = CompressionSettings.default
        settings.output.location = .customDirectory
        settings.output.customDirectoryPath = directory.path

        _ = try await OutputFinalizer().finalize(
            temporaryURL: temporary,
            inputURL: input,
            kind: .pdf,
            settings: settings,
            planner: OutputPlanner()
        )

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: unmarked.path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: invalidlyMarked.path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: invalidMarker.path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: prefixedMarker.path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: validPrefixMarker.path
            )
        )
    }

    func testOutputFinalizerPreservesOldLockedStagingFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SlimLumaFinalizeTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let lockedStaging = try createFinalizationStagingFixture(
            in: directory,
            modifiedAt: Date().addingTimeInterval(-25 * 60 * 60)
        )
        let descriptor = Darwin.open(
            lockedStaging.marker.path,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW
        )
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        guard descriptor >= 0 else { return }
        XCTAssertEqual(slimLumaFlock(descriptor, LOCK_EX | LOCK_NB), 0)
        defer {
            _ = slimLumaFlock(descriptor, LOCK_UN)
            _ = Darwin.close(descriptor)
        }
        let input = directory.appendingPathComponent("source.pdf")
        let temporary = directory.appendingPathComponent("pending.pdf")
        try Data([0x01]).write(to: input)
        try Data([0x25, 0x50, 0x44, 0x46]).write(to: temporary)
        var settings = CompressionSettings.default
        settings.output.location = .customDirectory
        settings.output.customDirectoryPath = directory.path

        _ = try await OutputFinalizer().finalize(
            temporaryURL: temporary,
            inputURL: input,
            kind: .pdf,
            settings: settings,
            planner: OutputPlanner()
        )

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: lockedStaging.payload.path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: lockedStaging.marker.path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: lockedStaging.directory.path
            )
        )
    }

    func testOutputFinalizerPreservesRecentUnlockedStagingFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SlimLumaFinalizeTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let recentStaging = try createFinalizationStagingFixture(
            in: directory
        )

        let input = directory.appendingPathComponent("source.pdf")
        let temporary = directory.appendingPathComponent("pending.pdf")
        try Data([0x01]).write(to: input)
        try Data([0x25, 0x50, 0x44, 0x46]).write(to: temporary)
        var settings = CompressionSettings.default
        settings.output.location = .customDirectory
        settings.output.customDirectoryPath = directory.path

        _ = try await OutputFinalizer().finalize(
            temporaryURL: temporary,
            inputURL: input,
            kind: .pdf,
            settings: settings,
            planner: OutputPlanner()
        )

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: recentStaging.payload.path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: recentStaging.marker.path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: recentStaging.directory.path
            )
        )
    }

    func testOutputFinalizerRemovesOwnStagingAfterCopyFailure() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SlimLumaFinalizeTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("source.pdf")
        let missing = directory.appendingPathComponent("missing.pdf")
        let linkedTemporary = directory.appendingPathComponent("pending.pdf")
        try Data([0x01]).write(to: input)
        try FileManager.default.createSymbolicLink(
            at: linkedTemporary,
            withDestinationURL: missing
        )
        var settings = CompressionSettings.default
        settings.output.location = .customDirectory
        settings.output.customDirectoryPath = directory.path

        do {
            _ = try await OutputFinalizer().finalize(
                temporaryURL: linkedTemporary,
                inputURL: input,
                kind: .pdf,
                settings: settings,
                planner: OutputPlanner()
            )
            XCTFail("A symbolic-link temporary result must be rejected")
        } catch let error as CompressionError {
            guard case .outputInvalid = error else {
                return XCTFail("Expected outputInvalid, got \(error)")
            }
        }

        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: linkedTemporary.path
            ),
            missing.path
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(
                    "source-slim.pdf"
                ).path
            )
        )
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(
                atPath: directory.path
            ).contains { $0.hasPrefix(".slimluma-finalize-") }
        )
    }

    private func createFinalizationStagingFixture(
        in directory: URL,
        modifiedAt: Date? = nil
    ) throws -> (directory: URL, payload: URL, marker: URL) {
        let stagingDirectory = directory.appendingPathComponent(
            ".slimluma-finalize-\(UUID().uuidString).stage",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let payload = stagingDirectory.appendingPathComponent("payload")
        let marker = stagingDirectory.appendingPathComponent(
            ".staging.lock"
        )
        try Data([0x00]).write(to: payload)
        try Data(
            "SlimLuma finalization staging v1\n".utf8
        ).write(to: marker)
        if let modifiedAt {
            try FileManager.default.setAttributes(
                [.modificationDate: modifiedAt],
                ofItemAtPath: stagingDirectory.path
            )
        }
        return (stagingDirectory, payload, marker)
    }

    func testImageMagickArgumentsKeepPathsAsSingleArguments() {
        let input = URL(fileURLWithPath: "/tmp/in folder/one image.png")
        let output = URL(fileURLWithPath: "/tmp/out folder/result.webp")
        let settings = ImageCompressionSettings(
            format: .webp,
            quality: 81,
            maxWidth: 1920,
            maxHeight: 1080,
            metadata: .removeAll
        )

        let arguments = ImageMagickCommandBuilder.arguments(
            input: input,
            output: output,
            settings: settings
        )

        XCTAssertEqual(arguments.first, input.path)
        XCTAssertEqual(arguments.last, output.path)
        XCTAssertTrue(arguments.contains("1920x1080>"))
        XCTAssertTrue(arguments.contains("81"))
    }

    func testImageMagickCanRestoreColorProfileAfterRemovingAllMetadata() {
        let input = URL(fileURLWithPath: "/tmp/in.jpg")
        let output = URL(fileURLWithPath: "/tmp/out.jpg")
        let profile = URL(fileURLWithPath: "/tmp/source.icc")
        let settings = ImageCompressionSettings(
            metadata: .removeAll,
            preserveColorProfile: true
        )

        let arguments = ImageMagickCommandBuilder.arguments(
            input: input,
            output: output,
            settings: settings,
            restoredICCProfileURL: profile
        )

        XCTAssertTrue(arguments.contains("-strip"))
        guard let profileIndex = arguments.firstIndex(of: "-profile") else {
            return XCTFail("Expected the extracted ICC profile to be restored")
        }
        XCTAssertEqual(arguments[profileIndex + 1], profile.path)
        XCTAssertLessThan(
            arguments.firstIndex(of: "-strip")!,
            profileIndex,
            "Metadata must be stripped before the preserved ICC profile is restored"
        )
    }

    func testSipsFallbackRespectsIndependentWidthAndHeightLimits() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SlimLumaSipsBuilderTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("source.png")
        let output = directory.appendingPathComponent("output.png")
        try makeSolidImage(
            at: input,
            type: .png,
            width: 400,
            height: 200
        )

        let arguments = try SipsCommandBuilder.arguments(
            input: input,
            output: output,
            settings: ImageCompressionSettings(
                format: .png,
                maxWidth: 100,
                maxHeight: 100,
                preserveColorProfile: false
            )
        )

        guard let resizeIndex = arguments.firstIndex(
            of: "--resampleHeightWidth"
        ) else {
            return XCTFail("Expected an exact aspect-ratio resize command")
        }
        XCTAssertEqual(arguments[resizeIndex + 1], "50")
        XCTAssertEqual(arguments[resizeIndex + 2], "100")
        XCTAssertFalse(arguments.contains("--resampleHeightWidthMax"))
    }

    func testLosslessJPEGIsRejectedBeforeAnyEngineRuns() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SlimLumaLosslessCompatibilityTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("source.jpg")
        try makeSolidImage(
            at: input,
            type: .jpeg,
            width: 24,
            height: 16
        )

        var settings = CompressionSettings.default
        settings.image.lossless = true
        settings.image.format = .keep

        do {
            _ = try await CompressionCoordinator().compress(
                inputURL: input,
                settings: settings
            )
            XCTFail("JPEG must not be presented as a lossless re-encode")
        } catch CompressionError.invalidSettings(let message) {
            XCTAssertTrue(message.contains("逐像素无损"), message)
            XCTAssertTrue(message.contains("PNG"), message)
            XCTAssertTrue(message.contains("WebP"), message)
        }
    }

    func testFFmpegArgumentsUseVideoToolboxWhenRequested() throws {
        let settings = VideoCompressionSettings(
            codec: .hevc,
            quality: 75,
            hardwareAcceleration: true,
            maxWidth: 1920,
            maxHeight: 1080
        )

        let arguments = try FFmpegCommandBuilder.arguments(
            input: URL(fileURLWithPath: "/tmp/in.mov"),
            output: URL(fileURLWithPath: "/tmp/out.mp4"),
            settings: settings
        )

        XCTAssertTrue(arguments.contains("hevc_videotoolbox"))
        XCTAssertTrue(arguments.contains("-map_metadata"))
        XCTAssertTrue(arguments.contains("0:s?"))
        XCTAssertTrue(arguments.contains("mov_text"))
        XCTAssertFalse(
            arguments.contains { $0.contains("force_divisible_by") },
            "Scale filters should remain compatible with older supported FFmpeg builds"
        )
        XCTAssertEqual(arguments.last, "/tmp/out.mp4")
    }

    func testCompressionResultReportsRetainedLargerOutputExplicitly() {
        let result = CompressionResult(
            inputURL: URL(fileURLWithPath: "/tmp/original.pdf"),
            outputURL: URL(fileURLWithPath: "/tmp/output.pdf"),
            mediaKind: .pdf,
            engineName: "Test",
            originalBytes: 1_000,
            outputBytes: 1_250,
            duration: 1,
            skippedBecauseLarger: false
        )

        XCTAssertEqual(result.sizeDeltaBytes, 250)
        XCTAssertTrue(result.isLargerThanOriginal)
        XCTAssertTrue(result.isNotSmallerThanOriginal)
        XCTAssertEqual(result.savedBytes, 0)
    }

    func testCompressionResultDoesNotTreatMissingOutputAsLarger() {
        let result = CompressionResult(
            inputURL: URL(fileURLWithPath: "/tmp/original.pdf"),
            outputURL: nil,
            mediaKind: .pdf,
            engineName: "Test",
            originalBytes: 1_000,
            outputBytes: nil,
            duration: 1,
            skippedBecauseLarger: true
        )

        XCTAssertNil(result.sizeDeltaBytes)
        XCTAssertFalse(result.isLargerThanOriginal)
        XCTAssertFalse(result.isNotSmallerThanOriginal)
    }

    func testCompressionResultPersistsStableEngineIdentity() throws {
        let result = CompressionResult(
            inputURL: URL(fileURLWithPath: "/tmp/original.pdf"),
            outputURL: URL(fileURLWithPath: "/tmp/output.pdf"),
            mediaKind: .pdf,
            engineName: "Localized display label",
            engineID: .macOSPDFKit,
            originalBytes: 1_000,
            outputBytes: 900,
            duration: 1,
            skippedBecauseLarger: false
        )

        let decoded = try JSONDecoder().decode(
            CompressionResult.self,
            from: JSONEncoder().encode(result)
        )

        XCTAssertEqual(decoded.engineID, .macOSPDFKit)
        XCTAssertEqual(decoded.engineName, "Localized display label")
    }

    func testCompressionResultDecodesLegacyPayloadWithoutEngineIdentity() throws {
        let result = CompressionResult(
            inputURL: URL(fileURLWithPath: "/tmp/original.pdf"),
            outputURL: nil,
            mediaKind: .pdf,
            engineName: "macOS PDFKit",
            originalBytes: 1_000,
            outputBytes: nil,
            duration: 1,
            skippedBecauseLarger: true
        )
        let encoded = try JSONEncoder().encode(result)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded)
                as? [String: Any]
        )
        object.removeValue(forKey: "engineID")

        let decoded = try JSONDecoder().decode(
            CompressionResult.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.engineID, .macOSPDFKit)
    }

    func testCompressionErrorCarriesTypedRecoveryTool() {
        let error = CompressionError.missingTool(
            name: "任意展示名称",
            installCommand: "brew install qpdf",
            tool: .qpdf
        )

        XCTAssertEqual(error.recoveryTool, .qpdf)
        XCTAssertFalse(error.isCancellation)
        XCTAssertFalse(error.isOutputValidationFailure)
        XCTAssertTrue(CompressionError.cancelled.isCancellation)
        XCTAssertTrue(
            CompressionError.outputInvalid("broken")
                .isOutputValidationFailure
        )
    }

    private func makeSolidImage(
        at url: URL,
        type: UTType,
        width: Int,
        height: Int
    ) throws {
        let bytesPerRow = width * 4
        let pixels = [UInt8](
            repeating: 0x7F,
            count: bytesPerRow * height
        )
        guard let provider = CGDataProvider(
            data: Data(pixels) as CFData
        ),
        let colorSpace = CGColorSpace(
            name: CGColorSpace.sRGB
        ),
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ),
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw CompressionError.outputInvalid(
                "无法创建测试图片"
            )
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CompressionError.outputInvalid(
                "无法写出测试图片"
            )
        }
    }

    func testFFmpegArgumentsUseSVTAV1WhenThatEncoderIsAvailable() throws {
        let settings = VideoCompressionSettings(
            codec: .av1,
            quality: 60,
            speed: .balanced,
            hardwareAcceleration: false
        )
        let arguments = try FFmpegCommandBuilder.arguments(
            input: URL(fileURLWithPath: "/tmp/in.mov"),
            output: URL(fileURLWithPath: "/tmp/out.mkv"),
            settings: settings,
            av1Encoder: .svtAV1
        )

        XCTAssertTrue(arguments.contains("libsvtav1"))
        XCTAssertTrue(arguments.contains("-crf"))
        XCTAssertTrue(arguments.contains("-preset"))
        XCTAssertFalse(arguments.contains("-cpu-used"))
    }

    func testFFmpegArgumentsUseLibaomSpecificSpeedOption() throws {
        let settings = VideoCompressionSettings(
            codec: .av1,
            quality: 60,
            speed: .balanced,
            hardwareAcceleration: false
        )
        let arguments = try FFmpegCommandBuilder.arguments(
            input: URL(fileURLWithPath: "/tmp/in.mov"),
            output: URL(fileURLWithPath: "/tmp/out.mkv"),
            settings: settings,
            av1Encoder: .libaomAV1
        )

        XCTAssertTrue(arguments.contains("libaom-av1"))
        XCTAssertTrue(arguments.contains("-cpu-used"))
    }

    func testFFmpegCapabilitiesPreferSVTAV1AndExplainMissingSupport() throws {
        let capabilities = FFmpegCapabilities.parse(
            """
             V..... libaom-av1           libaom AV1
             V..... libsvtav1            SVT-AV1
             V..... libx264              H.264
            """
        )

        XCTAssertEqual(try capabilities.requireAV1Encoder(), .svtAV1)

        let unsupported = FFmpegCapabilities.parse(
            " V..... libx264              H.264"
        )
        XCTAssertThrowsError(try unsupported.requireAV1Encoder()) { error in
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("libsvtav1"))
            XCTAssertTrue(message.contains("libaom-av1"))
            XCTAssertTrue(message.contains("H.264"))
        }
    }

    func testQPDFLosslessDoesNotEnableImageReencoding() {
        let settings = PDFCompressionSettings(mode: .lossless)
        let arguments = QPDFCommandBuilder.arguments(
            input: URL(fileURLWithPath: "/tmp/in.pdf"),
            output: URL(fileURLWithPath: "/tmp/out.pdf"),
            settings: settings
        )

        XCTAssertFalse(arguments.contains("--optimize-images"))
        XCTAssertTrue(arguments.contains("--object-streams=generate"))
    }

    func testQPDFBalancedUsesConfiguredJPEGQuality() {
        let settings = PDFCompressionSettings(mode: .balanced, imageQuality: 73)
        let arguments = QPDFCommandBuilder.arguments(
            input: URL(fileURLWithPath: "/tmp/in.pdf"),
            output: URL(fileURLWithPath: "/tmp/out.pdf"),
            settings: settings
        )

        XCTAssertTrue(arguments.contains("--optimize-images"))
        XCTAssertTrue(arguments.contains("--jpeg-quality=73"))
    }

    func testQPDFHasDedicatedRepairAndLinearizationStages() {
        let input = URL(fileURLWithPath: "/tmp/in.pdf")
        let repaired = URL(fileURLWithPath: "/tmp/repaired.pdf")
        let output = URL(fileURLWithPath: "/tmp/out.pdf")

        XCTAssertEqual(
            QPDFCommandBuilder.repairArguments(input: input, output: repaired),
            [input.path, repaired.path]
        )
        XCTAssertEqual(
            QPDFCommandBuilder.linearizeArguments(input: repaired, output: output),
            [repaired.path, output.path, "--linearize"]
        )
    }

    func testGhostscriptAppliesFastWebViewOnlyWhenItOwnsLinearization() {
        let settings = PDFCompressionSettings(linearizeForWeb: true)
        let input = URL(fileURLWithPath: "/tmp/in.pdf")
        let output = URL(fileURLWithPath: "/tmp/out.pdf")

        let directArguments = GhostscriptCommandBuilder.arguments(
            input: input,
            output: output,
            settings: settings
        )
        let qpdfPipelineArguments = GhostscriptCommandBuilder.arguments(
            input: input,
            output: output,
            settings: settings,
            linearizeInGhostscript: false
        )

        XCTAssertTrue(directArguments.contains("-dFastWebView=true"))
        XCTAssertFalse(qpdfPipelineArguments.contains("-dFastWebView=true"))
    }

    func testGhostscriptLosslessModeOmitsLossyImageControls() {
        let settings = PDFCompressionSettings(
            mode: .lossless,
            imageQuality: 25,
            imageDPI: 72,
            grayscale: true
        )
        let arguments = GhostscriptCommandBuilder.arguments(
            input: URL(fileURLWithPath: "/tmp/in.pdf"),
            output: URL(fileURLWithPath: "/tmp/out.pdf"),
            settings: settings
        )

        XCTAssertFalse(arguments.contains("-dJPEGQ=25"))
        XCTAssertFalse(arguments.contains("-dColorImageResolution=72"))
        XCTAssertFalse(arguments.contains("-sColorConversionStrategy=Gray"))
        XCTAssertTrue(arguments.contains("-dPDFSETTINGS=/prepress"))
    }

    func testTargetVideoArgumentsUseTwoPassSoftwareEncodingAndPreserveChapters() throws {
        let settings = VideoCompressionSettings(
            codec: .h264,
            targetSizeBytes: 5 * 1_024 * 1_024,
            speed: .balanced,
            hardwareAcceleration: true,
            audioBitrate: 128,
            removeMetadata: true,
            preserveChapters: true
        )
        let passes = try FFmpegCommandBuilder.targetArguments(
            input: URL(fileURLWithPath: "/tmp/in.mov"),
            output: URL(fileURLWithPath: "/tmp/out.mp4"),
            settings: settings,
            durationSeconds: 30,
            audioTrackCount: 1,
            passlogURL: URL(fileURLWithPath: "/tmp/passlog")
        )

        XCTAssertEqual(passes.count, 2)
        XCTAssertTrue(passes[0].contains("libx264"))
        XCTAssertFalse(passes[0].contains("h264_videotoolbox"))
        XCTAssertTrue(passes[0].contains("1"))
        XCTAssertTrue(passes[1].contains("2"))
        XCTAssertTrue(passes[1].contains("-map_chapters"))
        let chapterIndex = try XCTUnwrap(
            passes[1].firstIndex(of: "-map_chapters")
        )
        XCTAssertEqual(passes[1][chapterIndex + 1], "0")
    }

    func testVideoSettingsDecodeOlderPayloadWithSafeChapterDefault() throws {
        let settings = VideoCompressionSettings(
            codec: .hevc,
            quality: 80,
            preserveChapters: false
        )
        let data = try JSONEncoder().encode(settings)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object.removeValue(forKey: "preserveChapters")
        object.removeValue(forKey: "targetSizeBytes")

        let decoded = try JSONDecoder().decode(
            VideoCompressionSettings.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertTrue(decoded.preserveChapters)
        XCTAssertNil(decoded.targetSizeBytes)
    }

    func testPresetExchangeDocumentRoundTripsTargetSettings() throws {
        var settings = CompressionSettings.default
        settings.image.targetSizeBytes = 750_000
        settings.video.targetSizeBytes = 25_000_000
        let document = PresetExchangeDocument(
            presets: [
                CompressionPreset(
                    name: "Target",
                    summary: "Target sizes",
                    symbolName: "scope",
                    settings: settings
                )
            ]
        )

        let decoded = try JSONDecoder().decode(
            PresetExchangeDocument.self,
            from: JSONEncoder().encode(document)
        )

        XCTAssertEqual(decoded.formatVersion, 1)
        XCTAssertEqual(
            decoded.presets.first?.settings.image.targetSizeBytes,
            750_000
        )
        XCTAssertEqual(
            decoded.presets.first?.settings.video.targetSizeBytes,
            25_000_000
        )
    }

    func testBuiltInPresetsCoverDistinctNeeds() {
        XCTAssertGreaterThanOrEqual(CompressionPreset.builtIns.count, 5)
        XCTAssertTrue(CompressionPreset.builtIns.allSatisfy(\.isBuiltIn))
        XCTAssertTrue(
            CompressionPreset.builtIns.contains {
                $0.settings.image.metadata == .removeAll
            }
        )
    }
}
