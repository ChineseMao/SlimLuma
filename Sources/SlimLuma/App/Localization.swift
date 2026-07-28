import Foundation

enum L10n {
    static var usesRightToLeftLayout: Bool {
        let identifier =
            Bundle.main.preferredLocalizations.first
            ?? Locale.current.identifier
        return isRightToLeft(localeIdentifier: identifier)
    }

    static func isRightToLeft(localeIdentifier: String) -> Bool {
        Locale.Language(
            identifier: localeIdentifier
        ).characterDirection == .rightToLeft
    }

    private struct LocalizationComponents: Equatable {
        let language: String
        let script: String?
        let region: String?

        init?(_ identifier: String) {
            let language = Locale.Language(identifier: identifier)
            guard let languageCode = language.languageCode?.identifier else {
                return nil
            }
            self.language = languageCode.lowercased()
            script = language.script?.identifier.lowercased()
            region = language.region?.identifier.lowercased()
        }
    }

    private struct DynamicTemplate {
        let sourceKey: String
        let expression: NSRegularExpression
        let literalCharacterCount: Int
    }

    private static let dynamicPlaceholderExpression = try! NSRegularExpression(
        pattern: "%arg"
    )
    private static let validationFrameCountExpression =
        try! NSRegularExpression(
            pattern:
                #"^动画图片帧数从 (.+?) 帧变为 (.+?) 帧，输出已丢弃$"#
        )
    private static let validationLoopCountExpression =
        try! NSRegularExpression(
            pattern:
                #"^动画图片循环次数从 (.+?) 变为 (.+?)，输出已丢弃$"#
        )
    private static let validationMissingLoopExpression =
        try! NSRegularExpression(
            pattern:
                #"^动画图片循环设置（原为 (.+?)）已丢失，输出已丢弃$"#
        )
    private static let validationVideoTrackExpression =
        try! NSRegularExpression(
            pattern:
                #"^视频轨道从 (.+?) 条变为 (.+?) 条，输出已丢弃$"#
        )
    private static let validationAudioTrackExpression =
        try! NSRegularExpression(
            pattern:
                #"^音频轨道从 (.+?) 条变为 (.+?) 条，输出已丢弃$"#
        )
    private static let validationSubtitleTrackExpression =
        try! NSRegularExpression(
            pattern:
                #"^字幕轨道从 (.+?) 条变为 (.+?) 条，输出已丢弃$"#
        )
    private static let validationVideoDurationExpression =
        try! NSRegularExpression(
            pattern:
                #"^视频时长从 ([0-9]+(?:\.[0-9]+)?) 秒变为 ([0-9]+(?:\.[0-9]+)?) 秒，输出已丢弃$"#
        )

    private static let dynamicTemplates: [DynamicTemplate] = {
        sourceStrings.keys.compactMap { key in
            let fullRange = NSRange(key.startIndex..<key.endIndex, in: key)
            let matches = dynamicPlaceholderExpression.matches(
                in: key,
                range: fullRange
            )
            guard !matches.isEmpty else { return nil }

            var pattern = "^"
            var cursor = key.startIndex
            var literalCharacterCount = 0
            for match in matches {
                guard let range = Range(match.range, in: key) else { continue }
                let literal = String(key[cursor..<range.lowerBound])
                literalCharacterCount += literal.count
                pattern += NSRegularExpression.escapedPattern(for: literal)
                pattern += "(.+?)"
                cursor = range.upperBound
            }
            let suffix = String(key[cursor...])
            literalCharacterCount += suffix.count
            pattern += NSRegularExpression.escapedPattern(for: suffix)
            pattern += "$"

            guard let expression = try? NSRegularExpression(pattern: pattern) else {
                return nil
            }
            return DynamicTemplate(
                sourceKey: key,
                expression: expression,
                literalCharacterCount: literalCharacterCount
            )
        }
        .sorted { left, right in
            left.literalCharacterCount > right.literalCharacterCount
        }
    }()

    private static let sourceStrings: [String: String] = {
        dictionary(
            named: "Localizable",
            localization: "zh-Hans"
        ) ?? [:]
    }()

