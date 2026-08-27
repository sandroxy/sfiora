import Foundation

/// Determines how one foreground tag scan handles NDEF data.
public enum NfcReadMode: String, Equatable, Sendable {
    /// Returns tag identity and reads NDEF when the tag exposes it.
    case automatic

    /// Uses the system NDEF compatibility reader and requires an NDEF message.
    case ndef

    /// Returns tag identity without querying NDEF.
    case discover
}

/// Protocol families supported by an iOS tag reader session.
public enum NfcPollingTechnology: String, Hashable, Sendable {
    case iso14443
    case iso15693
    case iso18092
}

public enum NfcConfigurationError: Error, Equatable, LocalizedError, Sendable {
    case invalidTimeout(milliseconds: Int)
    case emptyPollingTechnologies
    case emptyMessage(name: String)

    public var errorDescription: String? {
        switch self {
        case .invalidTimeout(let milliseconds):
            return "timeoutMilliseconds \(milliseconds) is outside the supported range"
        case .emptyPollingTechnologies:
            return "At least one NFC polling technology is required"
        case .emptyMessage(let name):
            return "\(name) must not be empty"
        }
    }
}

/// Immutable settings for one iOS foreground NFC scan.
public struct NfcReadConfiguration: Equatable, Sendable {
    public static let minimumTimeoutMilliseconds = 1_000
    public static let maximumTimeoutMilliseconds = 60_000

    public let mode: NfcReadMode
    public let timeoutMilliseconds: Int
    public let pollingTechnologies: Set<NfcPollingTechnology>
    public let presentationMessages: NfcReaderPresentationMessages

    public var alertMessage: String { presentationMessages.instruction }
    public var successMessage: String { presentationMessages.success }
    public var multipleTagsMessage: String { presentationMessages.multipleTags }

    public static let standard = NfcReadConfiguration(
        validatedMode: .automatic,
        timeoutMilliseconds: 30_000,
        pollingTechnologies: [.iso14443, .iso15693],
        presentationMessages: .standard
    )

    public init(
        mode: NfcReadMode = .automatic,
        timeoutMilliseconds: Int = 30_000,
        pollingTechnologies: Set<NfcPollingTechnology> = [.iso14443, .iso15693],
        alertMessage: String = "Hold your iPhone near an NFC tag.",
        successMessage: String = "NFC tag read successfully.",
        multipleTagsMessage: String =
            "More than one tag was detected. Present only one tag."
    ) throws {
        try Self.validateTimeout(timeoutMilliseconds)
        guard !pollingTechnologies.isEmpty else {
            throw NfcConfigurationError.emptyPollingTechnologies
        }
        try Self.validateMessage(alertMessage, name: "alertMessage")
        try Self.validateMessage(successMessage, name: "successMessage")
        try Self.validateMessage(
            multipleTagsMessage,
            name: "multipleTagsMessage"
        )
        let messages = NfcReaderPresentationMessages(
            instruction: alertMessage,
            success: successMessage,
            timeout: NfcReaderPresentationMessages.standard.timeout,
            multipleTags: multipleTagsMessage,
            reading: NfcReaderPresentationMessages.standard.reading,
            tagLost: NfcReaderPresentationMessages.standard.tagLost,
            unsupportedTag: NfcReaderPresentationMessages.standard.unsupportedTag,
            readFailed: NfcReaderPresentationMessages.standard.readFailed
        )

        self.mode = mode
        self.timeoutMilliseconds = timeoutMilliseconds
        self.pollingTechnologies = pollingTechnologies
        presentationMessages = messages
    }

    public init(
        mode: NfcReadMode = .automatic,
        timeoutMilliseconds: Int = 30_000,
        pollingTechnologies: Set<NfcPollingTechnology> = [.iso14443, .iso15693],
        presentationMessages: NfcReaderPresentationMessages
    ) throws {
        try Self.validateTimeout(timeoutMilliseconds)
        guard !pollingTechnologies.isEmpty else {
            throw NfcConfigurationError.emptyPollingTechnologies
        }
        try Self.validate(presentationMessages)
        self.mode = mode
        self.timeoutMilliseconds = timeoutMilliseconds
        self.pollingTechnologies = pollingTechnologies
        self.presentationMessages = presentationMessages
    }

