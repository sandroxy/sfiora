import Foundation

/// Bounded recovery rules for transient Core NFC session failures.
struct NfcSessionRecoveryPolicy: Equatable, Sendable {
    static let standard = NfcSessionRecoveryPolicy(
        activationTimeoutMilliseconds: 4_000,
        retryDelayMilliseconds: 600,
        maximumRecoveryCount: 1
    )

    let activationTimeoutMilliseconds: Int
    let retryDelayMilliseconds: Int
    let maximumRecoveryCount: Int

    func canRetrySessionFailure(
        nativeErrorCode: Int,
        completedRecoveryCount: Int
    ) -> Bool {
        completedRecoveryCount < maximumRecoveryCount
            && Self.transientSessionErrorCodes.contains(nativeErrorCode)
    }

    func canRetryActivationTimeout(completedRecoveryCount: Int) -> Bool {
        completedRecoveryCount < maximumRecoveryCount
    }

    private static let transientSessionErrorCodes: Set<Int> = [
        7,  // The current system state is not eligible for scanning.
        8,  // Core NFC access was not accepted for this session.
        202,  // The reader session terminated unexpectedly.
        203,  // Another system NFC session is still being released.
    ]
}
