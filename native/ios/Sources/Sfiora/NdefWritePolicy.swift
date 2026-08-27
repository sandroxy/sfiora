import Foundation

enum NdefWritePolicy {
    static func validateInitializationMessage(
        _ message: NdefMessage,
        marker: NdefExternalType
    ) throws {
        guard message.records.filter(marker.matches).count == 1 else {
            throw NdefWritePolicyError.invalidInitializationMessage
        }
    }

    static func validateWritable(
        status: NfcNdefStatus,
        capacityBytes: Int,
        message: NdefMessage
    ) throws {
        guard status == .readWrite else {
            throw NfcError(
                code: .tagReadOnly,
                message: "The detected NDEF tag is read-only",
                recoverable: false
            )
        }
        guard message.byteCount <= capacityBytes else {
            throw NfcError(
                code: .ndefCapacityExceeded,
                message:
                    "The NDEF message requires \(message.byteCount) bytes "
                    + "but the tag capacity is \(capacityBytes) bytes",
                recoverable: false
            )
        }
    }

    static func verify(expected: NdefMessage, actual: NdefMessage?) throws {
        guard actual?.serializedData == expected.serializedData else {
            throw NfcError(
                code: .writeVerificationFailed,
                message: "The NDEF message read from the tag differs from the message written",
                recoverable: true
            )
        }
    }
}

enum NdefWritePolicyError: Error, Equatable, LocalizedError {
    case invalidInitializationMessage

    var errorDescription: String? {
        "The initialization message must contain exactly one record matching "
            + "the external type marker"
    }
}
