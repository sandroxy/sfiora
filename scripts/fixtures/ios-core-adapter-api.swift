import Foundation
import Sfiora

// Compiled against each distributed slice, never executed by verification.
func verifySfioraPublicApi() throws {
    let client = NfcClient()
    let capabilities: NfcCapabilities = client.capabilities
    _ = capabilities.features
    _ = client.state
    _ = client.isReading
    _ = client.isWriting
    client.stateChangeHandler = { state in
        switch state {
        case .idle, .reading, .writing: break
        @unknown default: break
        }
    }
    let marker = try NdefExternalType(domain: "example.org", type: "sample")
    let message = try NdefMessage(records: [
        NdefRecord.external(domain: marker.domain, type: marker.type, payload: Data([1]))
    ])
    client.startRead(configuration: .standard) { (result: Result<NfcTagSnapshot, NfcError>) in
        _ = result
    }
    client.cancelRead()
    client.startWrite(message: message, configuration: .standard) {
        (result: Result<NfcWriteResult, NfcError>) in
        _ = result
    }
    client.cancelWrite()
    try client.startInitialize(message: message, marker: marker, configuration: .standard) {
        (result: Result<NfcInitializationResult, NfcError>) in
        _ = result
    }
    client.stop()
}
