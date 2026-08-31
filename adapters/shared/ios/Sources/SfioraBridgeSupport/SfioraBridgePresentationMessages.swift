import Foundation

#if canImport(Sfiora)
    import Sfiora
#endif

enum SfioraBridgePresentationMessagesError: Error, Equatable, LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message):
            return message
        }
    }
}

enum SfioraBridgePresentationMessages {
    private static let scanKeys: Set<String> = [
        "title",
        "instruction",
        "cancel",
        "done",
        "success",
        "failureTitle",
        "timeout",
        "nfcDisabled",
        "nfcUnsupported",
        "multipleTags",
        "reading",
        "tagLost",
        "unsupportedTag",
        "readFailed",
    ]
    private static let writeKeys: Set<String> = [
        "title",
        "instruction",
        "cancel",
        "done",
        "success",
        "failureTitle",
        "timeout",
        "nfcDisabled",
        "nfcUnsupported",
        "multipleTags",
        "checking",
        "writing",
        "verifying",
        "tagLost",
        "tagReadOnly",
        "capacityExceeded",
        "unsupportedTag",
        "writeFailed",
        "verificationFailed",
    ]

    static func reader(_ rawValue: Any) throws -> NfcReaderPresentationMessages {
        let values = try dictionary(rawValue)
        try validateExactKeys(values, expected: scanKeys)
        return NfcReaderPresentationMessages(
            instruction: try text(values, "instruction"),
            success: try text(values, "success"),
            timeout: try text(values, "timeout"),
            multipleTags: try text(values, "multipleTags"),
            reading: try text(values, "reading"),
            tagLost: try text(values, "tagLost"),
            unsupportedTag: try text(values, "unsupportedTag"),
            readFailed: try text(values, "readFailed")
        )
    }

    static func writer(_ rawValue: Any) throws -> NfcWriterPresentationMessages {
        let values = try dictionary(rawValue)
        try validateExactKeys(values, expected: writeKeys)
        return NfcWriterPresentationMessages(
            instruction: try text(values, "instruction"),
            success: try text(values, "success"),
            timeout: try text(values, "timeout"),
            multipleTags: try text(values, "multipleTags"),
            checking: try text(values, "checking"),
            writing: try text(values, "writing"),
            verifying: try text(values, "verifying"),
            tagLost: try text(values, "tagLost"),
            tagReadOnly: try text(values, "tagReadOnly"),
            capacityExceeded: try text(values, "capacityExceeded"),
            unsupportedTag: try text(values, "unsupportedTag"),
            writeFailed: try text(values, "writeFailed"),
            verificationFailed: try text(values, "verificationFailed")
        )
    }

    private static func dictionary(_ value: Any) throws -> NSDictionary {
        guard let values = value as? NSDictionary else {
            throw invalid("messages must be an object")
        }
        return values
    }

    private static func validateExactKeys(
        _ values: NSDictionary,
        expected: Set<String>
    ) throws {
        for key in expected where values[key] == nil {
            throw invalid("messages.\(key) is required")
        }
        for key in expected {
            _ = try text(values, key)
        }
        for rawKey in values.allKeys {
            guard let key = rawKey as? String, expected.contains(key) else {
                throw invalid("messages contains an unsupported field: \(rawKey)")
            }
        }
    }

    private static func text(_ values: NSDictionary, _ key: String) throws -> String {
        guard
            let value = values[key] as? String,
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw invalid("messages.\(key) must be a non-empty string")
        }
        return value
    }

    private static func invalid(_ message: String) -> SfioraBridgePresentationMessagesError {
        .invalid(message)
    }
}
