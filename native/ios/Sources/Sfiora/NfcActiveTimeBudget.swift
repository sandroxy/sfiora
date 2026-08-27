/// Monotonic time budget that advances only while Core NFC is actively
/// scanning. Foreground waits, invalidation, and recovery delays are paused.
struct NfcActiveTimeBudget: Equatable, Sendable {
    private(set) var remainingMilliseconds: Int
    private var resumedAtNanoseconds: UInt64?

    init(milliseconds: Int) {
        precondition(milliseconds >= 0)
        remainingMilliseconds = milliseconds
    }

    mutating func resume(atUptimeNanoseconds uptimeNanoseconds: UInt64) -> Int {
        guard resumedAtNanoseconds == nil else {
            return remainingMilliseconds
        }
        resumedAtNanoseconds = uptimeNanoseconds
        return remainingMilliseconds
    }

    mutating func pause(atUptimeNanoseconds uptimeNanoseconds: UInt64) {
        guard let resumedAtNanoseconds else {
            return
        }
        let elapsedNanoseconds =
            uptimeNanoseconds >= resumedAtNanoseconds
            ? uptimeNanoseconds - resumedAtNanoseconds
            : 0
        remainingMilliseconds = max(
            0,
            remainingMilliseconds - Int(elapsedNanoseconds / 1_000_000)
        )
        self.resumedAtNanoseconds = nil
    }

    mutating func expire() {
        remainingMilliseconds = 0
        resumedAtNanoseconds = nil
    }
}
