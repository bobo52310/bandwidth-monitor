import Testing
import Foundation

/// Keeps `Utilities/L10n.swift` and `BandwidthECG/Localizable.xcstrings` in step.
///
/// The app reads strings from the catalog by key; a key that is missing a language falls back to
/// the Traditional Chinese `defaultValue`, which is how the English, Japanese and Korean UI used
/// to show Chinese. These tests read the two source files directly (no app bundle is involved),
/// so they fail in `swift test` the moment a key is added to one side only.
@Suite("L10n catalog")
struct L10nCatalogTests {

    // MARK: - Locating the files

    /// `.../BandwidthECGPackage/Tests/BandwidthECGFeatureTests/L10nCatalogTests.swift`
    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // BandwidthECGFeatureTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // BandwidthECGPackage

    private static let repoRoot = packageRoot.deletingLastPathComponent()

    private static let sourcesRoot = packageRoot
        .appendingPathComponent("Sources/BandwidthECGFeature")

    private static let l10nURL = sourcesRoot
        .appendingPathComponent("Utilities/L10n.swift")

    private static let catalogURL = repoRoot
        .appendingPathComponent("BandwidthECG/Localizable.xcstrings")

    private static let appTargetRoot = repoRoot.appendingPathComponent("BandwidthECG")

    /// Every language the app ships. `zh-Hant` is the source language of the catalog.
    private static let languages = ["en", "ja", "ko", "zh-Hant"]

    // MARK: - Reading L10n.swift

    private struct CodeEntry {
        let key: String
        /// The text of the `defaultValue:` literal, escapes resolved. `nil` when the call has none.
        let defaultValue: String?
    }

    private static func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// `String(localized: "key", defaultValue: "text")`, one entry per call, in file order.
    private static func codeEntries() throws -> [CodeEntry] {
        let source = try read(l10nURL)
        let pattern = #"String\(localized:\s*"([^"]+)"(?:\s*,\s*defaultValue:\s*"((?:[^"\\]|\\.)*)")?"#
        let regex = try NSRegularExpression(pattern: pattern)
        let whole = NSRange(source.startIndex..., in: source)
        return regex.matches(in: source, range: whole).map { match in
            let key = String(source[Range(match.range(at: 1), in: source)!])
            let defaultValue = Range(match.range(at: 2), in: source).map { unescape(String(source[$0])) }
            return CodeEntry(key: key, defaultValue: defaultValue)
        }
    }

    /// The escapes a Swift string literal can reasonably carry in this file.
    private static func unescape(_ literal: String) -> String {
        literal
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    // MARK: - Reading the catalog

    private struct Catalog {
        /// key -> language -> (state, value)
        let strings: [String: [String: (state: String?, value: String?)]]
        let keys: Set<String>
    }

    private static func catalog() throws -> Catalog {
        let data = try Data(contentsOf: catalogURL)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["sourceLanguage"] as? String == "zh-Hant")
        let strings = try #require(root["strings"] as? [String: [String: Any]])
        var result: [String: [String: (state: String?, value: String?)]] = [:]
        for (key, entry) in strings {
            var perLanguage: [String: (state: String?, value: String?)] = [:]
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            for (language, localization) in localizations {
                let unit = localization["stringUnit"] as? [String: Any]
                perLanguage[language] = (unit?["state"] as? String, unit?["value"] as? String)
            }
            result[key] = perLanguage
        }
        return Catalog(strings: result, keys: Set(strings.keys))
    }

    // MARK: - Format specifiers

    /// One conversion in a format string, with the argument it consumes.
    private struct Specifier: Hashable, Comparable {
        let position: Int
        let conversion: String

        static func < (lhs: Specifier, rhs: Specifier) -> Bool { lhs.position < rhs.position }
    }

    /// `%@`, `%d`, `%lld`, `%.1f`, `%1$d`. A literal `%%` consumes no argument.
    private static func specifiers(in format: String) -> [Specifier] {
        let pattern = #"%(?:(\d+)\$)?[-+ 0#]*\d*(?:\.\d+)?(hh|h|ll|l|q|L|z|t|j)?([@dDiuUxXoOfFeEgGaAcCsSp%])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let whole = NSRange(format.startIndex..., in: format)
        var next = 1
        var found: [Specifier] = []
        for match in regex.matches(in: format, range: whole) {
            let conversion = String(format[Range(match.range(at: 3), in: format)!])
            if conversion == "%" { continue }
            let length = Range(match.range(at: 2), in: format).map { String(format[$0]) } ?? ""
            let position: Int
            if let explicit = Range(match.range(at: 1), in: format), let n = Int(format[explicit]) {
                position = n
            } else {
                position = next
                next += 1
            }
            found.append(Specifier(position: position, conversion: length + conversion))
        }
        return found.sorted()
    }

