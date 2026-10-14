import Foundation
import Testing
@testable import CleanerFeatures

/// Gli esiti attesi sono quelli di `ViewModelBase.FormatBytes`, `N0` e `ToString("d MMM yyyy,
/// HH:mm", it-IT)` misurati su .NET 10 (piano 4a, «Fatti misurati»).
struct FormattingTests {
    @Test(arguments: [
        (Int64(0), "0 B"), (1, "1 B"), (1023, "1023 B"), (1024, "1 KB"), (1075, "1 KB"),
        (1126, "1,1 KB"), (1280, "1,3 KB"), (1331, "1,3 KB"), (1536, "1,5 KB"), (10_240, "10 KB"),
        (1_048_575, "1024 KB"), (1_048_576, "1 MB"), (2_621_440, "2,5 MB"), (2_673_869, "2,6 MB"),
        (10_200_547_328, "9,5 GB"), (11_811_160_064, "11 GB"), (1_099_511_627_776, "1 TB"),
        (1_152_921_504_606_846_976, "1048576 TB"), (Int64.max, "8388608 TB"), (-1, "-1 B"), (-5000, "-5000 B"),
    ])
    func bytesFollowFormatBytes(bytes: Int64, expected: String) {
        #expect(Formatting.bytes(bytes) == expected)
    }

    @Test(arguments: [
        (Int64(0), "0"), (999, "999"), (1000, "1.000"), (2117, "2.117"), (1_234_567, "1.234.567"),
        (-2117, "-2.117"), (Int64.max, "9.223.372.036.854.775.807"), (Int64.min, "-9.223.372.036.854.775.808"),
    ])
    func integersUseTheItalianThousandsSeparator(value: Int64, expected: String) {
        #expect(Formatting.integer(value) == expected)
    }

    @Test func pluralAgreesOnlyWithOne() {
        #expect(Formatting.plural(1, "elemento", "elementi") == "elemento")
        #expect(Formatting.plural(0, "elemento", "elementi") == "elementi")
        #expect(Formatting.plural(2, "elemento", "elementi") == "elementi")
    }

    @Test(arguments: [
        (Duration.zero, "0"), (.milliseconds(400), "0"), (.milliseconds(500), "1"), (.milliseconds(1500), "2"),
        (.milliseconds(2500), "3"), (.milliseconds(3490), "3"), (.milliseconds(59_500), "60"), (.milliseconds(120_400), "120"),
    ])
    func secondsRoundHalfAwayFromZero(duration: Duration, expected: String) {
        #expect(Formatting.seconds(duration) == expected)
    }

    @Test func historyDateUsesItalianMonthsInTheGivenTimeZone() throws {
        let rome = try #require(TimeZone(identifier: "Europe/Rome"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = rome
        let months = ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"]

        for (offset, month) in months.enumerated() {
            let date = try #require(calendar.date(from: DateComponents(year: 2026, month: offset + 1, day: 6, hour: 9, minute: 5)))
            #expect(Formatting.historyDate(date, timeZone: rome) == "6 \(month) 2026, 09:05")
        }

        let utc = try #require(TimeZone(identifier: "UTC"))
        let instant = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 1, minute: 19)))
        #expect(Formatting.historyDate(instant, timeZone: rome) == "26 set 2026, 01:19")
        // Lo stesso istante in UTC è il giorno prima: la data segue il fuso indicato.
        #expect(Formatting.historyDate(instant, timeZone: utc) == "25 set 2026, 23:19")
    }
}
