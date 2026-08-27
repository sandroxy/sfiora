import XCTest

@testable import Sfiora

final class NfcActiveTimeBudgetTests: XCTestCase {
    func testBudgetAdvancesOnlyWhileCoreNfcIsActive() {
        var budget = NfcActiveTimeBudget(milliseconds: 30_000)

        XCTAssertEqual(budget.resume(atUptimeNanoseconds: 1_000_000_000), 30_000)
        budget.pause(atUptimeNanoseconds: 11_000_000_000)
        XCTAssertEqual(budget.remainingMilliseconds, 20_000)

        XCTAssertEqual(budget.resume(atUptimeNanoseconds: 61_000_000_000), 20_000)
        budget.pause(atUptimeNanoseconds: 66_000_000_000)
        XCTAssertEqual(budget.remainingMilliseconds, 15_000)
    }

    func testDuplicateResumeDoesNotResetElapsedOrigin() {
        var budget = NfcActiveTimeBudget(milliseconds: 5_000)
        _ = budget.resume(atUptimeNanoseconds: 1_000_000_000)
        _ = budget.resume(atUptimeNanoseconds: 3_000_000_000)

        budget.pause(atUptimeNanoseconds: 5_000_000_000)

        XCTAssertEqual(budget.remainingMilliseconds, 1_000)
    }

    func testExpiredBudgetCannotGainTimeDuringRecovery() {
        var budget = NfcActiveTimeBudget(milliseconds: 1_000)
        _ = budget.resume(atUptimeNanoseconds: 1_000_000_000)
        budget.expire()

        XCTAssertEqual(budget.remainingMilliseconds, 0)
        XCTAssertEqual(budget.resume(atUptimeNanoseconds: 10_000_000_000), 0)
    }
}
