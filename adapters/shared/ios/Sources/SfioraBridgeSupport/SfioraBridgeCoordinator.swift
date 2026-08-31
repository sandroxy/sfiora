import Foundation

#if os(iOS) && canImport(Sfiora)
    import Sfiora

    /// Process-wide coordinator shared by the React Native and classic UniApp
    /// adapters. It exposes Foundation values only; NFC state and protocol work
    /// remain owned by `NfcClient`.
    @objc(SfioraBridgeCoordinator)
    @objcMembers
    public final class SfioraBridgeCoordinator: NSObject {
        public typealias SuccessHandler = (NSDictionary) -> Void
        public typealias FailureHandler = (NSDictionary) -> Void

        public static let shared = SfioraBridgeCoordinator()

        private let client = NfcClient()

        private override init() {
            super.init()
        }

        public func getCapabilities() -> NSDictionary {
            client.capabilities.dictionary as NSDictionary
        }

        @objc(startScanWithOptions:success:failure:)
        public func startScan(
            options: NSDictionary?,
            success: @escaping SuccessHandler,
            failure: @escaping FailureHandler
        ) {
            runOnMain {
                do {
                    let request = try SfioraBridgeOptions.parse(options)
                    self.client.startRead(
                        configuration: request.readerConfiguration
                    ) { result in
                        Self.finish(
                            result,
                            value: { $0.dictionary },
                            success: success,
                            failure: failure
                        )
                    }
                } catch {
                    failure(Self.invalidOptions(error))
                }
            }
        }

        public func cancelScan() {
            client.cancelRead()
        }

        public func isScanning() -> Bool {
            client.isReading
        }

        @objc(writeNdefWithMessage:options:success:failure:)
        public func writeNdef(
            message: NSDictionary,
            options: NSDictionary?,
            success: @escaping SuccessHandler,
            failure: @escaping FailureHandler
        ) {
            runOnMain {
                do {
                    let request = try SfioraBridgeWriteRequest.parse(
                        message: message,
                        options: options
                    )
                    self.client.startWrite(
                        message: request.message,
                        configuration: request.writerConfiguration
                    ) { result in
                        Self.finish(
                            result,
                            value: { $0.dictionary },
                            success: success,
                            failure: failure
                        )
                    }
                } catch {
                    failure(Self.invalidOptions(error))
                }
            }
        }

        @objc(initializeNdefWithMessage:marker:options:success:failure:)
        public func initializeNdef(
            message: NSDictionary,
            marker: NSDictionary,
            options: NSDictionary?,
            success: @escaping SuccessHandler,
            failure: @escaping FailureHandler
        ) {
            runOnMain {
                do {
                    let request = try SfioraBridgeWriteRequest.parse(
                        message: message,
                        options: options
                    )
                    let externalType =
                        try SfioraBridgeWriteRequest
                        .parseExternalTypeMarker(marker)
                    try self.client.startInitialize(
                        message: request.message,
                        marker: externalType,
                        configuration: request.writerConfiguration
                    ) { result in
                        Self.finish(
                            result,
                            value: { $0.dictionary },
                            success: success,
                            failure: failure
                        )
                    }
                } catch {
                    failure(Self.invalidOptions(error))
                }
            }
        }

        public func cancelWrite() {
            client.cancelWrite()
        }

        public func isWriting() -> Bool {
            client.isWriting
        }

        public func stop() {
            client.stop()
        }

        private func runOnMain(_ operation: @escaping () -> Void) {
            if Thread.isMainThread {
                operation()
            } else {
                DispatchQueue.main.async(execute: operation)
            }
        }

        private static func finish<Value>(
            _ result: Result<Value, NfcError>,
            value: (Value) -> [String: Any],
            success: SuccessHandler,
            failure: FailureHandler
        ) {
            switch result {
            case .success(let resultValue):
                success(value(resultValue) as NSDictionary)
            case .failure(let error):
                failure(error.dictionary as NSDictionary)
            }
        }

        private static func invalidOptions(_ error: Error) -> NSDictionary {
            NfcError(
                code: .invalidOptions,
                message: error.localizedDescription,
                recoverable: true,
                nativeError: NfcNativeError(error)
            ).dictionary as NSDictionary
        }
    }
#endif
