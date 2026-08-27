import Foundation

#if os(iOS) && canImport(CoreNFC)
    import CoreNFC
#endif

/// Device-level NFC availability.
public enum NfcFeature: String, CaseIterable, Equatable, Sendable {
    case discover
    case ndef
    case ndefWrite
    case ndefInitialize
    case ndefCompatibility
    case iso14443
    case iso15693
    case iso18092ByHostConfiguration
}

public struct NfcCapabilities: Equatable, Sendable {
    public let supported: Bool
    public let enabled: Bool
    public let features: [NfcFeature]

    public init(supported: Bool, enabled: Bool) {
        self.init(
            supported: supported,
            enabled: enabled,
            features: supported ? NfcFeature.allCases : []
        )
    }

    public init(
        supported: Bool,
        enabled: Bool,
        features: [NfcFeature]
    ) {
        self.supported = supported
        self.enabled = supported && enabled
        self.features = supported ? features : []
    }

    public static var current: NfcCapabilities {
        #if os(iOS) && canImport(CoreNFC)
            let available = NFCNDEFReaderSession.readingAvailable
            return NfcCapabilities(supported: available, enabled: available)
        #else
            return NfcCapabilities(supported: false, enabled: false)
        #endif
    }

    public var readerModeSupported: Bool { supported }

    public var dictionary: [String: Any] {
        [
            "platform": "ios",
            "supported": supported,
            "enabled": enabled,
            "readerModeSupported": readerModeSupported,
            "features": features.map(\.rawValue),
        ]
    }
}
