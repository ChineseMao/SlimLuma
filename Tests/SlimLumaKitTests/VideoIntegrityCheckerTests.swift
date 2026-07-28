@testable import SlimLumaKit
import XCTest

final class VideoIntegrityCheckerTests: XCTestCase {
    func testParsesFFprobeDurationAndAllRelevantTrackTypes() throws {
        let snapshot = try FFprobeSnapshotParser.parse(
            Data(
                """
                {
                  "streams": [
                    {"codec_type": "video", "duration": "2.400000"},
                    {"codec_type": "audio"},
                    {"codec_type": "audio"},
                    {"codec_type": "subtitle"}
                  ],
                  "format": {"duration": "2.500000"}
                }
                """.utf8
            ),
            filename: "fixture.mkv"
        )

        XCTAssertEqual(snapshot.durationSeconds, 2.5, accuracy: 0.0001)
        XCTAssertEqual(snapshot.videoTrackCount, 1)
        XCTAssertEqual(snapshot.audioTrackCount, 2)
        XCTAssertEqual(snapshot.subtitleTrackCount, 1)
        XCTAssertTrue(snapshot.isPlayable)
    }

    func testFFprobeParserFallsBackToLongestStreamDuration() throws {
        let snapshot = try FFprobeSnapshotParser.parse(
            Data(
                """
                {
                  "streams": [
                    {"codec_type": "video", "duration": "4.250000"},
                    {"codec_type": "audio", "duration": "4.100000"}
                  ],
                  "format": {}
                }
                """.utf8
            ),
            filename: "fixture.webm"
        )

        XCTAssertEqual(snapshot.durationSeconds, 4.25, accuracy: 0.0001)
        XCTAssertTrue(snapshot.isPlayable)
    }

    func testRejectsRemovedAudioAndChangedDuration() {
        let original = VideoIntegritySnapshot(
            durationSeconds: 120,
            videoTrackCount: 1,
            audioTrackCount: 1,
            subtitleTrackCount: 1,
            isPlayable: true
        )
        let compressed = VideoIntegritySnapshot(
            durationSeconds: 116,
            videoTrackCount: 1,
            audioTrackCount: 0,
            subtitleTrackCount: 0,
            isPlayable: true
        )

        let report = VideoIntegrityChecker().compare(
            original: original,
            compressed: compressed
        )

        XCTAssertTrue(report.hasCriticalRisk)
        XCTAssertTrue(report.risks.contains { $0.code == .audioTrackRemoved })
        XCTAssertTrue(report.risks.contains { $0.code == .subtitleTrackRemoved })
        XCTAssertTrue(report.risks.contains { $0.code == .durationChanged })
    }

    func testAcceptsNormalContainerTimingDifference() {
        let original = VideoIntegritySnapshot(
            durationSeconds: 60,
            videoTrackCount: 1,
            audioTrackCount: 1,
            subtitleTrackCount: 1,
            isPlayable: true
        )
        let compressed = VideoIntegritySnapshot(
            durationSeconds: 59.8,
            videoTrackCount: 1,
            audioTrackCount: 1,
            subtitleTrackCount: 1,
            isPlayable: true
        )

        let report = VideoIntegrityChecker().compare(
            original: original,
            compressed: compressed
        )

        XCTAssertFalse(report.hasCriticalRisk, report.summary)
    }

    func testParsesChaptersHDRLanguagesDispositionsAndSubtitlePackets() throws {
        let snapshot = try FFprobeSnapshotParser.parse(
            Data(
                """
                {
                  "streams": [
                    {
                      "codec_type": "video",
                      "color_transfer": "smpte2084",
                      "color_primaries": "bt2020"
                    },
                    {
                      "codec_type": "audio",
                      "tags": {"language": "eng"},
                      "disposition": {"default": 1, "forced": 0}
                    },
                    {
                      "codec_type": "subtitle",
                      "nb_read_packets": "12",
                      "tags": {"language": "zho"},
                      "disposition": {"default": 0, "forced": 1}
                    }
                  ],
                  "chapters": [{"id": 0}, {"id": 1}],
                  "format": {"duration": "30.0"}
                }
                """.utf8
            ),
            filename: "semantic-fixture.mkv"
        )

        XCTAssertEqual(snapshot.chapterCount, 2)
        XCTAssertTrue(snapshot.hasHDRVideo)
        XCTAssertEqual(snapshot.audioLanguages, ["eng"])
        XCTAssertEqual(snapshot.subtitleLanguages, ["zho"])
        XCTAssertEqual(snapshot.defaultAudioTrackCount, 1)
        XCTAssertEqual(snapshot.forcedSubtitleTrackCount, 1)
        XCTAssertEqual(snapshot.subtitlePacketCount, 12)
    }

    func testRejectsSemanticTrackAndHDRLoss() {
        let original = VideoIntegritySnapshot(
            durationSeconds: 30,
            videoTrackCount: 1,
            audioTrackCount: 1,
            subtitleTrackCount: 1,
            chapterCount: 2,
            hasHDRVideo: true,
            audioLanguages: ["eng"],
            subtitleLanguages: ["zho"],
            defaultAudioTrackCount: 1,
            forcedSubtitleTrackCount: 1,
            subtitlePacketCount: 12,
            isPlayable: true
        )
        let compressed = VideoIntegritySnapshot(
            durationSeconds: 30,
            videoTrackCount: 1,
            audioTrackCount: 1,
            subtitleTrackCount: 1,
            chapterCount: 0,
            hasHDRVideo: false,
            audioLanguages: [],
            subtitleLanguages: [],
            defaultAudioTrackCount: 0,
            forcedSubtitleTrackCount: 0,
            subtitlePacketCount: 0,
            isPlayable: true
        )

        let report = VideoIntegrityChecker().compare(
            original: original,
            compressed: compressed
        )
        let codes = Set(report.risks.map(\.code))
        XCTAssertTrue(codes.contains(.chaptersRemoved))
        XCTAssertTrue(codes.contains(.hdrRemoved))
        XCTAssertTrue(codes.contains(.trackLanguageChanged))
        XCTAssertTrue(codes.contains(.defaultAudioDispositionRemoved))
        XCTAssertTrue(codes.contains(.forcedSubtitleDispositionRemoved))
        XCTAssertTrue(codes.contains(.subtitlePayloadRemoved))
    }

    func testChapterRemovalCanBeExplicitlyAllowed() {
        let original = VideoIntegritySnapshot(
            durationSeconds: 10,
            videoTrackCount: 1,
            audioTrackCount: 0,
            subtitleTrackCount: 0,
            chapterCount: 3,
            isPlayable: true
        )
        let compressed = VideoIntegritySnapshot(
            durationSeconds: 10,
            videoTrackCount: 1,
            audioTrackCount: 0,
            subtitleTrackCount: 0,
            chapterCount: 0,
            isPlayable: true
        )

        let report = VideoIntegrityChecker().compare(
            original: original,
            compressed: compressed,
            expectations: VideoIntegrityExpectations(
                preserveChapters: false
            )
        )
        XCTAssertFalse(report.hasCriticalRisk, report.summary)
    }
}