    static func text(
        _ source: String,
        localeIdentifier: String? = nil
    ) -> String {
        if let translated = exactTranslation(
            for: source,
            localeIdentifier: localeIdentifier
        ) {
            return translated
        }

        let outputValidationPrefix = "输出文件验证失败："
        if source.hasPrefix(outputValidationPrefix) {
            let detail = String(source.dropFirst(outputValidationPrefix.count))
            let template =
                exactTranslation(
                    for: "输出文件验证失败：%arg",
                    localeIdentifier: localeIdentifier
                )
                ?? "输出文件验证失败：%arg"
            return interpolate(
                template,
                arguments: [
                    localizedValidationDetail(
                        detail,
                        localeIdentifier: localeIdentifier
                    )
                ]
            )
        }

        let clauses = source.split(
            separator: "；",
            omittingEmptySubsequences: false
        )
        if clauses.count > 1 {
            return clauses
                .map {
                    text(
                        String($0),
                        localeIdentifier: localeIdentifier
                    )
                }
                .joined(separator: clauseSeparator(for: localeIdentifier))
        }

        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        for template in dynamicTemplates {
            guard
                let match = template.expression.firstMatch(
                    in: source,
                    range: range
                ),
                match.range == range
            else {
                continue
            }

            let arguments = (1..<match.numberOfRanges).compactMap { index in
                Range(match.range(at: index), in: source).map {
                    String(source[$0])
                }
            }
            guard arguments.count == match.numberOfRanges - 1 else {
                continue
            }

            if let pluralized = pluralizedTranslation(
                for: template.sourceKey,
                arguments: arguments,
                localeIdentifier: localeIdentifier
            ) {
                return pluralized
            }

            let translatedTemplate =
                exactTranslation(
                    for: template.sourceKey,
                    localeIdentifier: localeIdentifier
                )
                ?? template.sourceKey
            return interpolate(
                translatedTemplate,
                arguments: arguments
            )
        }

        return source
    }

    private static func localizedValidationDetail(
        _ source: String,
        localeIdentifier: String?
    ) -> String {
        let clauses = source.split(
            separator: "；",
            omittingEmptySubsequences: false
        )
        if clauses.count > 1 {
            return clauses
                .map {
                    localizedValidationClause(
                        String($0),
                        localeIdentifier: localeIdentifier
                    )
                }
                .joined(separator: clauseSeparator(for: localeIdentifier))
        }
        return localizedValidationClause(
            source,
            localeIdentifier: localeIdentifier
        )
    }