    private init(
        validatedMode: NfcReadMode,
        timeoutMilliseconds: Int,
        pollingTechnologies: Set<NfcPollingTechnology>,
        presentationMessages: NfcReaderPresentationMessages
    ) {
        mode = validatedMode
        self.timeoutMilliseconds = timeoutMilliseconds
        self.pollingTechnologies = pollingTechnologies
        self.presentationMessages = presentationMessages
    }

    static func validateTimeout(_ milliseconds: Int) throws {
        guard minimumTimeoutMilliseconds...maximumTimeoutMilliseconds ~= milliseconds else {
            throw NfcConfigurationError.invalidTimeout(milliseconds: milliseconds)
        }
    }

    static func validateMessage(_ message: String, name: String) throws {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NfcConfigurationError.emptyMessage(name: name)
        }
    }

    private static func validate(
        _ messages: NfcReaderPresentationMessages
    ) throws {
        if let field = messages.firstEmptyField {
            throw NfcConfigurationError.emptyMessage(name: field)
        }
    }
}

/// Immutable settings for one iOS foreground NDEF write.
public struct NfcWriteConfiguration: Equatable, Sendable {
    public let timeoutMilliseconds: Int
    public let presentationMessages: NfcWriterPresentationMessages

    public var alertMessage: String { presentationMessages.instruction }
    public var successMessage: String { presentationMessages.success }
    public var multipleTagsMessage: String { presentationMessages.multipleTags }

    public static let standard = NfcWriteConfiguration(
        validatedTimeoutMilliseconds: 30_000,
        presentationMessages: .standard
    )

    public init(
        timeoutMilliseconds: Int = 30_000,
        alertMessage: String = "Hold your iPhone near the NFC tag to write.",
        successMessage: String = "NFC tag written and verified.",
        multipleTagsMessage: String =
            "More than one tag was detected. Present only one tag."
    ) throws {
        try NfcReadConfiguration.validateTimeout(timeoutMilliseconds)
        try NfcReadConfiguration.validateMessage(
            alertMessage,
            name: "alertMessage"
        )
        try NfcReadConfiguration.validateMessage(
            successMessage,
            name: "successMessage"
        )
        try NfcReadConfiguration.validateMessage(
            multipleTagsMessage,
            name: "multipleTagsMessage"
        )
        let messages = NfcWriterPresentationMessages(
            instruction: alertMessage,
            success: successMessage,
            timeout: NfcWriterPresentationMessages.standard.timeout,
            multipleTags: multipleTagsMessage,
            checking: NfcWriterPresentationMessages.standard.checking,
            writing: NfcWriterPresentationMessages.standard.writing,
            verifying: NfcWriterPresentationMessages.standard.verifying,
            tagLost: NfcWriterPresentationMessages.standard.tagLost,
            tagReadOnly: NfcWriterPresentationMessages.standard.tagReadOnly,
            capacityExceeded: NfcWriterPresentationMessages.standard.capacityExceeded,
            unsupportedTag: NfcWriterPresentationMessages.standard.unsupportedTag,
            writeFailed: NfcWriterPresentationMessages.standard.writeFailed,
            verificationFailed: NfcWriterPresentationMessages.standard.verificationFailed
        )

        self.timeoutMilliseconds = timeoutMilliseconds
        presentationMessages = messages
    }

    public init(
        timeoutMilliseconds: Int = 30_000,
        presentationMessages: NfcWriterPresentationMessages
    ) throws {
        try NfcReadConfiguration.validateTimeout(timeoutMilliseconds)
        try Self.validate(presentationMessages)
        self.timeoutMilliseconds = timeoutMilliseconds
        self.presentationMessages = presentationMessages
    }

    private init(
        validatedTimeoutMilliseconds: Int,
        presentationMessages: NfcWriterPresentationMessages
    ) {
        timeoutMilliseconds = validatedTimeoutMilliseconds
        self.presentationMessages = presentationMessages
    }

    private static func validate(
        _ messages: NfcWriterPresentationMessages
    ) throws {
        if let field = messages.firstEmptyField {
            throw NfcConfigurationError.emptyMessage(name: field)
        }
    }
}
