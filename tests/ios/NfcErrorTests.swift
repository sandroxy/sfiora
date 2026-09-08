import Foundation
import XCTest

@testable import Sfiora

final class NfcErrorTests: XCTestCase {
    func testUnverifiedWriteRetainsFailureAndWarnsExactlyOnce() {
        let native = NfcNativeError(
            type: "NSError", domain: "NFC", code: 200, message: "Cancelled"
        )
        let failure = NfcError(
            code: .userCancelled, message: "Cancelled", recoverable: true, nativeError: native
        )
        XCTAssertEqual(
            failure.acknowledgingUnverifiedWrite(commandStarted: false, verified: false), failure
        )
        XCTAssertEqual(
            failure.acknowledgingUnverifiedWrite(commandStarted: true, verified: true), failure
        )
        let uncertain = failure.acknowledgingUnverifiedWrite(commandStarted: true, verified: false)
        XCTAssertEqual(uncertain.code, .userCancelled)
        XCTAssertEqual(uncertain.nativeError, native)
        XCTAssertTrue(uncertain.recoverable)
        XCTAssertEqual(
            uncertain.message,
            "Cancelled; the tag may have changed because the write was not verified"
        )
        XCTAssertEqual(
            uncertain.acknowledgingUnverifiedWrite(commandStarted: true, verified: false), uncertain
        )
    }

    func testCoreNfcFailuresPreserveContractCategories() {
        let domain = "NFCError"
        let cases: [(Int, NfcErrorCode, NfcErrorCode, Bool)] = [
            (1, .nfcUnsupported, .nfcUnsupported, false),
            (2, .internalError, .internalError, false),
            (6, .nfcDisabled, .nfcDisabled, true),
            (100, .tagLost, .tagLost, true),
            (101, .readFailed, .writeFailed, true),
            (103, .readFailed, .writeFailed, true),
            (104, .tagLost, .tagLost, true),
            (200, .userCancelled, .userCancelled, true),
            (201, .scanTimeout, .writeTimeout, true),
            (203, .scanBusy, .writeBusy, true),
            (400, .tagReadOnly, .tagReadOnly, false),
            (402, .ndefCapacityExceeded, .ndefCapacityExceeded, false),
        ]
        for (code, readCode, writeCode, recoverable) in cases {
            for reading in [true, false] {
                let failure = NfcError.fromCoreNfc(
                    NSError(domain: domain, code: code), domain: domain, reading: reading
                )
                XCTAssertEqual(failure.code, reading ? readCode : writeCode, "native code \(code)")
                XCTAssertEqual(failure.recoverable, recoverable)
                XCTAssertEqual(failure.nativeError?.code, code)
            }
        }
        let unrelated = NfcError.fromCoreNfc(
            NSError(domain: "Other", code: 200), domain: domain, reading: false,
            defaultCode: .writeVerificationFailed
        )
        XCTAssertEqual(unrelated.code, .writeVerificationFailed)
        XCTAssertTrue(
            unrelated.acknowledgingUnverifiedWrite(commandStarted: true, verified: false)
                .message.contains("the tag may have changed")
        )
    }
}