    private static func localizedValidationClause(
        _ source: String,
        localeIdentifier: String?
    ) -> String {
        if let translated = exactTranslation(
            for: source,
            localeIdentifier: localeIdentifier
        ) {
            return translated
        }

        if let values = captures(
            in: source,
            matching: validationFrameCountExpression
        ) {
            return joinedValidationFragments(
                dynamicFragment(
                    "动画图片帧数从 %arg 帧变为 ",
                    arguments: [values[0]],
                    localeIdentifier: localeIdentifier
                ),
                dynamicFragment(
                    "%arg 帧，输出已丢弃",
                    arguments: [values[1]],
                    localeIdentifier: localeIdentifier
                ),
                localeIdentifier: localeIdentifier
            )
        }
        if let values = captures(
            in: source,
            matching: validationLoopCountExpression
        ) {
            return joinedValidationFragments(
                dynamicFragment(
                    "动画图片循环次数从 %arg 变为 ",
                    arguments: [values[0]],
                    localeIdentifier: localeIdentifier
                ),
                dynamicFragment(
                    "%arg，输出已丢弃",
                    arguments: [values[1]],
                    localeIdentifier: localeIdentifier
                ),
                localeIdentifier: localeIdentifier
            )
        }
        if let values = captures(
            in: source,
            matching: validationMissingLoopExpression
        ) {
            return joinedValidationFragments(
                dynamicFragment(
                    "动画图片循环设置（原为 %arg）",
                    arguments: [values[0]],
                    localeIdentifier: localeIdentifier
                ),
                exactTranslation(
                    for: "已丢失，输出已丢弃",
                    localeIdentifier: localeIdentifier
                ) ?? "已丢失，输出已丢弃",
                localeIdentifier: localeIdentifier
            )
        }

        for (expression, prefixKey) in [
            (validationVideoTrackExpression, "视频轨道从 %arg 条变为 "),
            (validationAudioTrackExpression, "音频轨道从 %arg 条变为 "),
            (validationSubtitleTrackExpression, "字幕轨道从 %arg 条变为 ")
        ] {
            if let values = captures(in: source, matching: expression) {
                return joinedValidationFragments(
                    dynamicFragment(
                        prefixKey,
                        arguments: [values[0]],
                        localeIdentifier: localeIdentifier
                    ),
                    dynamicFragment(
                        "%arg 条，输出已丢弃",
                        arguments: [values[1]],
                        localeIdentifier: localeIdentifier
                    ),
                    localeIdentifier: localeIdentifier
                )
            }
        }

        if
            let values = captures(
                in: source,
                matching: validationVideoDurationExpression
            ),
            values.count == 2,
            let original = Double(values[0]),
            let compressed = Double(values[1])
        {
            let key = "视频时长从 %.2f 秒变为 %.2f 秒，输出已丢弃"
            let format =
                exactTranslation(
                    for: key,
                    localeIdentifier: localeIdentifier
                )
                ?? key
            return String(
                format: format,
                locale: Locale(
                    identifier: effectiveLocaleIdentifier(localeIdentifier)
                ),
                original,
                compressed
            )
        }

        if
            source.hasSuffix("）"),
            let openingParenthesis = source.lastIndex(of: "（")
        {
            let message = String(source[..<openingParenthesis])
            if let translated = exactTranslation(
                for: message,
                localeIdentifier: localeIdentifier
            ) {
                let valueStart = source.index(after: openingParenthesis)
                let valueEnd = source.index(before: source.endIndex)
                let values = String(source[valueStart..<valueEnd])
                return translated
                    + localizedValidationValues(
                        values,
                        localeIdentifier: localeIdentifier
                    )
            }
        }

        return source
    }

