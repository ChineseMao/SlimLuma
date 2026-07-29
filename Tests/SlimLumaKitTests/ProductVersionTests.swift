import Foundation
@testable import SlimLumaKit
import XCTest

final class ProductVersionTests: XCTestCase {
    func testProductVersionMatchesAppInfoPlist() throws {
        let data = try Data(
            contentsOf: projectRoot.appendingPathComponent(
                "Support/Info.plist"
            )
        )
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        )

        XCTAssertEqual(
            plist["CFBundleShortVersionString"] as? String,
            SlimLumaProduct.version
        )
    }

    func testProductVersionIsSemanticVersion() {
        XCTAssertNotNil(
            SlimLumaProduct.version.range(
                of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#,
                options: .regularExpression
            )
        )
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
