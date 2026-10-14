import Testing
@testable import CleanerFeatures

@MainActor
struct ProgressRelayTests {
    @Test func valuesReportedFromOtherThreadsArriveInOrderOnTheMainActor() async {
        var applied: [Int] = []
        let relay = ProgressRelay<Int> { value in
            MainActor.assertIsolated()
            applied.append(value)
        }
        let report = relay.report

        await Task.detached {
            for value in 1...200 { report(value) }
        }.value
        await relay.finish()

        #expect(applied == Array(1...200))
    }

    @Test func finishWithoutValuesReturns() async {
        var applied = 0
        let relay = ProgressRelay<Int> { _ in applied += 1 }

        await relay.finish()

        #expect(applied == 0)
    }
}
