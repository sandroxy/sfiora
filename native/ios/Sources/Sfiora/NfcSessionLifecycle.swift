enum NfcSessionPhase: Equatable {
    case idle
    case waitingForForeground
    case active
    case invalidating
}

enum NfcSessionStartDecision: Equatable {
    case start
    case waitForForeground
    case busy
}

/// Platform-independent ordering for one Core NFC request and its session.
struct NfcSessionLifecycle<Completion> {
    private enum PendingCompletion {
        case none
        case value(Completion)
    }

    private(set) var phase: NfcSessionPhase = .idle
    private var pendingCompletion: PendingCompletion = .none

    var isRunning: Bool { phase != .idle }

    mutating func begin(applicationIsActive: Bool) -> NfcSessionStartDecision {
        guard phase == .idle else {
            return .busy
        }
        if applicationIsActive {
            phase = .active
            return .start
        }
        phase = .waitingForForeground
        return .waitForForeground
    }

    mutating func resumeWaitingRequest() -> Bool {
        guard phase == .waitingForForeground else {
            return false
        }
        phase = .active
        return true
    }

    mutating func prepareRetry() -> Bool {
        guard phase == .idle else {
            return false
        }
        phase = .waitingForForeground
        return true
    }

    mutating func abortStart() {
        guard phase == .active else {
            return
        }
        reset()
    }

    mutating func completeWaitingRequest(with completion: Completion) -> Completion? {
        guard phase == .waitingForForeground else {
            return nil
        }
        reset()
        return completion
    }

    mutating func completeWaitingRequest() -> Bool {
        guard phase == .waitingForForeground else {
            return false
        }
        reset()
        return true
    }

    mutating func requestInvalidation(with completion: Completion) -> Bool {
        guard phase == .active else {
            return false
        }
        phase = .invalidating
        pendingCompletion = .value(completion)
        return true
    }

    mutating func requestInvalidationWithoutPendingCompletion() -> Bool {
        guard phase == .active else {
            return false
        }
        phase = .invalidating
        pendingCompletion = .none
        return true
    }

    mutating func completeInvalidation(fallback: Completion) -> Completion? {
        let completion: Completion?
        switch phase {
        case .idle, .waitingForForeground:
            return nil
        case .active:
            completion = fallback
        case .invalidating:
            switch pendingCompletion {
            case .none:
                completion = nil
            case .value(let value):
                completion = value
            }
        }
        reset()
        return completion
    }

    /// End business waiting without claiming that Core NFC has released its session.
    mutating func takeInvalidatingCompletion() -> Completion? {
        guard phase == .invalidating else { return nil }
        let completion: Completion?
        switch pendingCompletion {
        case .none: completion = nil
        case .value(let value): completion = value
        }
        pendingCompletion = .none
        return completion
    }

    private mutating func reset() {
        phase = .idle
        pendingCompletion = .none
    }
}
