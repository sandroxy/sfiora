#import <CoreNFC/CoreNFC.h>

NS_ASSUME_NONNULL_BEGIN

// Test-only OS doubles. The production NfcClient and its delegates execute the read path.
@interface SFControlledSession : NFCTagReaderSession
- (instancetype)initWithQueue:(dispatch_queue_t)queue;
@property(nonatomic, copy) void (^onActive)(void);
@property(nonatomic, copy) void (^onInvalidated)(void);
@property(nonatomic, readonly) NSUInteger invalidations;
- (void)completeInvalidation;
@end

@interface SFControlledTag : NSObject <NFCMiFareTag>
@property(nonatomic, readonly) NSUInteger queryCount;
@property(nonatomic, readonly) NSUInteger readCount;
- (void)completeQueryWithError:(nullable NSError *)error;
- (void)completeReadWithText:(NSString *)text error:(nullable NSError *)error;
@end

NS_ASSUME_NONNULL_END
