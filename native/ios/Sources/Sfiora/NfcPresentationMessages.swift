import Foundation

/// Text displayed during one Core NFC read session.
public struct NfcReaderPresentationMessages: Equatable, Sendable {
    public let instruction: String
    public let success: String
    public let timeout: String
    public let multipleTags: String
    public let reading: String
    public let tagLost: String
    public let unsupportedTag: String
    public let readFailed: String

    public static let standard = NfcReaderPresentationMessages(
        instruction: "Hold your iPhone near an NFC tag.",
        success: "NFC tag read successfully.",
        timeout: "The NFC scan timed out. Try again.",
        multipleTags: "More than one tag was detected. Present only one tag.",
        reading: "Tag detected. Reading…",
        tagLost: "The NFC tag moved out of range. Try again.",
        unsupportedTag: "This tag does not expose supported NDEF data.",
        readFailed: "The NFC tag could not be read. Try again."
    )

    public init(
        instruction: String,
        success: String,
        timeout: String,
        multipleTags: String,
        reading: String,
        tagLost: String,
        unsupportedTag: String,
        readFailed: String
    ) {
        self.instruction = instruction
        self.success = success
        self.timeout = timeout
        self.multipleTags = multipleTags
        self.reading = reading
        self.tagLost = tagLost
        self.unsupportedTag = unsupportedTag
        self.readFailed = readFailed
    }

    var firstEmptyField: String? {
        firstEmptyPresentationField([
            ("instruction", instruction),
            ("success", success),
            ("timeout", timeout),
            ("multipleTags", multipleTags),
            ("reading", reading),
            ("tagLost", tagLost),
            ("unsupportedTag", unsupportedTag),
            ("readFailed", readFailed),
        ])
    }
}

/// Text displayed during one Core NFC write or initialization session.
public struct NfcWriterPresentationMessages: Equatable, Sendable {
    public let instruction: String
    public let success: String
    public let timeout: String
    public let multipleTags: String
    public let checking: String
    public let writing: String
    public let verifying: String
    public let tagLost: String
    public let tagReadOnly: String
    public let capacityExceeded: String
    public let unsupportedTag: String
    public let writeFailed: String
    public let verificationFailed: String

    public static let standard = NfcWriterPresentationMessages(
        instruction: "Hold your iPhone near the NFC tag to write.",
        success: "NFC tag written and verified.",
        timeout: "The NFC write timed out. Try again.",
        multipleTags: "More than one tag was detected. Present only one tag.",
        checking: "Tag detected. Checking write conditions…",
        writing: "Writing. Keep the tag still…",
        verifying: "Write complete. Verifying…",
        tagLost: "The NFC tag moved out of range. Try again.",
        tagReadOnly: "This NFC tag is read-only.",
        capacityExceeded: "The content exceeds this tag's NDEF capacity.",
        unsupportedTag: "This tag does not support NDEF writing.",
        writeFailed: "The NFC tag could not be written. Try again.",
        verificationFailed: "The NFC write could not be verified."
    )

    public init(
        instruction: String,
        success: String,
        timeout: String,
        multipleTags: String,
        checking: String,
        writing: String,
        verifying: String,
        tagLost: String,
        tagReadOnly: String,
        capacityExceeded: String,
        unsupportedTag: String,
        writeFailed: String,
        verificationFailed: String
    ) {
        self.instruction = instruction
        self.success = success
        self.timeout = timeout
        self.multipleTags = multipleTags
        self.checking = checking
        self.writing = writing
        self.verifying = verifying
        self.tagLost = tagLost
        self.tagReadOnly = tagReadOnly
        self.capacityExceeded = capacityExceeded
        self.unsupportedTag = unsupportedTag
        self.writeFailed = writeFailed
        self.verificationFailed = verificationFailed
    }

    var firstEmptyField: String? {
        firstEmptyPresentationField([
            ("instruction", instruction),
            ("success", success),
            ("timeout", timeout),
            ("multipleTags", multipleTags),
            ("checking", checking),
            ("writing", writing),
            ("verifying", verifying),
            ("tagLost", tagLost),
            ("tagReadOnly", tagReadOnly),
            ("capacityExceeded", capacityExceeded),
            ("unsupportedTag", unsupportedTag),
            ("writeFailed", writeFailed),
            ("verificationFailed", verificationFailed),
        ])
    }
}

private func firstEmptyPresentationField(
    _ values: [(String, String)]
) -> String? {
    values.first { _, value in
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }?.0
}
