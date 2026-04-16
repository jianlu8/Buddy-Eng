#import "LiteRTBridge.h"

#import "LiteRTShim.hpp"

namespace {

NSString *ExtractTextFromChunkJSON(const std::string &json_chunk) {
    if (json_chunk.empty()) {
        return @"";
    }

    NSData *data = [NSData dataWithBytes:json_chunk.data() length:json_chunk.size()];
    if (data == nil) {
        return @(json_chunk.c_str());
    }

    NSError *json_error = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&json_error];
    if (json_error != nil || ![object isKindOfClass:[NSDictionary class]]) {
        return @(json_chunk.c_str());
    }

    NSDictionary *message = (NSDictionary *)object;
    id content = message[@"content"];
    if ([content isKindOfClass:[NSString class]]) {
        return (NSString *)content;
    }
    if (![content isKindOfClass:[NSArray class]]) {
        return @"";
    }

    NSMutableString *text = [NSMutableString string];
    for (id item in (NSArray *)content) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSDictionary *content_item = (NSDictionary *)item;
        if ([content_item[@"type"] isKindOfClass:[NSString class]] &&
            [content_item[@"text"] isKindOfClass:[NSString class]] &&
            [content_item[@"type"] isEqualToString:@"text"]) {
            [text appendString:content_item[@"text"]];
        }
    }

    return text.length > 0 ? text : @"";
}

}  // namespace

@implementation LiteRTBridge {
    LiteRTShim *_shim;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _shim = new LiteRTShim();
    }
    return self;
}

- (void)dealloc {
    delete _shim;
    _shim = nullptr;
}

- (BOOL)prepareWithModelURL:(NSURL *)modelURL
          cacheDirectoryURL:(NSURL *)cacheDirectoryURL
                    backend:(LiteRTBridgeBackend)backend
                      error:(NSError **)error {
    std::string message;
    const BOOL success = _shim->Prepare(
        modelURL.path.UTF8String,
        cacheDirectoryURL.path.UTF8String,
        backend == LiteRTBridgeBackendGPU,
        &message
    );
    if (!success && error != nil) {
        *error = [NSError errorWithDomain:@"LiteRTBridge" code:100 userInfo:@{NSLocalizedDescriptionKey: @(message.c_str())}];
    }
    return success;
}

- (BOOL)startConversationWithSystemPrompt:(NSString *)systemPrompt
                            memoryContext:(NSString *)memoryContext
                                     mode:(NSString *)mode
                                    error:(NSError **)error {
    std::string message;
    const BOOL success = _shim->StartConversation(systemPrompt.UTF8String, memoryContext.UTF8String, mode.UTF8String, &message);
    if (!success && error != nil) {
        *error = [NSError errorWithDomain:@"LiteRTBridge" code:101 userInfo:@{NSLocalizedDescriptionKey: @(message.c_str())}];
    }
    return success;
}

- (BOOL)sendText:(NSString *)text
         onToken:(void (^)(NSString *, BOOL, NSError * _Nullable))onToken
           error:(NSError **)error {
    if (onToken == nil) {
        if (error != nil) {
            *error = [NSError errorWithDomain:@"LiteRTBridge" code:102 userInfo:@{NSLocalizedDescriptionKey: @"Token callback is required."}];
        }
        return NO;
    }

    std::string message;
    const BOOL success = _shim->SendTextStreaming(text.UTF8String,
                                                  [weakSelf = self, onToken](const std::string &token,
                                                                             bool isFinal,
                                                                             const std::string &errorText) {
        if (weakSelf == nil) {
            return;
        }

        if (errorText.empty() == false) {
            const BOOL isCancelled = errorText == "__ENGLISH_BUDDY_CANCELLED__" ||
                errorText.find("cancelled") != std::string::npos ||
                errorText.find("Cancelled") != std::string::npos ||
                errorText.find("CANCELLED") != std::string::npos;
            NSString *description = isCancelled ? @"Generation cancelled." : @(errorText.c_str());
            NSError *streamError = [NSError errorWithDomain:@"LiteRTBridge"
                                                       code:isCancelled ? 499 : 103
                                                   userInfo:@{NSLocalizedDescriptionKey: description}];
            onToken(@"", YES, streamError);
            return;
        }

        NSString *textChunk = ExtractTextFromChunkJSON(token);
        if (isFinal && textChunk.length > 0) {
            onToken(textChunk, NO, nil);
            onToken(@"", YES, nil);
            return;
        }

        onToken(textChunk, isFinal, nil);
    }, &message);
    if (!success && error != nil) {
        *error = [NSError errorWithDomain:@"LiteRTBridge" code:103 userInfo:@{NSLocalizedDescriptionKey: @(message.c_str())}];
    }
    return success;
}

- (void)cancelCurrentResponse {
    _shim->Cancel();
}

@end
