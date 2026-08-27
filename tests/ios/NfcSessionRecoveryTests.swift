import XCTest

@testable import Sfiora

final class NfcSessionRecoveryTests: XCTestCase {
    private let policy = NfcSessionRecoveryPolicy.standard

    func testRecoveryTimingIsShortAndBounded() {
        XCTAssertEqual(policy.activationTimeoutMilliseconds, 4_000)
        XCTAssertEqual(policy.retryDelayMilliseconds, 600)
        XCTAssertEqual(policy.maximumRecoveryCount, 1)
    }

    func testOnlyTransientSessionFailuresRetryOnce() {
        for code in [7, 8, 202, 203] {
            XCTAssertTrue(
                policy.canRetrySessionFailure(
                    nativeErrorCode: code,
                    completedRecoveryCount: 0
                )
            )
            XCTAssertFalse(
                policy.canRetrySessionFailure(
                    nativeErrorCode: code,
                    completedRecoveryCount: 1
                )
            )
        }
        for code in [100, 104, 200, 201] {
            XCTAssertFalse(
                policy.canRetrySessionFailure(
                    nativeErrorCode: code,
                    completedRecoveryCount: 0
                )
            )
        }
        XCTAssertTrue(policy.canRetryActivationTimeout(completedRecoveryCount: 0))
        XCTAssertFalse(policy.canRetryActivationTimeout(completedRecoveryCount: 1))
    }

    func testDeliveredSuccessKeepsLifecycleBusyUntilInvalidation() {
        var lifecycle = NfcSessionLifecycle<String>()
        XCTAssertEqual(lifecycle.begin(applicationIsActive: true), .start)
        XCTAssertTrue(lifecycle.requestInvalidationWithoutPendingCompletion())
        XCTAssertEqual(lifecycle.phase, .invalidating)
        XCTAssertEqual(lifecycle.begin(applicationIsActive: true), .busy)

        XCTAssertNil(lifecycle.completeInvalidation(fallback: "system error"))
        XCTAssertEqual(lifecycle.phase, .idle)
    }

    func testReleasedSessionCanWaitForOneRecoveryWithoutGoingIdle() {
        var lifecycle = NfcSessionLifecycle<String>()
        XCTAssertEqual(lifecycle.begin(applicationIsActive: true), .start)
        XCTAssertEqual(
            lifecycle.completeInvalidation(fallback: "retry"),
            "retry"
        )
        XCTAssertTrue(lifecycle.prepareRetry())
        XCTAssertTrue(lifecycle.isRunning)
        XCTAssertTrue(lifecycle.resumeWaitingRequest())
        XCTAssertEqual(lifecycle.phase, .active)
    }
}
