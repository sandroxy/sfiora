import Foundation

public enum NfcClientState: String, Equatable, Sendable {
    case idle
    case reading
    case writing
}

#if os(iOS) && canImport(CoreNFC) && canImport(UIKit)
    import CoreNFC
    import UIKit

    /// OS boundary for deterministic session tests; the public initializer uses live services.
    struct NfcClientEnvironment {
        var capabilities: () -> NfcCapabilities = { .current }
        var applicationIsActive: () -> Bool = { UIApplication.shared.applicationState == .active }
        var makeTagSession:
            (
                NFCTagReaderSession.PollingOption, NFCTagReaderSessionDelegate, DispatchQueue
            ) -> NFCTagReaderSession? = {
                NFCTagReaderSession(pollingOption: $0, delegate: $1, queue: $2)
            }
    }

    private final class NfcCompatibilitySessionDelegate: NSObject,
        NFCNDEFReaderSessionDelegate
    {
        weak var owner: NfcClient?

        init(owner: NfcClient) {
            self.owner = owner
        }

        func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
            owner?.ndefSessionDidBecomeActive(session)
        }

        func readerSession(
            _ session: NFCNDEFReaderSession,
            didDetectNDEFs messages: [NFCNDEFMessage]
        ) {
            owner?.compatibilitySession(session, didDetect: messages)
        }

        func readerSession(
            _ session: NFCNDEFReaderSession,
            didInvalidateWithError error: Error
        ) {
            owner?.ndefSession(session, didInvalidateWith: error)
        }
    }

    private final class NfcWritableSessionDelegate: NSObject,
        NFCNDEFReaderSessionDelegate
    {
        weak var owner: NfcClient?

        init(owner: NfcClient) {
            self.owner = owner
        }

        func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
            owner?.ndefSessionDidBecomeActive(session)
        }

        func readerSession(
            _: NFCNDEFReaderSession,
            didDetectNDEFs _: [NFCNDEFMessage]
        ) {
            // A writable session receives tags through the iOS 13 tag callback.
        }

        func readerSession(
            _ session: NFCNDEFReaderSession,
            didDetect tags: [NFCNDEFTag]
        ) {
            owner?.writableSession(session, didDetect: tags)
        }

        func readerSession(
            _ session: NFCNDEFReaderSession,
            didInvalidateWithError error: Error
        ) {
            owner?.ndefSession(session, didInvalidateWith: error)
        }
    }

    private final class NfcTagSessionDelegate: NSObject, NFCTagReaderSessionDelegate {
        weak var owner: NfcClient?

        init(owner: NfcClient) {
            self.owner = owner
        }

        func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
            owner?.tagSessionDidBecomeActive(session)
        }

        func tagReaderSession(
            _ session: NFCTagReaderSession,
            didDetect tags: [NFCTag]
        ) {
            owner?.tagSession(session, didDetect: tags)
        }

        func tagReaderSession(
            _ session: NFCTagReaderSession,
            didInvalidateWithError error: Error
        ) {
            owner?.tagSession(session, didInvalidateWith: error)
        }
    }

    private enum NfcClientRequest {
        case read(
            NfcReadConfiguration,
            (Result<NfcTagSnapshot, NfcError>) -> Void
        )
        case write(
            NdefMessage,
            NfcWriteConfiguration,
            (Result<NfcWriteResult, NfcError>) -> Void
        )
        case initialize(
            NdefMessage,
            NdefExternalType,
            NfcWriteConfiguration,
            (Result<NfcInitializationResult, NfcError>) -> Void
        )

        var kind: NfcOperationKind {
            switch self {
            case .read:
                return .read
            case .write, .initialize:
                return .write
            }
        }

        var timeoutMilliseconds: Int {
            switch self {
            case .read(let configuration, _):
                return configuration.timeoutMilliseconds
            case .write(_, let configuration, _),
                .initialize(_, _, let configuration, _):
                return configuration.timeoutMilliseconds
            }
        }
    }

    private enum NfcClientCompletion {
        case read(NfcTagSnapshot)
        case write(NfcWriteResult)
        case initialize(NfcInitializationResult)
        case failure(NfcError)
        case retry
        case silent
    }

    private enum NfcActiveSession {
        case compatibility(
            NFCNDEFReaderSession,
            NfcCompatibilitySessionDelegate
        )
        case writable(
            NFCNDEFReaderSession,
            NfcWritableSessionDelegate
        )
        case tag(NFCTagReaderSession, NfcTagSessionDelegate)

        func matches(_ session: NFCNDEFReaderSession) -> Bool {
            switch self {
            case .compatibility(let current, _), .writable(let current, _):
                return current === session
            case .tag:
                return false
            }
        }

        func matches(_ session: NFCTagReaderSession) -> Bool {
            switch self {
            case .tag(let current, _):
                return current === session
            case .compatibility, .writable:
                return false
            }
        }

        func setAlertMessage(_ message: String) {
            switch self {
            case .compatibility(let session, _), .writable(let session, _):
                session.alertMessage = message
            case .tag(let session, _):
                session.alertMessage = message
            }
        }

        func invalidate(errorMessage: String?) {
            switch self {
            case .compatibility(let session, _), .writable(let session, _):
                if let errorMessage {
                    session.invalidate(errorMessage: errorMessage)
                } else {
                    session.invalidate()
                }
            case .tag(let session, _):
                if let errorMessage {
                    session.invalidate(errorMessage: errorMessage)
                } else {
                    session.invalidate()
                }
            }
        }
    }

    /// Executes one foreground NFC read or write operation at a time.
    public final class NfcClient: NSObject {
        private let environment: NfcClientEnvironment
        private let observableStateLock = NSLock()
        private var observableOperationKind: NfcOperationKind?
        private var observableStateHandler: ((NfcClientState) -> Void)?

        private var request: NfcClientRequest?
        private var operationIdentifier: UUID?
        private var operationLease: NfcOperationLease?
        private var activeSession: NfcActiveSession?
        private var lifecycle = NfcSessionLifecycle<NfcClientCompletion>()
        private var invalidationDeadlineWorkItem: DispatchWorkItem?
        private var operationTimeoutWorkItem: DispatchWorkItem?
        private var activationTimeoutWorkItem: DispatchWorkItem?
        private var recoveryWorkItem: DispatchWorkItem?
        private var activeTimeBudget: NfcActiveTimeBudget?
        private let recoveryPolicy = NfcSessionRecoveryPolicy.standard
        private var sessionDidBecomeActive = false
        private var recoveryCount = 0
        private var applicationIsActive = false
        private var tagOperationInFlight = false
        private var writeCommandStarted = false
        private var writeVerified = false
        private var applicationObservers: [NSObjectProtocol] = []

        public override convenience init() {
            self.init(environment: NfcClientEnvironment())
        }

        init(environment: NfcClientEnvironment) {
            self.environment = environment
            super.init()
            observeApplicationLifecycle()
        }

        deinit {
            applicationObservers.forEach(NotificationCenter.default.removeObserver)
            operationTimeoutWorkItem?.cancel()
            activationTimeoutWorkItem?.cancel()
            recoveryWorkItem?.cancel()
            activeSession?.invalidate(errorMessage: nil)
            NfcOperationCoordinator.release(operationLease)
        }

        public var capabilities: NfcCapabilities { environment.capabilities() }

        public var state: NfcClientState {
            observableStateLock.lock()
            defer { observableStateLock.unlock() }
            switch observableOperationKind {
            case .read: return .reading
            case .write: return .writing
            case nil: return .idle
            }
        }

        /// Receives state changes on the main thread. Terminal callbacks are
        /// delivered after `.idle`, except successful Core NFC results: those
        /// are delivered immediately while the system panel is dismissing.
        /// A closing failure/cancellation may complete after a five-second grace
        /// period while state remains busy until Core NFC confirms invalidation.
        public var stateChangeHandler: ((NfcClientState) -> Void)? {
            get {
                observableStateLock.lock()
                defer { observableStateLock.unlock() }
                return observableStateHandler
            }
            set {
                observableStateLock.lock()
                observableStateHandler = newValue
                observableStateLock.unlock()
            }
        }

        public var isReading: Bool {
            observableStateLock.lock()
            defer { observableStateLock.unlock() }
            return observableOperationKind == .read
        }

        public var isWriting: Bool {
            observableStateLock.lock()
            defer { observableStateLock.unlock() }
            return observableOperationKind == .write
        }

        public func startRead(
            configuration: NfcReadConfiguration = .standard,
            completion: @escaping (Result<NfcTagSnapshot, NfcError>) -> Void
        ) {
            runOnMain {
                self.start(.read(configuration, completion))
            }
        }

        public func startWrite(
            message: NdefMessage,
            configuration: NfcWriteConfiguration = .standard,
            completion: @escaping (Result<NfcWriteResult, NfcError>) -> Void
        ) {
            runOnMain {
                self.start(.write(message, configuration, completion))
            }
        }

        public func startInitialize(
            message: NdefMessage,
            marker: NdefExternalType,
            configuration: NfcWriteConfiguration = .standard,
            completion: @escaping (Result<NfcInitializationResult, NfcError>) -> Void
        ) throws {
            try NdefWritePolicy.validateInitializationMessage(message, marker: marker)
            runOnMain {
                self.start(.initialize(message, marker, configuration, completion))
            }
        }

        public func cancelRead() {
            runOnMain {
                guard self.request?.kind == .read else {
                    return
                }
                self.finish(
                    .failure(
                        NfcError(
                            code: .userCancelled,
                            message: "The NFC scan was cancelled",
                            recoverable: true
                        )
                    )
                )
            }
        }

        public func cancelWrite() {
            runOnMain {
                guard self.request?.kind == .write else {
                    return
                }
                self.finish(
                    .failure(
                        NfcError(
                            code: .userCancelled,
                            message: self.uncertainWriteMessage("The NFC write was cancelled"),
                            recoverable: true
                        )
                    )
                )
            }
        }

        /// Stops the active operation without delivering a terminal callback.
        public func stop() {
            runOnMain {
                guard self.request != nil else {
                    return
                }
                _ = self.lifecycle.takeInvalidatingCompletion()
                self.finish(.silent)
            }
        }

        private func start(_ newRequest: NfcClientRequest) {
            dispatchPrecondition(condition: .onQueue(.main))
            guard request == nil, !lifecycle.isRunning else {
                deliver(
                    request: newRequest,
                    completion: .failure(busyError(for: newRequest.kind))
                )
                return
            }
            guard capabilities.supported else {
                deliver(
                    request: newRequest,
                    completion: .failure(
                        NfcError(
                            code: .nfcUnsupported,
                            message: "This device does not support Core NFC tag reading",
                            recoverable: false
                        )
                    )
                )
                return
            }
            guard let lease = NfcOperationCoordinator.acquire(newRequest.kind) else {
                deliver(
                    request: newRequest,
                    completion: .failure(busyError(for: newRequest.kind))
                )
                return
            }

            request = newRequest
            operationIdentifier = UUID()
            operationLease = lease
            tagOperationInFlight = false
            writeCommandStarted = false
            writeVerified = false
            recoveryCount = 0
            activeTimeBudget = NfcActiveTimeBudget(
                milliseconds: newRequest.timeoutMilliseconds
            )
            applicationIsActive = environment.applicationIsActive()
            let identifier = operationIdentifier
            let decision = lifecycle.begin(
                applicationIsActive: applicationIsActive
            )
            switch decision {
            case .start:
                beginCoreNfcSession()
                if request != nil, operationIdentifier == identifier {
                    setObservableOperationKind(newRequest.kind)
                }
            case .waitForForeground:
                setObservableOperationKind(newRequest.kind)
            case .busy:
                finishRequestWithoutSession(
                    .failure(
                        NfcError(
                            code: .internalError,
                            message: "The NFC client entered an invalid start state",
                            recoverable: false
                        )
                    )
                )
            }
        }

        private func beginCoreNfcSession() {
            dispatchPrecondition(condition: .onQueue(.main))
            guard lifecycle.phase == .active, activeSession == nil, let request else {
                lifecycle.abortStart()
                finishRequestWithoutSession(
                    .failure(
                        NfcError(
                            code: .internalError,
                            message: "The NFC client entered an invalid session state",
                            recoverable: false
                        )
                    )
                )
                return
            }

            sessionDidBecomeActive = false
            switch request {
            case .read(let configuration, _):
                switch configuration.mode {
                case .ndef:
                    let proxy = NfcCompatibilitySessionDelegate(owner: self)
                    let session = NFCNDEFReaderSession(
                        delegate: proxy,
                        queue: .main,
                        invalidateAfterFirstRead: false
                    )
                    session.alertMessage = configuration.alertMessage
                    activeSession = .compatibility(session, proxy)
                case .automatic, .discover:
                    let proxy = NfcTagSessionDelegate(owner: self)
                    guard
                        let session = environment.makeTagSession(
                            pollingOptions(configuration.pollingTechnologies), proxy, .main
                        )
                    else {
                        lifecycle.abortStart()
                        finishRequestWithoutSession(
                            .failure(
                                NfcError(
                                    code: .internalError,
                                    message: "Core NFC could not create a tag reader session",
                                    recoverable: false
                                )
                            )
                        )
                        return
                    }
                    session.alertMessage = configuration.alertMessage
                    activeSession = .tag(session, proxy)
                }
            case .write(_, let configuration, _),
                .initialize(_, _, let configuration, _):
                let proxy = NfcWritableSessionDelegate(owner: self)
                let session = NFCNDEFReaderSession(
                    delegate: proxy,
                    queue: .main,
                    invalidateAfterFirstRead: false
                )
                session.alertMessage = configuration.alertMessage
                activeSession = .writable(session, proxy)
            }

            scheduleActivationTimeout()
            switch activeSession {
            case .compatibility(let session, _), .writable(let session, _):
                session.begin()
            case .tag(let session, _):
                session.begin()
            case nil:
                break
            }
        }

        private func scheduleActivationTimeout() {
            activationTimeoutWorkItem?.cancel()
            guard let identifier = operationIdentifier else {
                return
            }
            let workItem = DispatchWorkItem { [weak self] in
                guard
                    let self,
                    self.operationIdentifier == identifier,
                    self.lifecycle.phase == .active,
                    !self.sessionDidBecomeActive
                else {
                    return
                }
                self.activationTimeoutWorkItem = nil
                if self.recoveryPolicy.canRetryActivationTimeout(
                    completedRecoveryCount: self.recoveryCount
                ) {
                    self.requestSessionRetry()
                    return
                }
                let reading = self.request?.kind == .read
                self.finish(
                    .failure(
                        NfcError(
                            code: reading ? .scanBusy : .writeBusy,
                            message: "Core NFC did not become ready for this operation",
                            recoverable: true
                        )
                    )
                )
            }
            activationTimeoutWorkItem = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now()
                    + .milliseconds(
                        recoveryPolicy.activationTimeoutMilliseconds
                    ),
                execute: workItem
            )
        }

        private func markSessionActive() {
            guard
                lifecycle.phase == .active,
                !sessionDidBecomeActive,
                request != nil
            else {
                return
            }
            sessionDidBecomeActive = true
            activationTimeoutWorkItem?.cancel()
            activationTimeoutWorkItem = nil
            scheduleOperationTimeout()
        }

        private func scheduleOperationTimeout() {
            operationTimeoutWorkItem?.cancel()
            guard
                let identifier = operationIdentifier,
                let request,
                var budget = activeTimeBudget
            else {
                return
            }
            let remainingMilliseconds = budget.resume(
                atUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
            )
            activeTimeBudget = budget
            guard remainingMilliseconds > 0 else {
                finish(
                    .failure(timeoutError(for: request)), errorMessage: timeoutMessage(for: request)
                )
                return
            }
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.operationIdentifier == identifier else {
                    return
                }
                self.operationTimeoutWorkItem = nil
                self.activeTimeBudget?.expire()
                self.finish(
                    .failure(self.timeoutError(for: request)),
                    errorMessage: self.timeoutMessage(for: request)
                )
            }
            operationTimeoutWorkItem = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + .milliseconds(remainingMilliseconds),
                execute: workItem
            )
        }

        private func timeoutError(for request: NfcClientRequest) -> NfcError {
            let reading = request.kind == .read
            return NfcError(
                code: reading ? .scanTimeout : .writeTimeout,
                message: reading
                    ? "The NFC scan did not complete before the configured timeout"
                    : uncertainWriteMessage(
                        "The NFC write did not complete before the configured timeout"
                    ),
                recoverable: true
            )
        }

        private func timeoutMessage(for request: NfcClientRequest) -> String {
            switch request {
            case .read(let configuration, _):
                return configuration.presentationMessages.timeout
            case .write(_, let configuration, _),
                .initialize(_, _, let configuration, _):
                return configuration.presentationMessages.timeout
            }
        }

        private func finish(
            _ completion: NfcClientCompletion,
            alertMessage: String? = nil,
            errorMessage: String? = nil
        ) {
            dispatchPrecondition(condition: .onQueue(.main))
            if let waitingCompletion = lifecycle.completeWaitingRequest(with: completion) {
                finishRequestWithoutSession(waitingCompletion)
                return
            }
            guard
                let activeSession,
                lifecycle.requestInvalidation(with: completion)
            else {
                return
            }

            cancelSessionWorkItems()
            scheduleInvalidationDeadline()
            if let alertMessage {
                activeSession.setAlertMessage(alertMessage)
            }
            activeSession.invalidate(errorMessage: errorMessage.map(sessionErrorMessage))
        }

        private func finishSuccess(
            _ completion: NfcClientCompletion,
            alertMessage: String
        ) {
            dispatchPrecondition(condition: .onQueue(.main))
            guard
                let request,
                let activeSession,
                lifecycle.requestInvalidationWithoutPendingCompletion()
            else {
                return
            }
            cancelSessionWorkItems()
            activeSession.setAlertMessage(alertMessage)
            activeSession.invalidate(errorMessage: nil)
            deliver(request: request, completion: completion)
        }

        private func completeInvalidatedSession(error: Error) {
            dispatchPrecondition(condition: .onQueue(.main))
            guard activeSession != nil else {
                return
            }
            applicationIsActive = environment.applicationIsActive()
            let nativeError = error as NSError
            let fallback: NfcClientCompletion
            if nativeError.domain == NFCErrorDomain,
                recoveryPolicy.canRetrySessionFailure(
                    nativeErrorCode: nativeError.code,
                    completedRecoveryCount: recoveryCount,
                    writeCommandStarted: writeCommandStarted
                )
            {
                fallback = .retry
            } else {
                fallback = .failure(publicError(from: error))
            }

            let completion = lifecycle.completeInvalidation(fallback: fallback)
            let isRetry: Bool
            if case .retry = completion {
                isRetry = true
            } else {
                isRetry = false
            }
            let shouldRetry = isRetry && applicationIsActive
            releaseActiveSession(preserveRequest: shouldRetry)

            if shouldRetry {
                scheduleRecovery()
                return
            }
            if isRetry {
                let reading = request?.kind == .read
                finishRequestWithoutSession(
                    .failure(
                        NfcError(
                            code: reading ? .readFailed : .writeFailed,
                            message: reading
                                ? "The NFC scan ended when the app left the foreground"
                                : uncertainWriteMessage(
                                    "The NFC write ended when the app left the foreground"
                                ),
                            recoverable: true
                        )
                    )
                )
                return
            }
            finishRequestWithoutSession(completion ?? .silent)
        }

        private func requestSessionRetry() {
            guard
                let activeSession,
                lifecycle.requestInvalidation(with: .retry)
            else {
                return
            }
            cancelSessionWorkItems()
            scheduleInvalidationDeadline()
            activeSession.invalidate(errorMessage: nil)
        }

        private func scheduleInvalidationDeadline() {
            guard let identifier = operationIdentifier else { return }
            let workItem = DispatchWorkItem { [weak self] in
                guard let self,
                    self.operationIdentifier == identifier,
                    let request = self.request,
                    let pending = self.lifecycle.takeInvalidatingCompletion()
                else { return }
                self.invalidationDeadlineWorkItem = nil
                let completion: NfcClientCompletion
                switch pending {
                case .retry:
                    completion = .failure(
                        NfcError(
                            code: .sessionCloseTimeout,
                            message:
                                "Core NFC did not finish closing its session; NFC remains busy",
                            recoverable: true
                        ))
                case .failure(let error):
                    completion = .failure(
                        error.acknowledgingUnverifiedWrite(
                            commandStarted: self.writeCommandStarted, verified: self.writeVerified
                        ))
                default:
                    completion = pending
                }
                // The late invalidation delegate still owns resource/lease release.
                // In particular, do not report idle or start recovery here.
                self.deliver(request: request, completion: completion)
            }
            invalidationDeadlineWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(5), execute: workItem)
        }

        private func releaseActiveSession(preserveRequest: Bool) {
            activeSession = nil
            sessionDidBecomeActive = false
            tagOperationInFlight = false
            cancelSessionWorkItems()
            if !preserveRequest {
                recoveryWorkItem?.cancel()
                recoveryWorkItem = nil
            }
        }

        private func scheduleRecovery() {
            guard request != nil, lifecycle.prepareRetry() else {
                finishRequestWithoutSession(
                    .failure(
                        NfcError(
                            code: .internalError,
                            message: "The NFC client could not prepare its recovery attempt",
                            recoverable: true
                        )
                    )
                )
                return
            }
            recoveryCount += 1
            recoveryWorkItem?.cancel()
            guard let identifier = operationIdentifier else {
                return
            }
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.operationIdentifier == identifier else {
                    return
                }
                self.recoveryWorkItem = nil
                self.applicationIsActive = self.environment.applicationIsActive()
                self.resumeWaitingRequestIfPossible()
            }
            recoveryWorkItem = workItem
            DispatchQueue.main.asyncAfter(
                deadline: .now()
                    + .milliseconds(
                        recoveryPolicy.retryDelayMilliseconds
                    ),
                execute: workItem
            )
        }

        private func resumeWaitingRequestIfPossible() {
            guard
                recoveryWorkItem == nil,
                applicationIsActive,
                lifecycle.resumeWaitingRequest()
            else {
                return
            }
            beginCoreNfcSession()
        }

        private func finishRequestWithoutSession(_ completion: NfcClientCompletion) {
            dispatchPrecondition(condition: .onQueue(.main))
            cancelAllWorkItems()
            let completedRequest = request
            let lease = operationLease
            let normalizedCompletion: NfcClientCompletion
            if case .failure(let error) = completion, request?.kind == .write {
                normalizedCompletion = .failure(
                    error.acknowledgingUnverifiedWrite(
                        commandStarted: writeCommandStarted, verified: writeVerified
                    )
                )
            } else {
                normalizedCompletion = completion
            }
            request = nil
            operationIdentifier = nil
            operationLease = nil
            activeSession = nil
            recoveryCount = 0
            sessionDidBecomeActive = false
            tagOperationInFlight = false
            writeCommandStarted = false
            writeVerified = false
            NfcOperationCoordinator.release(lease)
            // An idle observer may synchronously start the next operation.
            setObservableOperationKind(nil)
            if let completedRequest {
                deliver(request: completedRequest, completion: normalizedCompletion)
            }
        }

        private func cancelSessionWorkItems() {
            invalidationDeadlineWorkItem?.cancel()
            invalidationDeadlineWorkItem = nil
            if var budget = activeTimeBudget {
                budget.pause(
                    atUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
                )
                activeTimeBudget = budget
            }
            operationTimeoutWorkItem?.cancel()
            operationTimeoutWorkItem = nil
            activationTimeoutWorkItem?.cancel()
            activationTimeoutWorkItem = nil
        }

        private func cancelAllWorkItems() {
            cancelSessionWorkItems()
            activeTimeBudget = nil
            recoveryWorkItem?.cancel()
            recoveryWorkItem = nil
        }

        private func deliver(
            request: NfcClientRequest,
            completion: NfcClientCompletion
        ) {
            switch (request, completion) {
            case (.read(_, let callback), .read(let value)):
                callback(.success(value))
            case (.write(_, _, let callback), .write(let value)):
                callback(.success(value))
            case (.initialize(_, _, _, let callback), .initialize(let value)):
                callback(.success(value))
            case (.read(_, let callback), .failure(let error)):
                callback(.failure(error))
            case (.write(_, _, let callback), .failure(let error)):
                callback(.failure(error))
            case (.initialize(_, _, _, let callback), .failure(let error)):
                callback(.failure(error))
            case (_, .silent):
                break
            case (_, .retry):
                assertionFailure("An NFC recovery marker reached terminal delivery")
            default:
                assertionFailure("NFC completion type did not match its request")
            }
        }

        fileprivate func ndefSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
            guard activeSession?.matches(session) == true else {
                return
            }
            markSessionActive()
        }

        fileprivate func tagSessionDidBecomeActive(_ session: NFCTagReaderSession) {
            guard activeSession?.matches(session) == true else {
                return
            }
            markSessionActive()
        }

        fileprivate func compatibilitySession(
            _ session: NFCNDEFReaderSession,
            didDetect messages: [NFCNDEFMessage]
        ) {
            guard
                activeSession?.matches(session) == true,
                lifecycle.phase == .active,
                case .read(let configuration, _)? = request
            else {
                return
            }
            guard let platformMessage = messages.first else {
                finish(
                    .failure(
                        NfcError(
                            code: .readFailed,
                            message: "Core NFC detected a tag without an NDEF message",
                            recoverable: true
                        )
                    ),
                    errorMessage: configuration.presentationMessages.unsupportedTag
                )
                return
            }
            do {
                let snapshot = try NfcPlatformCodec.compatibilitySnapshot(
                    message: platformMessage,
                    detectedMessageCount: messages.count
                )
                finishSuccess(
                    .read(snapshot),
                    alertMessage: configuration.presentationMessages.success
                )
            } catch {
                finish(
                    .failure(
                        NfcError(
                            code: .internalError,
                            message: "The NFC tag snapshot could not be created",
                            recoverable: false,
                            nativeError: NfcNativeError(error)
                        )
                    ),
                    errorMessage: configuration.presentationMessages.readFailed
                )
            }
        }

        fileprivate func tagSession(
            _ session: NFCTagReaderSession,
            didDetect tags: [NFCTag]
        ) {
            guard
                activeSession?.matches(session) == true,
                lifecycle.phase == .active,
                !tagOperationInFlight,
                case .read(let configuration, _)? = request
            else {
                return
            }
            guard tags.count == 1, let tag = tags.first else {
                session.alertMessage = configuration.presentationMessages.multipleTags
                restartPolling(session: session)
                return
            }

            tagOperationInFlight = true
            session.alertMessage = configuration.presentationMessages.reading
            session.connect(to: tag) { [weak self, weak session] error in
                guard
                    let self,
                    let session,
                    self.activeSession?.matches(session) == true,
                    self.lifecycle.phase == .active
                else {
                    return
                }
                if let error {
                    self.finish(
                        .failure(self.publicError(from: error)),
                        errorMessage: configuration.presentationMessages.tagLost
                    )
                    return
                }
                self.inspectConnectedTag(tag, session: session, configuration: configuration)
            }
        }

        private func inspectConnectedTag(
            _ tag: NFCTag,
            session: NFCTagReaderSession,
            configuration: NfcReadConfiguration
        ) {
            do {
                let context = try NfcPlatformCodec.context(for: tag)
                guard configuration.mode != .discover else {
                    finishReadSnapshot(
                        context: context,
                        observation: .notChecked(),
                        configuration: configuration
                    )
                    return
                }

                context.ndefTag.queryNDEFStatus {
                    [weak self, weak session] platformStatus, capacity, error in
                    guard let self, let session,
                        self.activeSession?.matches(session) == true,
                        self.lifecycle.phase == .active
                    else {
                        return
                    }
                    if let error {
                        self.finishReadSnapshot(
                            context: context,
                            observation: NfcPlatformNdefObservation(
                                status: .readError,
                                accessStatus: nil,
                                capacityBytes: nil,
                                writable: nil,
                                nativeType: context.nativeTechnology,
                                platformMessage: nil,
                                message: nil,
                                readError: NfcNativeError(error),
                                warning: "Core NFC could not query the tag's NDEF status."
                            ),
                            configuration: configuration
                        )
                        return
                    }
                    do {
                        let status = try NfcPlatformCodec.status(platformStatus)
                        guard status != .notSupported else {
                            self.finishReadSnapshot(
                                context: context,
                                observation: .unsupported(),
                                configuration: configuration
                            )
                            return
                        }
                        context.ndefTag.readNDEF {
                            [weak self, weak session] platformMessage, error in
                            guard let self, let session,
                                self.activeSession?.matches(session) == true,
                                self.lifecycle.phase == .active
                            else {
                                return
                            }
                            if let error, !self.isZeroLengthMessage(error) {
                                self.finishReadSnapshot(
                                    context: context,
                                    observation: NfcPlatformNdefObservation(
                                        status: .readError,
                                        accessStatus: status,
                                        capacityBytes: capacity,
                                        writable: status == .readWrite,
                                        nativeType: context.nativeTechnology,
                                        platformMessage: nil,
                                        message: nil,
                                        readError: NfcNativeError(error),
                                        warning: "Core NFC found NDEF metadata but "
                                            + "could not read its message."
                                    ),
                                    configuration: configuration
                                )
                                return
                            }
                            let (message, warning) =
                                NfcPlatformCodec.tolerantMessage(platformMessage)
                            self.finishReadSnapshot(
                                context: context,
                                observation: NfcPlatformNdefObservation(
                                    status: status,
                                    accessStatus: nil,
                                    capacityBytes: capacity,
                                    writable: status == .readWrite,
                                    nativeType: context.nativeTechnology,
                                    platformMessage: platformMessage,
                                    message: message,
                                    readError: nil,
                                    warning: warning
                                ),
                                configuration: configuration
                            )
                        }
                    } catch let error as NfcError {
                        self.finish(
                            .failure(error),
                            errorMessage: configuration.presentationMessages.unsupportedTag
                        )
                    } catch {
                        self.finish(
                            .failure(
                                NfcError(
                                    code: .internalError,
                                    message: "The NDEF status could not be converted",
                                    recoverable: false,
                                    nativeError: NfcNativeError(error)
                                )
                            ),
                            errorMessage: configuration.presentationMessages.readFailed
                        )
                    }
                }
            } catch let error as NfcError {
                finish(
                    .failure(error),
                    errorMessage: configuration.presentationMessages.unsupportedTag
                )
            } catch {
                finish(
                    .failure(
                        NfcError(
                            code: .internalError,
                            message: "The NFC tag metadata could not be converted",
                            recoverable: false,
                            nativeError: NfcNativeError(error)
                        )
                    ),
                    errorMessage: configuration.presentationMessages.readFailed
                )
            }
        }

        private func finishReadSnapshot(
            context: NfcPlatformTagContext,
            observation: NfcPlatformNdefObservation,
            configuration: NfcReadConfiguration
        ) {
            do {
                finishSuccess(
                    .read(
                        try NfcPlatformCodec.snapshot(
                            context: context,
                            observation: observation
                        )
                    ),
                    alertMessage: configuration.presentationMessages.success
                )
            } catch {
                finish(
                    .failure(
                        NfcError(
                            code: .internalError,
                            message: "The NFC tag snapshot could not be created",
                            recoverable: false,
                            nativeError: NfcNativeError(error)
                        )
                    ),
                    errorMessage: configuration.presentationMessages.readFailed
                )
            }
        }

        fileprivate func writableSession(
            _ session: NFCNDEFReaderSession,
            didDetect tags: [NFCNDEFTag]
        ) {
            guard
                activeSession?.matches(session) == true,
                lifecycle.phase == .active,
                !tagOperationInFlight,
                let request
            else {
                return
            }
            let configuration: NfcWriteConfiguration
            switch request {
            case .write(_, let value, _), .initialize(_, _, let value, _):
                configuration = value
            case .read:
                return
            }
            guard tags.count == 1, let tag = tags.first else {
                session.alertMessage = configuration.presentationMessages.multipleTags
                restartPolling(session: session)
                return
            }

            tagOperationInFlight = true
            session.alertMessage = configuration.presentationMessages.checking
            session.connect(to: tag) { [weak self, weak session] error in
                guard
                    let self,
                    let session,
                    self.activeSession?.matches(session) == true,
                    self.lifecycle.phase == .active
                else {
                    return
                }
                if let error {
                    self.finish(
                        .failure(self.publicError(from: error)),
                        errorMessage: configuration.presentationMessages.tagLost
                    )
                    return
                }
                tag.queryNDEFStatus { [weak self, weak session] platformStatus, capacity, error in
                    guard
                        let self,
                        let session,
                        self.activeSession?.matches(session) == true,
                        self.lifecycle.phase == .active
                    else {
                        return
                    }
                    if let error {
                        self.finish(
                            .failure(self.publicError(from: error)),
                            errorMessage: configuration.presentationMessages.writeFailed
                        )
                        return
                    }
                    do {
                        let status = try NfcPlatformCodec.status(platformStatus)
                        guard status != .notSupported else {
                            throw NfcError(
                                code: .unsupportedTag,
                                message: "The detected tag is not formatted for NDEF",
                                recoverable: true
                            )
                        }
                        self.prepareWrite(
                            request: request,
                            tag: tag,
                            session: session,
                            status: status,
                            capacity: capacity,
                            configuration: configuration
                        )
                    } catch let error as NfcError {
                        self.finish(
                            .failure(error),
                            errorMessage: configuration.presentationMessages.unsupportedTag
                        )
                    } catch {
                        self.finish(
                            .failure(
                                NfcError(
                                    code: .internalError,
                                    message: "The NDEF status could not be converted",
                                    recoverable: false,
                                    nativeError: NfcNativeError(error)
                                )
                            )
                        )
                    }
                }
            }
        }

        private func prepareWrite(
            request: NfcClientRequest,
            tag: NFCNDEFTag,
            session: NFCNDEFReaderSession,
            status: NfcNdefStatus,
            capacity: Int,
            configuration: NfcWriteConfiguration
        ) {
            switch request {
            case .write(let message, _, _):
                writeAndVerify(
                    message: message,
                    marker: nil,
                    tag: tag,
                    session: session,
                    status: status,
                    capacity: capacity,
                    configuration: configuration
                )
            case .initialize(let message, let marker, _, _):
                tag.readNDEF { [weak self, weak session] platformMessage, error in
                    guard
                        let self,
                        let session,
                        self.activeSession?.matches(session) == true,
                        self.lifecycle.phase == .active
                    else {
                        return
                    }
                    if let error, !self.isZeroLengthMessage(error) {
                        self.finish(
                            .failure(
                                NfcError(
                                    code: .readFailed,
                                    message: "Core NFC could not read the existing "
                                        + "NDEF message before initialization",
                                    recoverable: true,
                                    nativeError: NfcNativeError(error)
                                )
                            ),
                            errorMessage: configuration.presentationMessages.writeFailed
                        )
                        return
                    }
                    do {
                        if NfcPlatformCodec.containsMarker(marker, in: platformMessage),
                            let platformMessage
                        {
                            let snapshot = try NfcPlatformCodec.compatibilitySnapshot(
                                message: platformMessage,
                                detectedMessageCount: 1,
                                status: status,
                                writable: status == .readWrite,
                                capacityBytes: capacity
                            )
                            self.finishSuccess(
                                .initialize(
                                    NfcInitializationResult.preserved(
                                        marker: marker,
                                        tag: snapshot
                                    )
                                ),
                                alertMessage: configuration.presentationMessages.success
                            )
                            return
                        }
                        self.writeAndVerify(
                            message: message,
                            marker: marker,
                            tag: tag,
                            session: session,
                            status: status,
                            capacity: capacity,
                            configuration: configuration
                        )
                    } catch {
                        self.finish(
                            .failure(
                                NfcError(
                                    code: .readFailed,
                                    message: "The existing NDEF message could not be inspected",
                                    recoverable: true,
                                    nativeError: NfcNativeError(error)
                                )
                            ),
                            errorMessage: configuration.presentationMessages.writeFailed
                        )
                    }
                }
            case .read:
                break
            }
        }

        private func writeAndVerify(
            message: NdefMessage,
            marker: NdefExternalType?,
            tag: NFCNDEFTag,
            session: NFCNDEFReaderSession,
            status: NfcNdefStatus,
            capacity: Int,
            configuration: NfcWriteConfiguration
        ) {
            do {
                try NdefWritePolicy.validateWritable(
                    status: status,
                    capacityBytes: capacity,
                    message: message
                )
            } catch let error as NfcError {
                let message: String
                switch error.code {
                case .tagReadOnly:
                    message = configuration.presentationMessages.tagReadOnly
                case .ndefCapacityExceeded:
                    message = configuration.presentationMessages.capacityExceeded
                default:
                    message = configuration.presentationMessages.writeFailed
                }
                finish(.failure(error), errorMessage: message)
                return
            } catch {
                finish(
                    .failure(
                        NfcError(
                            code: .internalError,
                            message: "The NDEF write policy could not be evaluated",
                            recoverable: false,
                            nativeError: NfcNativeError(error)
                        )
                    )
                )
                return
            }

            session.alertMessage = configuration.presentationMessages.writing
            writeCommandStarted = true
            tag.writeNDEF(NfcPlatformCodec.toPlatform(message)) { [weak self, weak session] error in
                guard
                    let self,
                    let session,
                    self.activeSession?.matches(session) == true,
                    self.lifecycle.phase == .active
                else {
                    return
                }
                if let error {
                    let mapped = self.publicError(from: error, defaultCode: .writeFailed)
                    self.finish(
                        .failure(
                            NfcError(
                                code: mapped.code,
                                message: self.uncertainWriteMessage(mapped.message),
                                recoverable: mapped.recoverable,
                                nativeError: mapped.nativeError
                            )
                        ),
                        errorMessage: configuration.presentationMessages.writeFailed
                    )
                    return
                }

                session.alertMessage = configuration.presentationMessages.verifying
                tag.readNDEF { [weak self, weak session] platformMessage, error in
                    guard
                        let self,
                        let session,
                        self.activeSession?.matches(session) == true,
                        self.lifecycle.phase == .active
                    else {
                        return
                    }
                    if let error {
                        self.finish(
                            .failure(
                                NfcError(
                                    code: .writeVerificationFailed,
                                    message: self.uncertainWriteMessage(
                                        "The tag was written but could not be read back for verification"
                                    ),
                                    recoverable: true,
                                    nativeError: NfcNativeError(error)
                                )
                            ),
                            errorMessage: configuration.presentationMessages.verificationFailed
                        )
                        return
                    }
                    do {
                        let verifiedMessage = try NfcPlatformCodec.fromPlatform(platformMessage)
                        try NdefWritePolicy.verify(
                            expected: message,
                            actual: verifiedMessage
                        )
                        guard verifiedMessage != nil else {
                            throw NfcError(
                                code: .writeVerificationFailed,
                                message: "The tag returned no NDEF message during verification",
                                recoverable: true
                            )
                        }
                        guard let platformMessage else {
                            throw NfcError(
                                code: .writeVerificationFailed,
                                message: "The tag returned no raw NDEF message during verification",
                                recoverable: true
                            )
                        }
                        self.writeVerified = true
                        let snapshot = try NfcPlatformCodec.compatibilitySnapshot(
                            message: platformMessage,
                            detectedMessageCount: 1,
                            status: .readWrite,
                            writable: true,
                            capacityBytes: capacity
                        )
                        if let marker {
                            self.finishSuccess(
                                .initialize(
                                    NfcInitializationResult.initialized(
                                        marker: marker,
                                        tag: snapshot,
                                        message: message
                                    )
                                ),
                                alertMessage: configuration.presentationMessages.success
                            )
                        } else {
                            self.finishSuccess(
                                .write(NfcWriteResult(tag: snapshot, message: message)),
                                alertMessage: configuration.presentationMessages.success
                            )
                        }
                    } catch let error as NfcError {
                        self.finish(
                            .failure(
                                NfcError(
                                    code: error.code,
                                    message: self.uncertainWriteMessage(error.message),
                                    recoverable: error.recoverable,
                                    nativeError: error.nativeError
                                )
                            ),
                            errorMessage: configuration.presentationMessages.verificationFailed
                        )
                    } catch {
                        self.finish(
                            .failure(
                                NfcError(
                                    code: .writeVerificationFailed,
                                    message: self.uncertainWriteMessage(
                                        "The written NDEF message could not be converted for verification"
                                    ),
                                    recoverable: true,
                                    nativeError: NfcNativeError(error)
                                )
                            ),
                            errorMessage: configuration.presentationMessages.verificationFailed
                        )
                    }
                }
            }
        }

        fileprivate func ndefSession(
            _ session: NFCNDEFReaderSession,
            didInvalidateWith error: Error
        ) {
            guard activeSession?.matches(session) == true else {
                return
            }
            completeInvalidatedSession(error: error)
        }

        fileprivate func tagSession(
            _ session: NFCTagReaderSession,
            didInvalidateWith error: Error
        ) {
            guard activeSession?.matches(session) == true else {
                return
            }
            completeInvalidatedSession(error: error)
        }

        private func restartPolling(session: NFCNDEFReaderSession) {
            guard let identifier = operationIdentifier else {
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
                [weak self, weak session] in
                guard
                    let self,
                    let session,
                    self.operationIdentifier == identifier,
                    self.activeSession?.matches(session) == true,
                    !self.tagOperationInFlight
                else {
                    return
                }
                session.restartPolling()
            }
        }

        private func restartPolling(session: NFCTagReaderSession) {
            guard let identifier = operationIdentifier else {
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
                [weak self, weak session] in
                guard
                    let self,
                    let session,
                    self.operationIdentifier == identifier,
                    self.activeSession?.matches(session) == true,
                    !self.tagOperationInFlight
                else {
                    return
                }
                session.restartPolling()
            }
        }

        private func pollingOptions(
            _ technologies: Set<NfcPollingTechnology>
        ) -> NFCTagReaderSession.PollingOption {
            var options: NFCTagReaderSession.PollingOption = []
            if technologies.contains(.iso14443) {
                options.insert(.iso14443)
            }
            if technologies.contains(.iso15693) {
                options.insert(.iso15693)
            }
            if technologies.contains(.iso18092) {
                options.insert(.iso18092)
            }
            return options
        }

        private func publicError(
            from error: Error,
            defaultCode: NfcErrorCode? = nil
        ) -> NfcError {
            NfcError.fromCoreNfc(
                error,
                domain: NFCErrorDomain,
                reading: request?.kind == .read,
                defaultCode: defaultCode
            ).acknowledgingUnverifiedWrite(
                commandStarted: request?.kind == .write && writeCommandStarted,
                verified: writeVerified
            )
        }

        private func isZeroLengthMessage(_ error: Error) -> Bool {
            let value = error as NSError
            return value.domain == NFCErrorDomain && value.code == 403
        }

        private func uncertainWriteMessage(_ message: String) -> String {
            guard request?.kind == .write, writeCommandStarted, !writeVerified else {
                return message
            }
            return NfcError.unverifiedWriteMessage(message)
        }

        private func busyError(for kind: NfcOperationKind) -> NfcError {
            NfcError(
                code: kind == .read ? .scanBusy : .writeBusy,
                message: "Another NFC read or write operation is already active",
                recoverable: true
            )
        }

        private func sessionErrorMessage(_ message: String) -> String {
            String(message.prefix(100))
        }

        private func setObservableOperationKind(_ kind: NfcOperationKind?) {
            let newState: NfcClientState
            switch kind {
            case .read: newState = .reading
            case .write: newState = .writing
            case nil: newState = .idle
            }
            observableStateLock.lock()
            let previousKind = observableOperationKind
            observableOperationKind = kind
            let handler = observableStateHandler
            observableStateLock.unlock()
            if previousKind != kind {
                handler?(newState)
            }
        }

        private func observeApplicationLifecycle() {
            let center = NotificationCenter.default
            applicationObservers.append(
                center.addObserver(
                    forName: UIApplication.willResignActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.applicationIsActive = false
                }
            )
            applicationObservers.append(
                center.addObserver(
                    forName: UIApplication.didBecomeActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    guard let self else { return }
                    self.applicationIsActive = true
                    self.resumeWaitingRequestIfPossible()
                }
            )
            applicationObservers.append(
                center.addObserver(
                    forName: UIApplication.didEnterBackgroundNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    guard let self, self.request != nil else {
                        return
                    }
                    self.applicationIsActive = false
                    let reading = self.request?.kind == .read
                    self.finish(
                        .failure(
                            NfcError(
                                code: reading ? .readFailed : .writeFailed,
                                message: reading
                                    ? "The NFC scan ended when the app left the foreground"
                                    : self.uncertainWriteMessage(
                                        "The NFC write ended when the app left the foreground"
                                    ),
                                recoverable: true
                            )
                        )
                    )
                }
            )
            applicationObservers.append(
                center.addObserver(
                    forName: UIApplication.willEnterForegroundNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.applicationIsActive = false
                }
            )
        }

        private func runOnMain(_ action: @escaping () -> Void) {
            if Thread.isMainThread {
                action()
            } else {
                DispatchQueue.main.async(execute: action)
            }
        }
    }

