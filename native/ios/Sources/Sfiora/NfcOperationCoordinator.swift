import Foundation

enum NfcOperationKind {
    case read
    case write
}

struct NfcOperationLease: Equatable {
    fileprivate let identifier: UUID
    let kind: NfcOperationKind
}

/// Serializes NFC read and write sessions in the current process.
enum NfcOperationCoordinator {
    private static let lock = NSLock()
    private static var activeLease: NfcOperationLease?

    static func acquire(_ kind: NfcOperationKind) -> NfcOperationLease? {
        lock.lock()
        defer { lock.unlock() }
        guard activeLease == nil else {
            return nil
        }
        let lease = NfcOperationLease(identifier: UUID(), kind: kind)
        activeLease = lease
        return lease
    }

    static func release(_ lease: NfcOperationLease?) {
        guard let lease else {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        guard activeLease?.identifier == lease.identifier else {
            return
        }
        activeLease = nil
    }
}
