import Foundation

/// A canonical NFC Forum External Type used to identify an NDEF record.
public struct NdefExternalType: Equatable, Hashable, Sendable {
    public let domain: String
    public let type: String
    public let value: String
    private let encodedValue: Data

    public init(domain: String, type: String) throws {
        let record = try NdefRecord.external(
            domain: domain,
            type: type,
            payload: Data()
        )
        self.domain = domain
        self.type = type
        value = "\(domain):\(type)"
        encodedValue = record.type
    }

    public func matches(_ record: NdefRecord) -> Bool {
        record.typeNameFormat == .externalType && record.type == encodedValue
    }

    func matches(typeNameFormat: UInt8, type: Data) -> Bool {
        typeNameFormat == NdefTypeNameFormat.externalType.rawValue
            && type == encodedValue
    }
}