#else

    /// A platform stub that reports Core NFC as unavailable outside iOS.
    public final class NfcClient {
        public init() {}

        public var capabilities: NfcCapabilities { .current }
        public var state: NfcClientState { .idle }
        /// A closing failure/cancellation may complete after a five-second grace
        /// period while state remains busy until Core NFC confirms invalidation.
        public var stateChangeHandler: ((NfcClientState) -> Void)?
        public var isReading: Bool { false }
        public var isWriting: Bool { false }

        public func startRead(
            configuration _: NfcReadConfiguration = .standard,
            completion: @escaping (Result<NfcTagSnapshot, NfcError>) -> Void
        ) {
            deliverUnsupported(completion)
        }

        public func startWrite(
            message _: NdefMessage,
            configuration _: NfcWriteConfiguration = .standard,
            completion: @escaping (Result<NfcWriteResult, NfcError>) -> Void
        ) {
            deliverUnsupported(completion)
        }

        public func startInitialize(
            message: NdefMessage,
            marker: NdefExternalType,
            configuration _: NfcWriteConfiguration = .standard,
            completion: @escaping (Result<NfcInitializationResult, NfcError>) -> Void
        ) throws {
            try NdefWritePolicy.validateInitializationMessage(message, marker: marker)
            deliverUnsupported(completion)
        }

        public func cancelRead() {}
        public func cancelWrite() {}
        public func stop() {}

        private func deliverUnsupported<Success>(
            _ completion: @escaping (Result<Success, NfcError>) -> Void
        ) {
            let error = NfcError(
                code: .nfcUnsupported,
                message: "Core NFC is only available on supported iOS devices",
                recoverable: false
            )
            if Thread.isMainThread {
                completion(.failure(error))
            } else {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

#endif
