import Foundation
import XCTest

@testable import Sfiora

final class NfcCoreTests: XCTestCase {
    func testConfigurationsUseStableDefaultsAndValidateInputs() throws {
        XCTAssertEqual(NfcReadConfiguration.standard.mode, .automatic)
        XCTAssertEqual(
            NfcReadConfiguration.standard.pollingTechnologies,
            [.iso14443, .iso15693]
        )
        XCTAssertEqual(NfcWriteConfiguration.standard.timeoutMilliseconds, 30_000)
        XCTAssertEqual(
            NfcWriteConfiguration.standard.presentationMessages.checking,
            "Tag detected. Checking write conditions…"
        )

        XCTAssertThrowsError(try NfcReadConfiguration(timeoutMilliseconds: 999)) {
            XCTAssertEqual(
                $0 as? NfcConfigurationError,
                .invalidTimeout(milliseconds: 999)
            )
        }
        XCTAssertThrowsError(try NfcReadConfiguration(pollingTechnologies: [])) {
            XCTAssertEqual($0 as? NfcConfigurationError, .emptyPollingTechnologies)
        }
        XCTAssertThrowsError(try NfcWriteConfiguration(alertMessage: "  \n")) {
            XCTAssertEqual(
                $0 as? NfcConfigurationError,
                .emptyMessage(name: "alertMessage")
            )
        }
    }

    func testEveryPresentationStageIsValidated() {
        let messages = NfcReaderPresentationMessages(
            instruction: " ",
            success: "success",
            timeout: "timeout",
            multipleTags: "multiple",
            reading: "reading",
            tagLost: "lost",
            unsupportedTag: "unsupported",
            readFailed: "failed"
        )
        XCTAssertThrowsError(
            try NfcReadConfiguration(presentationMessages: messages)
        ) {
            XCTAssertEqual(
                $0 as? NfcConfigurationError,
                .emptyMessage(name: "instruction")
            )
        }
    }

    func testLifecyclePreservesFirstTerminalValueUntilInvalidation() {
        var lifecycle = NfcSessionLifecycle<String>()

        XCTAssertEqual(lifecycle.begin(applicationIsActive: true), .start)
        XCTAssertTrue(lifecycle.requestInvalidation(with: "success"))
        XCTAssertFalse(lifecycle.requestInvalidation(with: "replacement"))
        XCTAssertEqual(
            lifecycle.completeInvalidation(fallback: "native failure"),
            "success"
        )
        XCTAssertEqual(lifecycle.phase, .idle)
    }

    func testLifecycleCanWaitForForegroundOrCompleteBeforeSessionCreation() {
        var resumed = NfcSessionLifecycle<Int>()
        XCTAssertEqual(
            resumed.begin(applicationIsActive: false),
            .waitForForeground
        )
        XCTAssertTrue(resumed.resumeWaitingRequest())
        XCTAssertEqual(resumed.phase, .active)
        XCTAssertEqual(resumed.completeInvalidation(fallback: 7), 7)

        var cancelled = NfcSessionLifecycle<Int>()
        XCTAssertEqual(
            cancelled.begin(applicationIsActive: false),
            .waitForForeground
        )
        XCTAssertEqual(cancelled.completeWaitingRequest(with: 9), 9)
        XCTAssertEqual(cancelled.phase, .idle)
    }

    func testCoordinatorLeaseCannotBeStolenOrReleasedByAStaleLease() {
        let read = NfcOperationCoordinator.acquire(.read)
        XCTAssertNotNil(read)
        XCTAssertNil(NfcOperationCoordinator.acquire(.write))

        NfcOperationCoordinator.release(read)
        let write = NfcOperationCoordinator.acquire(.write)
        XCTAssertNotNil(write)
        NfcOperationCoordinator.release(read)
        XCTAssertNil(NfcOperationCoordinator.acquire(.read))
        NfcOperationCoordinator.release(write)
    }

    func testExternalTypeAndInitializationPolicyRequireOneExactMarker() throws {
        let marker = try NdefExternalType(domain: "example.org", type: "sample")
        let matching = try NdefRecord.external(
            domain: marker.domain,
            type: marker.type,
            payload: Data([0x01])
        )
        let text = try NdefRecord.text("value", languageCode: "en")

        XCTAssertTrue(marker.matches(matching))
        XCTAssertThrowsError(
            try NdefExternalType(domain: "Example.org", type: "sample")
        )
        XCTAssertNoThrow(
            try NdefWritePolicy.validateInitializationMessage(
                NdefMessage(records: [matching, text]),
                marker: marker
            )
        )
        XCTAssertThrowsError(
            try NdefWritePolicy.validateInitializationMessage(
                NdefMessage(records: [text]),
                marker: marker
            )
        )
        XCTAssertThrowsError(
            try NdefWritePolicy.validateInitializationMessage(
                NdefMessage(records: [matching, matching]),
                marker: marker
            )
        )
    }

