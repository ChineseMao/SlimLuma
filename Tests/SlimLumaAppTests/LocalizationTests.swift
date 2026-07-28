import Foundation
@testable import SlimLuma
import XCTest

final class LocalizationTests: XCTestCase {
    private let supportedLocalizations = [
        "en",
        "zh-Hans",
        "zh-Hant",
        "hi",
        "es-419",
        "es-ES",
        "ar",
        "fr",
        "bn",
        "pt-BR",
        "pt-PT",
        "id",
        "ur",
        "ru",
        "de",
        "ja",
        "sw",
        "pa-Arab",
        "te",
        "pcm"
    ]
    private let pluralizedKeys: Set<String> = [
        "%lld 个",
        "%lld 个失败",
        "%lld 个说明章节",
        "%lld 个未变小但已保留",
        "%lld 个未生成",
        "%lld 个文件，可继续拖入",
        "%lld 个已生成",
        "还有 %lld 个引擎可补齐",
        "同时处理 %lld 个任务"
    ]
    private let protectedTechnicalTerms = [
        "${applicationName}",
        "SlimLuma",
        "ImageMagick",
        "Ghostscript",
        "Homebrew",
        "AVFoundation",
        "VideoToolbox",
        "ImageIO",
        "Quick Look",
        "PDFKit",
        "FFmpeg",
        "ffprobe",
        "qpdf",
        "sips",
        "macOS",
        "Finder",
        "WebP",
        "AVIF",
        "HEIC",
        "HEVC",
        "H.264",
        "H.265",
        "AV1",
        "JPEG 2000",
        "JPEG",
        "PNG",
        "TIFF",
        "BMP",
        "GIF",
        "MKV",
        "WebM",
        "EXIF",
        "XMP",
        "IPTC",
        "ICC",
        "PDF"
    ]

    func testInfoPlistDeclaresEveryProductLocalization() throws {
        let infoPlist = try anyDictionary(at: projectRoot.appendingPathComponent(
            "Support/Info.plist"
        ))
        let declared = try XCTUnwrap(
            infoPlist["CFBundleLocalizations"] as? [String]
        )
        XCTAssertEqual(Set(declared), Set(supportedLocalizations))
        XCTAssertEqual(
            infoPlist["CFBundleDevelopmentRegion"] as? String,
            "zh-Hans"
        )
    }

