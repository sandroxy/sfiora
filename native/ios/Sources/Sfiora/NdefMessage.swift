import Foundation

/// One complete NDEF message with deterministic NFC Forum serialization.
public struct NdefMessage: Equatable, Hashable, Sendable {
    public let records: [NdefRecord]
    private let encodedData: Data

    public init(records: [NdefRecord]) throws {
        guard !records.isEmpty else {
            throw NdefError.emptyMessage
        }
        self.records = records
        do {
            encodedData = try NdefMessageEncoder.encode(
                records.map(\.recordValue)
            )
        } catch {
            throw NdefError.messageEncodingFailed
        }
    }

    public var byteCount: Int {
        encodedData.count
    }

    public var serializedData: Data {
        Data(encodedData)
    }
}