    private static func captures(
        in source: String,
        matching expression: NSRegularExpression
    ) -> [String]? {
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard
            let match = expression.firstMatch(in: source, range: range),
            match.range == range
        else {
            return nil
        }
        let values = (1..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: source).map {
                String(source[$0])
            }
        }
        return values.count == match.numberOfRanges - 1 ? values : nil
    }

    private static func dynamicFragment(
        _ key: String,
        arguments: [String],
        localeIdentifier: String?
    ) -> String {
        let template =
            exactTranslation(
                for: key,
                localeIdentifier: localeIdentifier
            )
            ?? key
        return interpolate(template, arguments: arguments)
    }

    private static func joinedValidationFragments(
        _ first: String,
        _ second: String,
        localeIdentifier: String?
    ) -> String {
        guard
            first.last?.isWhitespace != true,
            second.first?.isWhitespace != true
        else {
            return first + second
        }
        let identifier = effectiveLocaleIdentifier(
            localeIdentifier
        ).lowercased()
        let separator =
            identifier.hasPrefix("zh") || identifier.hasPrefix("ja")
                ? ""
                : " "
        return first + separator + second
    }

    private static func localizedValidationValues(
        _ values: String,
        localeIdentifier: String?
    ) -> String {
        let identifier = effectiveLocaleIdentifier(
            localeIdentifier
        ).lowercased()
        if identifier.hasPrefix("zh") || identifier.hasPrefix("ja") {
            return "（\(values)）"
        }
        if identifier.hasPrefix("ar")
            || identifier.hasPrefix("ur")
            || identifier.hasPrefix("pa-arab") {
            return " (\u{2068}\(values)\u{2069})"
        }
        return " (\(values))"
    }

    private static func pluralizedTranslation(
        for sourceKey: String,
        arguments: [String],
        localeIdentifier: String?
    ) -> String? {
        guard
            arguments.count == 1,
            let count = Int64(arguments[0]),
            sourceKey.components(separatedBy: "%arg").count == 2
        else {
            return nil
        }

        let typedKey = sourceKey.replacingOccurrences(
            of: "%arg",
            with: "%lld"
        )

        let locale = effectiveLocaleIdentifier(localeIdentifier)
        if
            let entry = pluralEntry(
                for: typedKey,
                localeIdentifier: locale
            ),
            let rule = entry.values
                .compactMap({ $0 as? [String: Any] })
                .first(where: {
                    $0["NSStringFormatSpecTypeKey"] as? String
                        == "NSStringPluralRuleType"
                })
        {
            let category = pluralCategory(
                for: count,
                localeIdentifier: locale
            )
            let format =
                rule[category] as? String
                ?? rule["other"] as? String
            if let format {
                return String(
                    format: format,
                    locale: Locale(identifier: locale),
                    count
                )
            }
        }

        for bundle in bundles(localization: localeIdentifier) {
            let format = bundle.localizedString(
                forKey: typedKey,
                value: typedKey,
                table: "Localizable"
            )
            if format != typedKey {
                return String.localizedStringWithFormat(format, count)
            }
        }
        return nil
    }

    private static func pluralEntry(
        for key: String,
        localeIdentifier: String
    ) -> [String: Any]? {
        for bundle in resourceBundles {
            guard
                let matchedLocalization = matchingLocalizationIdentifier(
                    localeIdentifier,
                    availableLocalizations: bundle.localizations
                ),
                let path = bundle.path(
                    forResource: "Localizable",
                    ofType: "stringsdict",
                    inDirectory: nil,
                    forLocalization: matchedLocalization
                ),
                let data = try? Data(
                    contentsOf: URL(fileURLWithPath: path)
                ),
                let table = try? PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                ) as? [String: Any],
                let entry = table[key] as? [String: Any]
            else {
                continue
            }
            return entry
        }
        return nil
    }

    private static func pluralCategory(
        for rawCount: Int64,
        localeIdentifier: String
    ) -> String {
        let count = abs(rawCount)
        let language = Locale.Language(
            identifier: localeIdentifier
        ).languageCode?.identifier

        switch language {
        case "ar":
            if count == 0 { return "zero" }
            if count == 1 { return "one" }
            if count == 2 { return "two" }
            if (3...10).contains(count % 100) { return "few" }
            if (11...99).contains(count % 100) { return "many" }
            return "other"
        case "ru":
            if count % 10 == 1, count % 100 != 11 {
                return "one"
            }
            if (2...4).contains(count % 10),
               !(12...14).contains(count % 100) {
                return "few"
            }
            if count % 10 == 0
                || (5...9).contains(count % 10)
                || (11...14).contains(count % 100) {
                return "many"
            }
            return "other"
        case "fr":
            if count == 0 || count == 1 { return "one" }
            if count > 0, count.isMultiple(of: 1_000_000) {
                return "many"
            }
            return "other"
        case "pt":
            if localeIdentifier.lowercased().hasPrefix("pt-br") {
                if count == 0 || count == 1 { return "one" }
            } else if count == 1 {
                return "one"
            }
            if count > 0, count.isMultiple(of: 1_000_000) {
                return "many"
            }
            return "other"
        case "es":
            if count == 1 { return "one" }
            if count > 0, count.isMultiple(of: 1_000_000) {
                return "many"
            }
            return "other"
        case "hi", "bn", "pa", "pcm":
            return count == 0 || count == 1 ? "one" : "other"
        case "en", "de", "ur", "sw", "te":
            return count == 1 ? "one" : "other"
        default:
            return "other"
        }
    }

    private static func effectiveLocaleIdentifier(
        _ localeIdentifier: String?
    ) -> String {
        localeIdentifier
            ?? Bundle.main.preferredLocalizations.first
            ?? Locale.current.identifier
    }

    private static func clauseSeparator(for localeIdentifier: String?) -> String {
        let identifier = (
            localeIdentifier
                ?? Bundle.main.preferredLocalizations.first
                ?? Locale.current.identifier
        ).lowercased()
        if identifier.hasPrefix("zh") || identifier.hasPrefix("ja") {
            return "；"
        }
        if identifier.hasPrefix("ar")
            || identifier.hasPrefix("ur")
            || identifier.hasPrefix("pa-arab") {
            return "؛ "
        }
        return "; "
    }

    static func list(
        _ values: [String],
        localeIdentifier: String? = nil
    ) -> String {
        let translated = values.map {
            text($0, localeIdentifier: localeIdentifier)
        }
        guard let localeIdentifier else {
            return ListFormatter.localizedString(
                byJoining: translated
            )
        }

        let formatter = ListFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        return formatter.string(from: translated) ?? translated.joined(separator: ", ")
    }

    static func labelSeparator(localeIdentifier: String? = nil) -> String {
        let identifier = (
            localeIdentifier
                ?? Bundle.main.preferredLocalizations.first
                ?? Locale.current.identifier
        ).lowercased()
        if identifier.hasPrefix("zh") || identifier.hasPrefix("ja") {
            return "："
        }
        if identifier.hasPrefix("ar")
            || identifier.hasPrefix("ur")
            || identifier.hasPrefix("pa-arab") {
            return "، "
        }
        return ": "
    }

    private static func exactTranslation(
        for key: String,
        localeIdentifier: String?
    ) -> String? {
        for bundle in bundles(localization: localeIdentifier) {
            let value = bundle.localizedString(
                forKey: key,
                value: key,
                table: "Localizable"
            )
            if value != key {
                return value
            }
        }
        return nil
    }

    private static func interpolate(
        _ template: String,
        arguments: [String]
    ) -> String {
        var result = template
        var usedIndexedPlaceholder = false
        for (index, argument) in arguments.enumerated() {
            let token = "{{\(index)}}"
            if result.contains(token) {
                result = result.replacingOccurrences(
                    of: token,
                    with: argument
                )
                usedIndexedPlaceholder = true
            }
        }
        if usedIndexedPlaceholder {
            return result
        }

        for argument in arguments {
            guard let range = result.range(of: "%arg") else { break }
            result.replaceSubrange(range, with: argument)
        }
        return result
    }

    private static func bundles(localization: String?) -> [Bundle] {
        let baseBundles = resourceBundles
        guard let localization else {
            return baseBundles
        }

        return baseBundles.compactMap { bundle in
            guard
                let matchedLocalization = matchingLocalizationIdentifier(
                    localization,
                    availableLocalizations: bundle.localizations
                ),
                let path = bundle.path(
                    forResource: matchedLocalization,
                    ofType: "lproj"
                )
            else {
                return nil
            }
            return Bundle(path: path)
        }
    }

    static func matchingLocalizationIdentifier(
        _ requestedIdentifier: String,
        availableLocalizations: [String]
    ) -> String? {
        if availableLocalizations.contains(requestedIdentifier) {
            return requestedIdentifier
        }

        let normalizedRequested = requestedIdentifier.replacingOccurrences(
            of: "_",
            with: "-"
        )
        if let exactNormalizedMatch = availableLocalizations.first(where: {
            $0.replacingOccurrences(of: "_", with: "-")
                .caseInsensitiveCompare(normalizedRequested) == .orderedSame
        }) {
            return exactNormalizedMatch
        }

        guard let requestedComponents = LocalizationComponents(
            requestedIdentifier
        ) else {
            return nil
        }
        return availableLocalizations.first {
            LocalizationComponents($0) == requestedComponents
        }
    }

    private static func dictionary(
        named name: String,
        localization: String
    ) -> [String: String]? {
        for bundle in resourceBundles {
            guard
                let matchedLocalization = matchingLocalizationIdentifier(
                    localization,
                    availableLocalizations: bundle.localizations
                ),
                let path = bundle.path(
                    forResource: name,
                    ofType: "strings",
                    inDirectory: nil,
                    forLocalization: matchedLocalization
                ),
                let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                let dictionary = try? PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                ) as? [String: String]
            else {
                continue
            }
            return dictionary
        }
        return nil
    }

    private static var resourceBundles: [Bundle] {
        if Bundle.main.bundleURL.pathExtension.lowercased() == "app" {
            return [Bundle.main]
        }
        return [Bundle.main, Bundle.module]
    }
}