    func testWritePolicyDistinguishesValidationAndVerificationFailures() throws {
        let message = try NdefMessage(records: [
            NdefRecord.uri("https://example.org")
        ])
        XCTAssertThrowsError(
            try NdefWritePolicy.validateWritable(
                status: .readOnly,
                capacityBytes: 512,
                message: message
            )
        ) {
            XCTAssertEqual(($0 as? NfcError)?.code, .tagReadOnly)
        }
        XCTAssertThrowsError(
            try NdefWritePolicy.validateWritable(
                status: .readWrite,
                capacityBytes: message.byteCount - 1,
                message: message
            )
        ) {
            XCTAssertEqual(($0 as? NfcError)?.code, .ndefCapacityExceeded)
        }
        XCTAssertNoThrow(
            try NdefWritePolicy.verify(expected: message, actual: message)
        )
        XCTAssertThrowsError(
            try NdefWritePolicy.verify(expected: message, actual: nil)
        ) {
            XCTAssertEqual(($0 as? NfcError)?.code, .writeVerificationFailed)
        }
    }

    func testSnapshotNormalizesTechnologiesAndResultsRemainDistinct() throws {
        let message = try NdefMessage(records: [
            NdefRecord.text("value", languageCode: "en")
        ])
        let snapshot = try NfcTagSnapshot(
            identifier: Data([0x01, 0x02]),
            technologies: [.nfcA, .ndef, .nfcA],
            ndefStatus: .readWrite,
            ndefCapacityBytes: 512,
            ndefMessage: message,
            discoveredAtEpochMilliseconds: 10
        )
        XCTAssertEqual(snapshot.technologies, [.nfcA, .ndef])

        let marker = try NdefExternalType(domain: "example.org", type: "sample")
        let preserved = NfcInitializationResult.preserved(
            marker: marker,
            tag: snapshot
        )
        let initialized = NfcInitializationResult.initialized(
            marker: marker,
            tag: snapshot,
            message: message
        )
        XCTAssertEqual(preserved.action, .preserved)
        XCTAssertFalse(preserved.verified)
        XCTAssertNil(preserved.writtenMessage)
        XCTAssertEqual(initialized.action, .initialized)
        XCTAssertTrue(initialized.verified)
        XCTAssertEqual(initialized.writtenMessage, message)
        XCTAssertEqual(initialized.recordCount, 1)

        XCTAssertEqual(
            preserved.dictionary["operation"] as? String,
            "initializeNdef"
        )
        XCTAssertNil(preserved.dictionary["verified"])
        XCTAssertEqual(
            initialized.dictionary["messageHex"] as? String,
            NfcTagSnapshot.hex(message.serializedData)
        )
        XCTAssertEqual(
            (initialized.dictionary["marker"] as? [String: Any])?["externalType"]
                as? String,
            "example.org:sample"
        )
        XCTAssertTrue(
            try initialized.jsonString(prettyPrinted: true)
                .contains("\"operation\" : \"initializeNdef\"")
        )

        let write = NfcWriteResult(
            tag: snapshot,
            message: message,
            completedAtEpochMilliseconds: 11
        )
        XCTAssertTrue(write.verified)
        XCTAssertEqual(write.recordCount, 1)
        XCTAssertEqual(write.dictionary["completedAtEpochMs"] as? Int64, 11)
        XCTAssertEqual(
            write.dictionary["messageBase64"] as? String,
            message.serializedData.base64EncodedString()
        )
        XCTAssertTrue(
            try write.jsonString().contains("\"operation\":\"writeNdef\"")
        )
    }

    func testSnapshotAndErrorKeepBridgeValuesIndependent() throws {
        let snapshot = try NfcTagSnapshot(
            identifier: Data([0x01]),
            technologies: [.nfcA, .ndef],
            nativeTechnologies: ["CoreNFC.Test"],
            ndefStatus: .readError,
            ndefAccessStatus: .readOnly,
            ndefCapacityBytes: 128,
            ndefWritable: false,
            ndefMessage: nil,
            warnings: ["warning"],
            discoveredAtEpochMilliseconds: 10
        )
        var copy = snapshot.dictionary
        copy["platform"] = "changed"
        let json = try snapshot.jsonString(prettyPrinted: true)

        XCTAssertTrue(json.contains("\"platform\" : \"ios\""))
        XCTAssertFalse(json.contains("changed"))
        XCTAssertEqual(
            (snapshot.dictionary["ndef"] as? [String: Any])?["status"] as? String,
            "readError"
        )

        let error = NfcError(
            code: .invalidOptions,
            message: "Invalid options",
            recoverable: false,
            nativeError: NfcNativeError(
                type: "TestError",
                domain: "test",
                code: 7,
                message: "native"
            )
        )
        XCTAssertEqual(error.dictionary["code"] as? String, "INVALID_OPTIONS")
        XCTAssertEqual(
            (error.dictionary["nativeError"] as? [String: Any])?["code"] as? Int,
            7
        )
    }

    func testCapabilitiesExposeTypedAndBridgeFeatureContracts() {
        let capabilities = NfcCapabilities(
            supported: true,
            enabled: true,
            features: [.ndef, .ndefInitialize]
        )

        XCTAssertEqual(capabilities.features, [.ndef, .ndefInitialize])
        XCTAssertEqual(capabilities.dictionary["platform"] as? String, "ios")
        XCTAssertEqual(
            capabilities.dictionary["readerModeSupported"] as? Bool,
            true
        )
    }
}