    func testEveryLocalizationHasTheCompleteKeySet() throws {
        let source = try localizableDictionary(locale: "zh-Hans")
        let manifestData = try Data(
            contentsOf: resourcesRoot.appendingPathComponent(
                "LocalizationKeys.json"
            )
        )
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: manifestData) as? [String]
        )
        XCTAssertEqual(source.count, manifest.count)

        for locale in supportedLocalizations {
            let translations = try localizableDictionary(locale: locale)
            XCTAssertEqual(
                Set(translations.keys),
                Set(source.keys),
                "\(locale) has missing or unexpected localization keys"
            )
            XCTAssertFalse(
                translations.values.contains(where: \.isEmpty),
                "\(locale) contains an empty translation"
            )
        }
    }

    func testFrozenKeyManifestMatchesTheSourceTable() throws {
        let source = try localizableDictionary(locale: "zh-Hans")
        let data = try Data(
            contentsOf: resourcesRoot.appendingPathComponent(
                "LocalizationKeys.json"
            )
        )
        let frozenKeys = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String]
        )
        XCTAssertEqual(Set(frozenKeys), Set(source.keys))
        XCTAssertEqual(frozenKeys.count, source.count)
    }

    func testNonCJKLocalizationsContainNoResidualChineseCopy() throws {
        for locale in supportedLocalizations where
            !["zh-Hans", "zh-Hant", "ja"].contains(locale) {
            let translations = try localizableDictionary(locale: locale)
            let residual = translations.filter { _, value in
                containsHanScript(value)
            }
            XCTAssertTrue(
                residual.isEmpty,
                "\(locale) contains residual Chinese copy: "
                    + residual.keys.prefix(3).joined(separator: " | ")
            )
        }
    }

    func testTranslationsContainNoGeneratorTokens() throws {
        for locale in supportedLocalizations {
            let translations = try localizableDictionary(locale: locale)
            let contaminated = translations.filter { _, value in
                value.contains("SLFMT_")
                    || value.contains("SLTERM_")
                    || value.contains("SLKEY_")
            }
            XCTAssertTrue(
                contaminated.isEmpty,
                "\(locale) contains translation-generator tokens: "
                    + contaminated.keys.prefix(3).joined(separator: " | ")
            )
        }
    }

    func testTechnicalIdentifiersRemainExact() throws {
        let source = try localizableDictionary(locale: "zh-Hans")
        for locale in supportedLocalizations {
            let translations = try localizableDictionary(locale: locale)
            for (key, sourceValue) in source {
                let translated = try XCTUnwrap(translations[key])
                for term in protectedTechnicalTerms where
                    sourceValue.contains(term) {
                    XCTAssertTrue(
                        translated.contains(term),
                        "\(locale) changed or removed \(term) in \(key)"
                    )
                }
            }
        }
    }

    func testNonChineseLocalizationsDoNotSilentlyFallBackToChinese() throws {
        let source = try localizableDictionary(locale: "zh-Hans")
        for locale in supportedLocalizations where
            locale != "zh-Hans" && locale != "zh-Hant" {
            let translations = try localizableDictionary(locale: locale)
            let untranslated = source.keys.filter { key in
                guard containsHanScript(key) else { return false }
                return translations[key] == key
            }
            XCTAssertTrue(
                untranslated.isEmpty,
                "\(locale) still contains \(untranslated.count) source values: "
                    + untranslated.prefix(3).joined(separator: " | ")
            )
        }
    }

    func testNonEnglishLocalizationsAreNotEnglishPlaceholderCopies() throws {
        let english = try localizableDictionary(locale: "en")
        for locale in supportedLocalizations where locale != "en" {
            let translations = try localizableDictionary(locale: locale)
            let localizedValueCount = english.keys.filter { key in
                translations[key] != english[key]
            }.count
            XCTAssertGreaterThanOrEqual(
                localizedValueCount,
                english.count / 2,
                "\(locale) changes only \(localizedValueCount) of "
                    + "\(english.count) English values and appears to be "
                    + "an English placeholder table"
            )
        }
    }

    func testFormatPlaceholdersRemainCompleteAndReorderable() throws {
        let source = try localizableDictionary(locale: "zh-Hans")
        for locale in supportedLocalizations where locale != "zh-Hans" {
            let translations = try localizableDictionary(locale: locale)

            for key in source.keys {
                let translated = try XCTUnwrap(translations[key])
                let dynamicCount = key.components(separatedBy: "%arg").count - 1
                if dynamicCount > 0 {
                    for index in 0..<dynamicCount {
                        XCTAssertTrue(
                            translated.contains("{{\(index)}}"),
                            "\(locale) lost dynamic argument \(index) for \(key)"
                        )
                    }
                    XCTAssertFalse(
                        translated.contains("%arg"),
                        "\(locale) retained a source-only dynamic placeholder for \(key)"
                    )
                }

                XCTAssertEqual(
                    typedPlaceholders(in: translated).sorted(),
                    typedPlaceholders(in: key).sorted(),
                    "\(locale) changed a printf placeholder for \(key)"
                )
            }
        }
    }

    func testFinderAndInfoPlistTablesExistForEveryLocale() throws {
        for locale in supportedLocalizations {
            let directory = resourcesRoot.appendingPathComponent(
                "\(locale).lproj"
            )
            let translations = try localizableDictionary(locale: locale)
            let infoPlist = try stringDictionary(
                at: directory.appendingPathComponent("InfoPlist.strings")
            )
            let services = try stringDictionary(
                at: directory.appendingPathComponent("ServicesMenu.strings")
            )
            XCTAssertEqual(
                infoPlist["CFBundleTypeName"],
                translations["支持的媒体文件"],
                "\(locale) has a stale document type translation"
            )
            XCTAssertEqual(
                services["添加到 SlimLuma 压缩队列"],
                translations["添加到 SlimLuma 压缩队列"],
                "\(locale) has a stale Finder service title"
            )
            XCTAssertEqual(
                services["SLIMLUMA_SERVICE_DESCRIPTION"],
                translations[
                    "将所选图片、视频或 PDF 添加到 SlimLuma 的媒体压缩队列。"
                ],
                "\(locale) has a stale Finder service description"
            )
        }
    }

    func testAppShortcutsCatalogCoversEveryLocaleAndPreservesAppName() throws {
        let url = resourcesRoot.appendingPathComponent("AppShortcuts.xcstrings")
        let data = try Data(contentsOf: url)
        let catalog = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        XCTAssertEqual(strings.count, 2)

        for (key, rawEntry) in strings {
            let entry = try XCTUnwrap(rawEntry as? [String: Any])
            let localizations = try XCTUnwrap(
                entry["localizations"] as? [String: Any]
            )
            XCTAssertEqual(
                Set(localizations.keys),
                Set(supportedLocalizations)
            )
            for (locale, rawLocalization) in localizations {
                let translations = try localizableDictionary(locale: locale)
                let localization = try XCTUnwrap(
                    rawLocalization as? [String: Any]
                )
                let unit = try XCTUnwrap(
                    localization["stringUnit"] as? [String: Any]
                )
                let value = try XCTUnwrap(unit["value"] as? String)
                XCTAssertTrue(
                    value.contains("${applicationName}"),
                    "\(locale) lost the App Shortcut applicationName token"
                )
                XCTAssertEqual(
                    value,
                    translations[key],
                    "\(locale) has a stale App Shortcut phrase"
                )
            }
        }
    }

    func testPluralTablesFollowRequiredCLDRCategories() throws {
        let requiredCategories: [String: Set<String>] = [
            "en": ["one", "other"],
            "zh-Hans": ["other"],
            "zh-Hant": ["other"],
            "hi": ["one", "other"],
            "es-419": ["one", "many", "other"],
            "es-ES": ["one", "many", "other"],
            "ar": ["zero", "one", "two", "few", "many", "other"],
            "fr": ["one", "many", "other"],
            "bn": ["one", "other"],
            "pt-BR": ["one", "many", "other"],
            "pt-PT": ["one", "many", "other"],
            "id": ["other"],
            "ur": ["one", "other"],
            "ru": ["one", "few", "many", "other"],
            "de": ["one", "other"],
            "ja": ["other"],
            "sw": ["one", "other"],
            "pa-Arab": ["one", "other"],
            "te": ["one", "other"],
            "pcm": ["one", "other"]
        ]

        for locale in supportedLocalizations {
            let table = try anyDictionary(
                at: resourcesRoot
                    .appendingPathComponent("\(locale).lproj")
                    .appendingPathComponent("Localizable.stringsdict")
            )
            XCTAssertEqual(
                Set(table.keys),
                pluralizedKeys,
                "\(locale) has an incomplete plural table"
            )

            for key in pluralizedKeys {
                let entry = try XCTUnwrap(table[key] as? [String: Any])
                let pluralRule = try XCTUnwrap(
                    entry.values
                        .compactMap { $0 as? [String: Any] }
                        .first {
                            $0["NSStringFormatSpecTypeKey"] as? String
                                == "NSStringPluralRuleType"
                        }
                )
                XCTAssertEqual(
                    pluralRule["NSStringFormatValueTypeKey"] as? String,
                    "lld",
                    "\(locale) uses the wrong count type for \(key)"
                )
                let availableCategories = Set(
                    pluralRule.keys.filter {
                        ![
                            "NSStringFormatSpecTypeKey",
                            "NSStringFormatValueTypeKey"
                        ].contains($0)
                    }
                )
                XCTAssertTrue(
                    requiredCategories[locale, default: []]
                        .isSubset(of: availableCategories),
                    "\(locale) is missing CLDR plural categories for \(key)"
                )
            }
        }
    }

    func testDynamicAndExactRuntimeLocalization() {
        XCTAssertNotEqual(
            L10n.text("媒体压缩", localeIdentifier: "en"),
            "媒体压缩"
        )

        let result = L10n.text(
            "还有 3 个引擎可补齐",
            localeIdentifier: "en"
        )
        XCTAssertTrue(result.contains("3"))
        XCTAssertFalse(containsHanScript(result))

        XCTAssertEqual(L10n.labelSeparator(localeIdentifier: "en"), ": ")
        XCTAssertEqual(L10n.labelSeparator(localeIdentifier: "zh-Hans"), "：")
        XCTAssertEqual(L10n.labelSeparator(localeIdentifier: "ar"), "، ")
    }

    func testRegionAndScriptLocalizationsResolveAtRuntime() throws {
        try assertRuntimeLocalizations([
            "es-ES",
            "pt-BR",
            "zh-Hant",
            "pa-Arab"
        ])
    }

    func testSupportedRightToLeftScriptsUseRightToLeftLayout() {
        for locale in ["ar", "ur", "pa-Arab"] {
            XCTAssertTrue(
                L10n.isRightToLeft(localeIdentifier: locale),
                "\(locale) should use right-to-left layout"
            )
        }

        for locale in ["en", "zh-Hans", "hi", "pa-Guru"] {
            XCTAssertFalse(
                L10n.isRightToLeft(localeIdentifier: locale),
                "\(locale) should use left-to-right layout"
            )
        }
    }

    func testEveryProductLocalizationResolvesAtRuntime() throws {
        try assertRuntimeLocalizations(supportedLocalizations)
    }

    private func assertRuntimeLocalizations(_ locales: [String]) throws {
        let sourceValue = try XCTUnwrap(
            try localizableDictionary(locale: "zh-Hans")["媒体压缩"]
        )

        for locale in locales {
            let expected = try XCTUnwrap(
                try localizableDictionary(locale: locale)["媒体压缩"]
            )
            let actual = L10n.text(
                "媒体压缩",
                localeIdentifier: locale
            )
            XCTAssertEqual(
                actual,
                expected,
                "\(locale) did not load its exact runtime localization"
            )
            if locale != "zh-Hans" {
                XCTAssertNotEqual(
                    actual,
                    sourceValue,
                    "\(locale) silently fell back to the source localization"
                )
            }
        }
    }

    func testLocalizationResolutionDoesNotCrossRegionsOrScripts() {
        XCTAssertEqual(
            L10n.matchingLocalizationIdentifier(
                "es-ES",
                availableLocalizations: ["es-Latn-ES"]
            ),
            "es-Latn-ES"
        )
        XCTAssertEqual(
            L10n.matchingLocalizationIdentifier(
                "pt-PT",
                availableLocalizations: ["pt-br", "pt-pt"]
            ),
            "pt-pt"
        )
        XCTAssertNil(
            L10n.matchingLocalizationIdentifier(
                "pt-PT",
                availableLocalizations: ["pt-br"]
            )
        )
        XCTAssertEqual(
            L10n.matchingLocalizationIdentifier(
                "zh-Hant",
                availableLocalizations: ["zh-hans", "zh-hant"]
            ),
            "zh-hant"
        )
        XCTAssertNil(
            L10n.matchingLocalizationIdentifier(
                "pa-Arab",
                availableLocalizations: ["pa-Guru"]
            )
        )
    }

    func testRuntimePluralSelectionUsesDifferentGrammaticalForms() {
        let englishOne = normalizedCountCopy(
            L10n.text("还有 1 个引擎可补齐", localeIdentifier: "en")
        )
        let englishOther = normalizedCountCopy(
            L10n.text("还有 2 个引擎可补齐", localeIdentifier: "en")
        )
        XCTAssertNotEqual(englishOne, englishOther)

        let russianForms = [1, 2, 5].map {
            normalizedCountCopy(
                L10n.text(
                    "还有 \($0) 个引擎可补齐",
                    localeIdentifier: "ru"
                )
            )
        }
        XCTAssertEqual(Set(russianForms).count, 3)

        let arabicForms = [0, 1, 2, 3, 11, 100].map {
            normalizedCountCopy(
                L10n.text(
                    "还有 \($0) 个引擎可补齐",
                    localeIdentifier: "ar"
                )
            )
        }
        XCTAssertEqual(Set(arabicForms).count, 6)
    }

    func testNestedIntegrityFailuresLocalizeWithoutTranslatingUserData() {
        let englishPDF = L10n.text(
            "输出文件验证失败：压缩前后页数不一致（17 → 16）；"
                + "压缩结果丢失了 PDF 书签（23 → 0）",
            localeIdentifier: "en"
        )
        XCTAssertFalse(containsHanScript(englishPDF))
        XCTAssertTrue(englishPDF.contains("17"))
        XCTAssertTrue(englishPDF.contains("23"))

        let englishAnimation = L10n.text(
            "输出文件验证失败：动画图片帧数从 8 帧变为 "
                + "1 帧，输出已丢弃",
            localeIdentifier: "en"
        )
        XCTAssertFalse(containsHanScript(englishAnimation))
        XCTAssertTrue(englishAnimation.contains("8"))
        XCTAssertTrue(englishAnimation.contains("1"))

        let arabicVideo = L10n.text(
            "输出文件验证失败：音频轨道从 2 条变为 "
                + "1 条，输出已丢弃；"
                + "视频时长从 12.50 秒变为 9.25 秒，输出已丢弃",
            localeIdentifier: "ar"
        )
        XCTAssertFalse(containsHanScript(arabicVideo))
        XCTAssertTrue(arabicVideo.contains("12"))

        let userNamedFile = L10n.text(
            "删除“图片”？",
            localeIdentifier: "en"
        )
        XCTAssertTrue(userNamedFile.contains("图片"))
    }

    func testRTLLocalesContainReviewedScriptCoverage() throws {
        for locale in ["ar", "ur", "pa-Arab"] {
            XCTAssertEqual(
                Locale.Language(identifier: locale).characterDirection,
                .rightToLeft
            )
            let translations = try localizableDictionary(locale: locale)
            let values = translations.values.joined(separator: "\n")
            let arabicScalars = values.unicodeScalars.filter {
                (0x0600...0x06FF).contains(Int($0.value))
                    || (0x0750...0x077F).contains(Int($0.value))
            }
            XCTAssertGreaterThan(
                arabicScalars.count,
                500,
                "\(locale) does not contain enough Arabic-script UI text"
            )
        }
    }

    func testRepresentativeWritingSystemsAreActuallyPresent() throws {
        let rangesByLocale: [String: [ClosedRange<Int>]] = [
            "hi": [0x0900...0x097F],
            "bn": [0x0980...0x09FF],
            "ru": [0x0400...0x04FF],
            "ja": [0x3040...0x30FF],
            "te": [0x0C00...0x0C7F]
        ]

        for (locale, ranges) in rangesByLocale {
            let translations = try localizableDictionary(locale: locale)
            let scalarCount = translations.values
                .joined(separator: "\n")
                .unicodeScalars
                .filter { scalar in
                    ranges.contains { $0.contains(Int(scalar.value)) }
                }
                .count
            XCTAssertGreaterThan(
                scalarCount,
                100,
                "\(locale) does not contain enough text in its writing system"
            )
        }
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var resourcesRoot: URL {
        projectRoot.appendingPathComponent(
            "Sources/SlimLuma/Resources",
            isDirectory: true
        )
    }

    private func localizableDictionary(
        locale: String
    ) throws -> [String: String] {
        try stringDictionary(
            at: resourcesRoot
                .appendingPathComponent("\(locale).lproj")
                .appendingPathComponent("Localizable.strings")
        )
    }

    private func stringDictionary(
        at url: URL
    ) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: String],
            "Unable to parse \(url.path)"
        )
    }

    private func anyDictionary(
        at url: URL
    ) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any],
            "Unable to parse \(url.path)"
        )
    }

    private func typedPlaceholders(in value: String) -> [String] {
        let expression = try! NSRegularExpression(
            pattern: "%(?:\\d+\\$)?(?:@|lld|ld|d|\\.0f|\\.1f|f|s)"
        )
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.matches(in: value, range: range).compactMap {
            Range($0.range, in: value).map { String(value[$0]) }
        }
    }

    private func containsHanScript(_ value: String) -> Bool {
        value.unicodeScalars.contains {
            (0x3400...0x9FFF).contains(Int($0.value))
        }
    }

    private func normalizedCountCopy(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"\d+"#,
            with: "#",
            options: .regularExpression
        )
    }
}