    // MARK: - Characters

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
    }

    private static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isHan)
    }

    /// Language names are written in their own language in every locale.
    private static func isLanguageName(_ key: String) -> Bool {
        key.hasPrefix("language.")
    }

    // MARK: - Tests

    @Test func parserSeesEveryLookup() throws {
        let source = try Self.read(Self.l10nURL)
        let calls = source.components(separatedBy: "String(localized:").count - 1
        let entries = try Self.codeEntries()
        #expect(entries.count == calls, "a String(localized:) call in L10n.swift is not in the form the parser reads")
        #expect(entries.count > 100)
        let keys = entries.map(\.key)
        #expect(Set(keys).count == keys.count, "a key is declared twice in L10n.swift")
        let withoutDefault = entries.filter { $0.defaultValue == nil }.map(\.key)
        #expect(withoutDefault.isEmpty, "keys without a defaultValue: \(withoutDefault)")
    }

    @Test func everyKeyInCatalog() throws {
        let keys = Set(try Self.codeEntries().map(\.key))
        let catalog = try Self.catalog()
        let missing = keys.subtracting(catalog.keys).sorted()
        #expect(missing.isEmpty, "used in L10n.swift but not in Localizable.xcstrings: \(missing)")
    }

    @Test func noOrphanKeys() throws {
        let keys = Set(try Self.codeEntries().map(\.key))
        let catalog = try Self.catalog()
        let orphans = catalog.keys.subtracting(keys).sorted()
        #expect(orphans.isEmpty, "in Localizable.xcstrings but not referenced by L10n.swift: \(orphans)")
    }

    @Test func everyKeyTranslated() throws {
        let catalog = try Self.catalog()
        var problems: [String] = []
        for key in try Self.codeEntries().map(\.key) {
            guard let perLanguage = catalog.strings[key] else { continue }  // everyKeyInCatalog reports it
            for language in Self.languages {
                guard let localization = perLanguage[language] else {
                    problems.append("\(key) [\(language)] missing")
                    continue
                }
                if localization.state != "translated" {
                    problems.append("\(key) [\(language)] state=\(localization.state ?? "nil")")
                }
                let value = localization.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if value.isEmpty {
                    problems.append("\(key) [\(language)] empty")
                }
            }
        }
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test func formatSpecifiersMatch() throws {
        let catalog = try Self.catalog()
        var problems: [String] = []
        for entry in try Self.codeEntries() {
            guard let defaultValue = entry.defaultValue, let perLanguage = catalog.strings[entry.key] else { continue }
            let expected = Self.specifiers(in: defaultValue)
            for language in Self.languages {
                guard let value = perLanguage[language]?.value else { continue }  // reported elsewhere
                let actual = Self.specifiers(in: value)
                if actual != expected {
                    problems.append("\(entry.key) [\(language)] \(actual.map(\.conversion)) != \(expected.map(\.conversion))")
                }
                // In a format string a literal percent sign is written `%%`; a lone `%` would
                // swallow whatever follows it. Strings without a specifier are never formatted,
                // so "90%" is right there.
                if !expected.isEmpty {
                    let percents = value.components(separatedBy: "%%").joined().filter { $0 == "%" }.count
                    if percents != actual.count {
                        problems.append("\(entry.key) [\(language)] has a bare % that is not a conversion")
                    }
                }
            }
        }
        #expect(problems.isEmpty, "\(problems)")
    }

    @Test func specifierParserUnderstandsTheForms() {
        #expect(Self.specifiers(in: "%@ 月度報告").map(\.conversion) == ["@"])
        #expect(Self.specifiers(in: "已收集 %d%%").map(\.conversion) == ["d"])
        #expect(Self.specifiers(in: "%@ %lld").map(\.conversion) == ["@", "lld"])
        // Positional specifiers may be reordered by a language and still match by position.
        #expect(Self.specifiers(in: "%2$d / %1$d") == Self.specifiers(in: "%1$d / %2$d"))
        #expect(Self.specifiers(in: "%d") != Self.specifiers(in: "%lld"))
        #expect(Self.specifiers(in: "50%%").isEmpty)
    }

    /// The `defaultValue` is what the app shows when the catalog cannot be read (and what unit
    /// tests see). It has to say what the zh-Hant row says, or the two sources of truth drift.
    @Test func zhHantMatchesDefaultValue() throws {
        let catalog = try Self.catalog()
        var problems: [String] = []
        for entry in try Self.codeEntries() {
            guard let defaultValue = entry.defaultValue,
                  let zh = catalog.strings[entry.key]?["zh-Hant"]?.value else { continue }
            if zh != defaultValue {
                problems.append("\(entry.key): catalog \"\(zh)\" != defaultValue \"\(defaultValue)\"")
            }
        }
        #expect(problems.isEmpty, "\(problems)")
    }

    /// The point of the whole catalog: no Chinese ideographs in the English or Korean rows, and
    /// no Japanese row that is just the Chinese copied over.
    @Test func foreignRowsAreNotChinese() throws {
        let catalog = try Self.catalog()
        var problems: [String] = []
        for key in try Self.codeEntries().map(\.key) where !Self.isLanguageName(key) {
            guard let perLanguage = catalog.strings[key] else { continue }
            for language in ["en", "ko"] {
                if let value = perLanguage[language]?.value, Self.containsHan(value) {
                    problems.append("\(key) [\(language)] contains Chinese characters: \(value)")
                }
            }
            if let ja = perLanguage["ja"]?.value, let zh = perLanguage["zh-Hant"]?.value,
               ja == zh, Self.containsHan(ja), !Self.japaneseSameAsChinese.contains(key) {
                problems.append("\(key) [ja] is identical to zh-Hant: \(ja)")
            }
        }
        #expect(problems.isEmpty, "\(problems)")
    }

    /// One word for "plan" in Korean. The catalog had 플랜 and 요금제 side by side.
    @Test func koreanUsesOnePlanTerm() throws {
        let catalog = try Self.catalog()
        var withPlan: [String] = []
        var withSubscription: [String] = []
        for (key, perLanguage) in catalog.strings {
            guard let ko = perLanguage["ko"]?.value else { continue }
            if ko.contains("플랜") { withPlan.append(key) }
            if ko.contains("요금제") { withSubscription.append(key) }
        }
        #expect(withPlan.isEmpty || withSubscription.isEmpty,
                "both 플랜 (\(withPlan.sorted())) and 요금제 (\(withSubscription.sorted())) are used")
    }

    /// The count is passed through `String(format:)`, so the catalog cannot pick a singular. An
    /// English unit word after the number ("1 times") is therefore wrong for 1; the strings use
    /// a neutral "×" instead.
    @Test func englishCountsAvoidPluralUnitWords() throws {
        let catalog = try Self.catalog()
        let pattern = try NSRegularExpression(
            pattern: #"%d\s*(times|days|hours|minutes|seconds|interruptions|disconnections|events|drops)\b"#
        )
        var problems: [String] = []
        for (key, perLanguage) in catalog.strings {
            guard let en = perLanguage["en"]?.value else { continue }
            let whole = NSRange(en.startIndex..., in: en)
            if pattern.firstMatch(in: en, range: whole) != nil {
                problems.append("\(key): \(en)")
            }
        }
        // The unit that stands beside a separately printed number.
        if let unit = catalog.strings["peak.times.unit"]?["en"]?.value, unit == "times" {
            problems.append("peak.times.unit: \(unit)")
        }
        #expect(problems.isEmpty, "\(problems)")
    }

    /// Words that are written the same in Japanese and Traditional Chinese. A new key that
    /// lands here must be checked by a person, not copied over.
    private static let japaneseSameAsChinese: Set<String> = [
        "button.settings",
        "chart.axis.speed",
        "chart.stats.average",
        "chart.tooltip.average",
        "chart.yaxis.fixed",
        "chart.yaxis.fixedLabel.value",
        "connection.quality.fair",
        "connection.quality.good",
        "disconnect.seconds",
        "network.abnormal",
        "settings.manage",
        "settings.notification.settings",
        "settings.title",
    ]

    // MARK: - Sources

    private static func swiftFiles(under directory: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    /// A lookup outside `L10n.swift` would never be checked against the catalog.
    @Test func noLocalizedLookupOutsideL10n() throws {
        let files = Self.swiftFiles(under: Self.sourcesRoot) + Self.swiftFiles(under: Self.appTargetRoot)
        #expect(files.count > 10)
        var offenders: [String] = []
        for file in files where file.standardizedFileURL != Self.l10nURL.standardizedFileURL {
            let source = try Self.read(file)
            for token in ["String(localized:", "NSLocalizedString(", "LocalizedStringResource("] where source.contains(token) {
                offenders.append("\(file.lastPathComponent): \(token)")
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }

    /// `PlottableValue.value("Time", …)` takes a `LocalizedStringKey`, so a literal label is
    /// looked up in the catalog under that English word, finds nothing, and VoiceOver's audio
    /// graph reads it in English in every language. The labels come from `L10n` instead.
    @Test func chartValueLabelsComeFromL10n() throws {
        let files = Self.swiftFiles(under: Self.sourcesRoot)
        var offenders: [String] = []
        for file in files {
            let source = try Self.read(file)
            for (index, line) in source.components(separatedBy: "\n").enumerated() {
                let code = line.components(separatedBy: "//").first ?? line
                if code.contains(".value(\"") {
                    offenders.append("\(file.lastPathComponent):\(index + 1): \(code.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }

    /// Chinese text in code is only for the internal log and the Chinese `defaultValue`s. A
    /// chart series name or a label written as a literal shows up in every language.
    @Test func noHardCodedChineseInUICode() throws {
        let files = Self.swiftFiles(under: Self.sourcesRoot) + Self.swiftFiles(under: Self.appTargetRoot)
        var offenders: [String] = []
        for file in files where file.standardizedFileURL != Self.l10nURL.standardizedFileURL {
            // `NetworkMonitorError.errorDescription` is only ever passed to the error log.
            if file.lastPathComponent == "ErrorHandler.swift" { continue }
            let source = try Self.read(file)
            for (index, line) in source.components(separatedBy: "\n").enumerated() {
                let code = line.components(separatedBy: "//").first ?? line
                guard Self.containsHan(code) else { continue }
                if code.contains("errorHandler.log(") { continue }
                offenders.append("\(file.lastPathComponent):\(index + 1): \(code.trimmingCharacters(in: .whitespaces))")
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }
}
