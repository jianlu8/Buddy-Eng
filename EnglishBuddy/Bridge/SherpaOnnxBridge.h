#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SherpaOnnxASRResult : NSObject

@property (nonatomic, copy, readonly) NSString *text;
@property (nonatomic, assign, readonly) BOOL endpointDetected;

- (instancetype)initWithText:(NSString *)text
            endpointDetected:(BOOL)endpointDetected NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface SherpaOnnxTTSResult : NSObject

@property (nonatomic, strong, readonly) NSData *pcmFloatData;
@property (nonatomic, assign, readonly) NSInteger sampleRate;
@property (nonatomic, assign, readonly) NSInteger sampleCount;

- (instancetype)initWithPCMFloatData:(NSData *)pcmFloatData
                          sampleRate:(NSInteger)sampleRate
                         sampleCount:(NSInteger)sampleCount NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

@interface SherpaOnnxASRBridge : NSObject

- (BOOL)prepareWithAssetDirectoryURL:(NSURL *)assetDirectoryURL
                               error:(NSError * _Nullable * _Nullable)error;

- (nullable SherpaOnnxASRResult *)processAudioSamples:(NSData *)pcmFloatData
                                           sampleRate:(NSInteger)sampleRate
                                        inputFinished:(BOOL)inputFinished
                                                error:(NSError * _Nullable * _Nullable)error;

- (void)reset;

@end

@interface SherpaOnnxTTSBridge : NSObject

- (BOOL)prepareWithAssetDirectoryURL:(NSURL *)assetDirectoryURL
                         lexiconPath:(nullable NSString *)lexiconPath
                        languageHint:(nullable NSString *)languageHint
                               error:(NSError * _Nullable * _Nullable)error;

- (nullable SherpaOnnxTTSResult *)generateSpeechForText:(NSString *)text
                                              speakerID:(NSInteger)speakerID
                                                  speed:(float)speed
                                           silenceScale:(float)silenceScale
                                              extraJSON:(nullable NSString *)extraJSON
                                                  error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
