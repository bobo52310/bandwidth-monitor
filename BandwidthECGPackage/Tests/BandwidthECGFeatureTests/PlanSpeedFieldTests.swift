import Testing
import Foundation
@testable import BandwidthECGFeature

/// The text-to-model rules behind `PlanSpeedField` (UI-P2-9). The popover's content is released
/// when it closes, so the field also commits a valid pending value when it disappears; that
/// path calls the same `commit`, which is what these tests drive.
@Suite("PlanSpeedField input")
@MainActor
struct PlanSpeedFieldTests {
    private let english = Locale(identifier: "en_US")

    // MARK: - Parsing

    @Test func parse_plainNumber() {
        #expect(PlanSpeedInput.parse("300", locale: english) == 300)
        #expect(PlanSpeedInput.parse("  450 ", locale: english) == 450)
        #expect(PlanSpeedInput.parse("2.5", locale: english) == 2.5)
    }

    @Test func parse_groupingSeparator() {
        #expect(PlanSpeedInput.parse("1,000", locale: english) == 1000)
    }

    @Test func parse_decimalCommaLocale() {
        #expect(PlanSpeedInput.parse("2,5", locale: Locale(identifier: "de_DE")) == 2.5)
    }

    /// An input method can hand over full-width digits.
    @Test func parse_fullWidthDigits() {
        #expect(PlanSpeedInput.parse("３００", locale: english) == 300)
        #expect(PlanSpeedInput.parse("１０００", locale: english) == 1000)
    }

    @Test(arguments: ["", "   ", "abc", "300abc", "nan", "inf", "-", "Mbps"])
    func parse_unusable_isNil(text: String) {
        #expect(PlanSpeedInput.parse(text, locale: english) == nil)
    }

    @Test func display_wholeNumbersWithoutDecimals() {
        #expect(PlanSpeedInput.display(300, locale: english) == "300")
        #expect(PlanSpeedInput.display(1000, locale: english) == "1000")
        #expect(PlanSpeedInput.display(2.5, locale: english) == "2.5")
        #expect(PlanSpeedInput.display(100_000, locale: english) == "100000")
    }

    // MARK: - Committing

    @Test func commit_valid_writesAndShowsTheModelValue() {
        let prefs = UserPreferences(defaults: MemoryDefaults.make(), loginItems: FakeLoginItems())

        let shown = PlanSpeedInput.commit(
            "450",
            current: { prefs.downloadPlanSpeed },
            write: { prefs.downloadPlanSpeed = $0 },
            locale: english
        )

        #expect(prefs.downloadPlanSpeed == 450)
        #expect(shown == "450")
    }

    /// The field used to show a placeholder while the model still held 300.
    @Test func commit_empty_revertsToTheModelValue() {
        var model = 300.0
        var writes = 0

        let shown = PlanSpeedInput.commit(
            "",
            current: { model },
            write: { model = $0; writes += 1 },
            locale: english
        )

        #expect(model == 300)
        #expect(writes == 0)
        #expect(shown == "300")
    }

    @Test func commit_invalid_revertsToTheModelValue() {
        var model = 450.0
        var writes = 0

        let shown = PlanSpeedInput.commit(
            "fast",
            current: { model },
            write: { model = $0; writes += 1 },
            locale: english
        )

        #expect(writes == 0)
        #expect(shown == "450")
    }

    /// The model rejects 0.3; the field then shows what the model kept.
    @Test func commit_belowLowerBound_showsWhatTheModelKept() {
        let prefs = UserPreferences(defaults: MemoryDefaults.make(), loginItems: FakeLoginItems())
        prefs.uploadPlanSpeed = 120

        let shown = PlanSpeedInput.commit(
            "0.3",
            current: { prefs.uploadPlanSpeed },
            write: { prefs.uploadPlanSpeed = $0 },
            locale: english
        )

        #expect(prefs.uploadPlanSpeed == 120)
        #expect(shown == "120")
    }

    @Test func commit_zeroAndNegative_showWhatTheModelKept() {
        let prefs = UserPreferences(defaults: MemoryDefaults.make(), loginItems: FakeLoginItems())

        for text in ["0", "-5"] {
            let shown = PlanSpeedInput.commit(
                text,
                current: { prefs.downloadPlanSpeed },
                write: { prefs.downloadPlanSpeed = $0 },
                locale: english
            )
            #expect(prefs.downloadPlanSpeed == 300)
            #expect(shown == "300")
        }
    }

    @Test func commit_aboveUpperBound_showsTheClampedValue() {
        let prefs = UserPreferences(defaults: MemoryDefaults.make(), loginItems: FakeLoginItems())

        let shown = PlanSpeedInput.commit(
            "999999999",
            current: { prefs.downloadPlanSpeed },
            write: { prefs.downloadPlanSpeed = $0 },
            locale: english
        )

        #expect(prefs.downloadPlanSpeed == 100_000)
        #expect(shown == "100000")
    }

    @Test func commit_unchangedValue_isNotWrittenAgain() {
        var model = 300.0
        var writes = 0

        let shown = PlanSpeedInput.commit(
            "300",
            current: { model },
            write: { model = $0; writes += 1 },
            locale: english
        )

        #expect(writes == 0)
        #expect(shown == "300")
    }

    /// Typing 450 and closing the popover without pressing return: the disappear handler
    /// commits the text still sitting in the field, once, and a second commit changes nothing.
    @Test func commit_pendingValueOnDisappear_isKept() {
        let defaults = MemoryDefaults.make()
        let prefs = UserPreferences(defaults: defaults, loginItems: FakeLoginItems())
        var fieldText = "450"

        fieldText = PlanSpeedInput.commit(
            fieldText,
            current: { prefs.downloadPlanSpeed },
            write: { prefs.downloadPlanSpeed = $0 },
            locale: english
        )
        fieldText = PlanSpeedInput.commit(
            fieldText,
            current: { prefs.downloadPlanSpeed },
            write: { prefs.downloadPlanSpeed = $0 },
            locale: english
        )

        #expect(defaults.double(forKey: "downloadPlanSpeed") == 450)
        #expect(UserPreferences(defaults: defaults, loginItems: FakeLoginItems()).downloadPlanSpeed == 450)
        #expect(fieldText == "450")
    }

    /// An invalid pending value on disappear is dropped, not saved, and the model is untouched.
    @Test func commit_invalidPendingValueOnDisappear_isDropped() {
        let defaults = MemoryDefaults.make()
        let prefs = UserPreferences(defaults: defaults, loginItems: FakeLoginItems())
        prefs.downloadPlanSpeed = 500

        _ = PlanSpeedInput.commit(
            "",
            current: { prefs.downloadPlanSpeed },
            write: { prefs.downloadPlanSpeed = $0 },
            locale: english
        )

        #expect(defaults.double(forKey: "downloadPlanSpeed") == 500)
        #expect(prefs.downloadPlanSpeed == 500)
    }
}
