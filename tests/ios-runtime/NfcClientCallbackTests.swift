import CoreNFC
import XCTest

@testable import Sfiora

/// Executes the iOS production client, delegates and codec on the actual main queue.
@MainActor
final class NfcClientCallbackTests: XCTestCase {
    func testLateSuccessfulQueryCannotStartReadingFromAnOldSession() async throws {
        try await assertLateCallback(atRead: false, failure: false)
    }

    func testLateFailedQueryCannotFinishTheNewSession() async throws {
        try await assertLateCallback(atRead: false, failure: true)
    }

    func testLateReadMessageCannotReplaceTheNewSessionsResult() async throws {
        try await assertLateCallback(atRead: true, failure: false)
    }

    func testLateReadErrorCannotFinishTheNewSession() async throws {
        try await assertLateCallback(atRead: true, failure: true)
    }

    private func assertLateCallback(atRead: Bool, failure: Bool) async throws {
        var sessions: [SFControlledSession] = []
        var detectors: [(SFControlledTag) -> Void] = []
        var environment = NfcClientEnvironment()
        environment.capabilities = { NfcCapabilities(supported: true, enabled: true) }
        environment.applicationIsActive = { true }
        environment.makeTagSession = { _, delegate, queue in
            let session = SFControlledSession(queue: queue)
            session.onActive = { [weak delegate, weak session] in
                guard let delegate, let session else { return }
                delegate.tagReaderSessionDidBecomeActive(session)
            }
            session.onInvalidated = { [weak delegate, weak session] in
                guard let delegate, let session else { return }
                delegate.tagReaderSession(
                    session, didInvalidateWithError: NSError(domain: NFCErrorDomain, code: 200))
            }
            detectors.append { [weak delegate, weak session] tag in
                queue.async(
                    execute: DispatchWorkItem {
                        guard let delegate, let session else { return }
                        delegate.tagReaderSession(session, didDetect: [.miFare(tag)])
                    })
            }
            sessions.append(session)
            return session
        }
        let client = NfcClient(environment: environment)
        var oldResults: [Result<NfcTagSnapshot, NfcError>] = []
        var newResults: [Result<NfcTagSnapshot, NfcError>] = []
        let configuration = try NfcReadConfiguration(mode: .automatic)
        client.startRead(configuration: configuration) {
            XCTAssertTrue(Thread.isMainThread)
            oldResults.append($0)
        }
        await flushCallbacks()
        let oldSession = try XCTUnwrap(sessions.first)
        let oldTag = SFControlledTag()
        detectors[0](oldTag)
        await flushCallbacks()
        XCTAssertEqual(oldTag.queryCount, 1)
        if atRead {
            oldTag.completeQueryWithError(nil)
            await flushCallbacks()
            XCTAssertEqual(oldTag.readCount, 1)
        }
        client.cancelRead()
        XCTAssertTrue(client.isReading)
        oldSession.completeInvalidation()
        await flushCallbacks()
        XCTAssertFalse(client.isReading)
        XCTAssertEqual(oldResults.count, 1)
        if case .failure(let error) = oldResults.first {
            XCTAssertEqual(error.code, .userCancelled)
        } else {
            XCTFail("The original operation must finish as cancelled")
        }

        client.startRead(configuration: configuration) {
            XCTAssertTrue(Thread.isMainThread)
            newResults.append($0)
        }
        await flushCallbacks()
        XCTAssertEqual(sessions.count, 2)
        let newSession = try XCTUnwrap(sessions.last)
        let newTag = SFControlledTag()
        detectors[1](newTag)
        await flushCallbacks()
        XCTAssertEqual(newTag.queryCount, 1)

        // Keep the old session alive: this must exercise identity rejection,
        // rather than merely succeeding because its weak reference became nil.
        let error = failure ? NSError(domain: NFCErrorDomain, code: 100) : nil
        if atRead {
            oldTag.completeRead(withText: "old", error: error)
        } else {
            oldTag.completeQueryWithError(error)
        }
        await flushCallbacks()
        XCTAssertTrue(client.isReading)
        XCTAssertTrue(newResults.isEmpty)
        XCTAssertEqual(oldTag.readCount, atRead ? 1 : 0)
        XCTAssertEqual(newSession.invalidations, 0)
        XCTAssertEqual(oldResults.count, 1)
        guard newResults.isEmpty, newSession.invalidations == 0,
            oldTag.readCount == (atRead ? 1 : 0)
        else {
            client.stop()
            newSession.completeInvalidation()
            await flushCallbacks()
            return
        }

        newTag.completeQueryWithError(nil)
        await flushCallbacks()
        XCTAssertEqual(newTag.readCount, 1)
        newTag.completeRead(withText: "new", error: nil)
        await flushCallbacks()
        XCTAssertEqual(newResults.count, 1)
        let snapshot = try XCTUnwrap(newResults.first).get()
        XCTAssertEqual(snapshot.ndefMessage?.records.first?.decodedText?.text, "new")
        XCTAssertTrue(client.isReading)
        newSession.completeInvalidation()
        await flushCallbacks()
        XCTAssertFalse(client.isReading)
        XCTAssertEqual(newResults.count, 1)
    }

    private func flushCallbacks() async {
        for _ in 0..<4 {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }
}
