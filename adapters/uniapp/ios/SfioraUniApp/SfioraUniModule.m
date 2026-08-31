#import "SfioraUniModule.h"
#import <SfioraUniApp/SfioraUniApp-Swift.h>

@implementation SfioraUniModule

UNI_EXPORT_METHOD(@selector(getCapabilities:))
- (void)getCapabilities:(UniModuleKeepAliveCallback)callback {
    if (callback) {
        callback(
            [SfioraUniModule
                successEnvelope:[[SfioraBridgeCoordinator shared] getCapabilities]],
            NO
        );
    }
}

UNI_EXPORT_METHOD(@selector(startScan:callback:))
- (void)startScan:(id)options
         callback:(UniModuleKeepAliveCallback)callback {
    if (!callback) {
        return;
    }

    if (options != nil && ![options isKindOfClass:NSDictionary.class]) {
        callback(
            [SfioraUniModule failureEnvelope:@{
                @"code": @"INVALID_OPTIONS",
                @"message": @"options must be an object",
                @"recoverable": @YES
            }],
            NO
        );
        return;
    }

    NSDictionary *safeOptions = options ?: @{};
    [[SfioraBridgeCoordinator shared]
        startScanWithOptions:safeOptions
        success:^(NSDictionary *snapshot) {
            callback(
                [SfioraUniModule successEnvelope:snapshot],
                NO
            );
        }
        failure:^(NSDictionary *error) {
            callback(
                [SfioraUniModule failureEnvelope:error],
                NO
            );
        }];
}

UNI_EXPORT_METHOD(@selector(cancelScan:))
- (void)cancelScan:(UniModuleKeepAliveCallback)callback {
    [[SfioraBridgeCoordinator shared] cancelScan];
    if (callback) {
        callback([SfioraUniModule successEnvelope:@{}], NO);
    }
}

UNI_EXPORT_METHOD(@selector(isScanning:))
- (void)isScanning:(UniModuleKeepAliveCallback)callback {
    if (callback) {
        callback(
            [SfioraUniModule
                successEnvelope:@([[SfioraBridgeCoordinator shared] isScanning])],
            NO
        );
    }
}

UNI_EXPORT_METHOD(@selector(writeNdef:options:callback:))
- (void)writeNdef:(id)message
          options:(id)options
         callback:(UniModuleKeepAliveCallback)callback {
    if (!callback) {
        return;
    }

    if (![message isKindOfClass:NSDictionary.class]) {
        callback(
            [SfioraUniModule failureEnvelope:@{
                @"code": @"INVALID_OPTIONS",
                @"message": @"message must be an object",
                @"recoverable": @YES
            }],
            NO
        );
        return;
    }
    if (options != nil && ![options isKindOfClass:NSDictionary.class]) {
        callback(
            [SfioraUniModule failureEnvelope:@{
                @"code": @"INVALID_OPTIONS",
                @"message": @"options must be an object",
                @"recoverable": @YES
            }],
            NO
        );
        return;
    }

    [[SfioraBridgeCoordinator shared]
        writeNdefWithMessage:(NSDictionary *)message
        options:(NSDictionary *)options
        success:^(NSDictionary *result) {
            callback(
                [SfioraUniModule successEnvelope:result],
                NO
            );
        }
        failure:^(NSDictionary *error) {
            callback(
                [SfioraUniModule failureEnvelope:error],
                NO
            );
        }];
}

UNI_EXPORT_METHOD(@selector(initializeNdef:marker:options:callback:))
- (void)initializeNdef:(id)message
                marker:(id)marker
               options:(id)options
              callback:(UniModuleKeepAliveCallback)callback {
    if (!callback) {
        return;
    }
    if (![message isKindOfClass:NSDictionary.class] ||
        ![marker isKindOfClass:NSDictionary.class]) {
        callback(
            [SfioraUniModule failureEnvelope:@{
                @"code": @"INVALID_OPTIONS",
                @"message": @"message and marker must be objects",
                @"recoverable": @YES
            }],
            NO
        );
        return;
    }
    if (options != nil && ![options isKindOfClass:NSDictionary.class]) {
        callback(
            [SfioraUniModule failureEnvelope:@{
                @"code": @"INVALID_OPTIONS",
                @"message": @"options must be an object",
                @"recoverable": @YES
            }],
            NO
        );
        return;
    }

    [[SfioraBridgeCoordinator shared]
        initializeNdefWithMessage:(NSDictionary *)message
        marker:(NSDictionary *)marker
        options:(NSDictionary *)options
        success:^(NSDictionary *result) {
            callback([SfioraUniModule successEnvelope:result], NO);
        }
        failure:^(NSDictionary *error) {
            callback([SfioraUniModule failureEnvelope:error], NO);
        }];
}

UNI_EXPORT_METHOD(@selector(cancelWrite:))
- (void)cancelWrite:(UniModuleKeepAliveCallback)callback {
    [[SfioraBridgeCoordinator shared] cancelWrite];
    if (callback) {
        callback([SfioraUniModule successEnvelope:@{}], NO);
    }
}

UNI_EXPORT_METHOD(@selector(isWriting:))
- (void)isWriting:(UniModuleKeepAliveCallback)callback {
    if (callback) {
        callback(
            [SfioraUniModule
                successEnvelope:@([[SfioraBridgeCoordinator shared] isWriting])],
            NO
        );
    }
}

- (void)dealloc {
    [[SfioraBridgeCoordinator shared] cancelScan];
    [[SfioraBridgeCoordinator shared] cancelWrite];
}

+ (NSDictionary *)successEnvelope:(id)data {
    return @{
        @"ok": @YES,
        @"data": data ?: NSNull.null
    };
}

+ (NSDictionary *)failureEnvelope:(NSDictionary *)error {
    return @{
        @"ok": @NO,
        @"error": error ?: @{
            @"code": @"INTERNAL_ERROR",
            @"message": @"The NFC operation failed",
            @"recoverable": @NO
        }
    };
}

@end
