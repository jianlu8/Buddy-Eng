#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, LiteRTBridgeBackend) {
    LiteRTBridgeBackendGPU = 0,
    LiteRTBridgeBackendCPU = 1
};

@interface LiteRTBridge : NSObject

- (BOOL)prepareWithModelURL:(NSURL *)modelURL
          cacheDirectoryURL:(NSURL *)cacheDirectoryURL
                    backend:(LiteRTBridgeBackend)backend
                      error:(NSError * _Nullable * _Nullable)error;

- (BOOL)startConversationWithSystemPrompt:(NSString *)systemPrompt
                            memoryContext:(NSString *)memoryContext
                                     mode:(NSString *)mode
                                    error:(NSError * _Nullable * _Nullable)error;

- (BOOL)sendText:(NSString *)text
         onToken:(void (^)(NSString *token, BOOL isFinal, NSError * _Nullable error))onToken
           error:(NSError * _Nullable * _Nullable)error;

- (void)cancelCurrentResponse;

@end

NS_ASSUME_NONNULL_END
