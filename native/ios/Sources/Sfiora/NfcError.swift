import Foundation

/// Stable failure codes shared by the native implementations.
public enum NfcErrorCode: String, Equatable, Sendable {
    case nfcUnsupported = "NFC_UNSUPPORTED"
    case nfcDisabled = "NFC_DISABLED"
    case scanBusy = "SCAN_BUSY"
    case writeBusy = "WRITE_BUSY"
    case userCancelled = "USER_CANCELLED"
    case scanTimeout = "SCAN_TIMEOUT"
    case writeTimeout = "WRITE_TIMEOUT"
    case sessionCloseTimeout = "SESSION_CLOSE_TIMEOUT"
    case tagLost = "TAG_LOST"
    case unsupportedTag = "UNSUPPORTED_TAG"
    case readFailed = "READ_FAILED"
    case tagReadOnly = "TAG_READ_ONLY"
    case ndefCapacityExceeded = "NDEF_CAPACITY_EXCEEDED"
    case writeFailed = "WRITE_FAILED"
    case writeVerificationFailed = "WRITE_VERIFICATION_FAILED"
    case invalidOptions = "INVALID_OPTIONS"
    case internalError = "INTERNAL_ERROR"
}

/// A value copy of an error returned by the native NFC framework.
public struct NfcNativeError: Equatable, Sendable {
    public let type: String
    public let domain: String
    public let code: Int
    public let message: String

    public init(type: String, domain: String, code: Int, message: String) {
        self.type = type
        self.domain = domain
        self.code = code
        self.message = message
    }

    public init(_ error: Error) {
        let value = error as NSError
        type = String(reflecting: Swift.type(of: error))
        domain = value.domain
        code = value.code
        message = value.localizedDescription
    }

    public var dictionary: [String: Any] {
        [
            "type": type,
            "domain": domain,
            "code": code,
            "message": message,
        ]
    }
}

/// An immutable NFC operation failure suitable for bridge conversion.
public struct NfcError: Error, Equatable, LocalizedError, Sendable {
    public let code: NfcErrorCode
    public let message: String
    public let recoverable: Bool
    public let nativeError: NfcNativeError?

    public init(
        code: NfcErrorCode,
        message: String,
        recoverable: Bool,
        nativeError: NfcNativeError? = nil
    ) {
        self.code = code
        self.message = message
        self.recoverable = recoverable
        self.nativeError = nativeError
    }

    public var errorDescription: String? {
        message
    }

    public var dictionary: [String: Any] {
        var value: [String: Any] = [
            "code": code.rawValue,
            "message": message,
            "recoverable": recoverable,
        ]
        if let nativeError {
            value["nativeError"] = nativeError.dictionary
        }
        return value
    }
}

extension NfcError {
    static func unverifiedWriteMessage(_ message: String) -> String {
        let warning = "the tag may have changed because the write was not verified"
        return message.contains(warning) ? message : message + "; " + warning
    }

    /// Preserve the error identity while acknowledging that a failed write is
    /// not evidence that the tag still contains its original data.
    func acknowledgingUnverifiedWrite(commandStarted: Bool, verified: Bool) -> NfcError {
        guard commandStarted, !verified else {
            return self
        }
        return NfcError(
            code: code,
            message: Self.unverifiedWriteMessage(message),
            recoverable: recoverable,
            nativeError: nativeError
        )
    }
}

extension NfcError {
    static func fromCoreNfc(
        _ error: Error,
        domain: String,
        reading: Bool,
        defaultCode: NfcErrorCode? = nil
    ) -> NfcError {
        if let error = error as? NfcError {
            return error
        }
        let native = NfcNativeError(error)
        let value = error as NSError
        let fallbackCode = defaultCode ?? (reading ? .readFailed : .writeFailed)

        guard value.domain == domain else {
            return NfcError(
                code: fallbackCode,
                message: reading
                    ? "The NFC tag could not be read"
                    : "The NFC tag could not be written",
                recoverable: true,
                nativeError: native
            )
        }

        switch value.code {
        case 1:
            return NfcError(
                code: .nfcUnsupported,
                message: "This device does not support the requested Core NFC operation",
                recoverable: false,
                nativeError: native
            )
        case 6:
            return NfcError(
                code: .nfcDisabled,
                message: "NFC is unavailable in the current system state",
                recoverable: true,
                nativeError: native
            )
        case 2:
            return NfcError(
                code: .internalError,
                message: "The app is missing required NFC permissions or tag configuration",
                recoverable: false,
                nativeError: native
            )
        case 100, 104:
            return NfcError(
                code: .tagLost,
                message: "The NFC tag left the reader field",
                recoverable: true,
                nativeError: native
            )
        case 200:
            return NfcError(
                code: .userCancelled,
                message: reading ? "The NFC scan was cancelled" : "The NFC write was cancelled",
                recoverable: true,
                nativeError: native
            )
        case 201:
            return NfcError(
                code: reading ? .scanTimeout : .writeTimeout,
                message: reading
                    ? "The NFC scan timed out"
                    : "The NFC write timed out",
                recoverable: true,
                nativeError: native
            )
        case 203:
            return NfcError(
                code: reading ? .scanBusy : .writeBusy,
                message: "Another NFC session is already active",
                recoverable: true,
                nativeError: native
            )
        case 400:
            return NfcError(
                code: .tagReadOnly,
                message: "The detected NDEF tag is read-only",
                recoverable: false,
                nativeError: native
            )
        case 402:
            return NfcError(
                code: .ndefCapacityExceeded,
                message: "The NDEF message is larger than the tag capacity",
                recoverable: false,
                nativeError: native
            )
        default:
            return NfcError(
                code: fallbackCode,
                message: reading
                    ? "The NFC tag could not be read"
                    : "The NFC tag could not be written",
                recoverable: true,
                nativeError: native
            )
        }
    }
}
