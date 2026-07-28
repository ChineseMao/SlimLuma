import XCTest
@testable import SlimLuma

final class PrinciplesContentTests: XCTestCase {
    func testPrinciplesNavigationMetadataIsComplete() {
        XCTAssertTrue(AppSection.allCases.contains(.principles))
        XCTAssertEqual(AppSection.principles.title, "功能与原理")
        XCTAssertFalse(AppSection.principles.symbolName.isEmpty)
    }

    func testEveryTopicHasDetailedContentAndAnExplicitBoundary() {
        for topic in PrincipleTopic.allCases {
            let sections = PrinciplesCatalog.sections(for: topic)

            XCTAssertGreaterThanOrEqual(
                sections.count,
                3,
                "\(topic.title) should have multiple explanation sections"
            )
            XCTAssertTrue(
                sections.contains { $0.kind == .boundary },
                "\(topic.title) should state its limits explicitly"
            )

            for section in sections {
                XCTAssertFalse(section.summary.isEmpty)
                XCTAssertGreaterThanOrEqual(section.facts.count, 2)
                XCTAssertEqual(
                    Set(section.facts.map(\.id)).count,
                    section.facts.count,
                    "\(section.title) uses fact titles as stable view identifiers"
                )
            }
        }
    }

    func testOverviewWorkflowEndsInValidatedSafeLanding() {
        let steps = PrinciplesCatalog.processSteps

        XCTAssertEqual(steps.map(\.number), Array(1...5))
        XCTAssertEqual(steps.last?.title, "体积策略与落盘")
        XCTAssertTrue(
            steps.contains { $0.detail.contains("隐藏临时文件") }
        )
        XCTAssertTrue(
            steps.contains { $0.detail.contains("完整性") }
        )
    }

    func testCapabilityCardsCoverEveryTopic() {
        XCTAssertEqual(
            Set(PrinciplesCatalog.capabilities.map(\.topic)),
            Set(PrincipleTopic.allCases.filter { $0 != .overview })
        )
    }

    func testEngineMatrixHasUniqueRowsAndExplainsMissingBehavior() {
        let engines = PrinciplesCatalog.engines

        XCTAssertEqual(Set(engines.map(\.id)).count, engines.count)
        XCTAssertTrue(engines.contains { $0.id == "imagemagick" })
        XCTAssertTrue(engines.contains { $0.id == "ffmpeg" })
        XCTAssertTrue(engines.contains { $0.id == "qpdf" })
        XCTAssertTrue(engines.contains { $0.id == "ghostscript" })
        XCTAssertTrue(
            engines.allSatisfy {
                !$0.responsibility.isEmpty && !$0.missingBehavior.isEmpty
            }
        )
    }

    func testHighRiskClaimsAreQualifiedInVisibleContent() {
        let allFacts = PrincipleTopic.allCases
            .flatMap(PrinciplesCatalog.sections(for:))
            .flatMap(\.facts)
            .map { "\($0.title) \($0.detail)" }
            .joined(separator: "\n")

        XCTAssertTrue(allFacts.contains("不是 100% 等价"))
        XCTAssertTrue(allFacts.contains("不做页面渲染对比"))
        XCTAssertTrue(allFacts.contains("当前不逐帧比较画面"))
        XCTAssertTrue(allFacts.contains("导入副本会保留"))
        XCTAssertTrue(
            allFacts.contains("不代替用户执行 Homebrew 自身的安装脚本")
        )
    }
}
