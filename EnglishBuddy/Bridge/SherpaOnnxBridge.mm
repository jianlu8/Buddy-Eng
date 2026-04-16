#import "SherpaOnnxBridge.h"

#import <sherpa-onnx/c-api/c-api.h>

#include <algorithm>
#include <cstring>
#include <string>
#include <vector>

namespace {

NSString *const kSherpaOnnxBridgeDomain = @"SherpaOnnxBridge";

NSError *SherpaError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:kSherpaOnnxBridgeDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

NSString *FindFilePathMatchingName(NSURL *directoryURL, NSString *fileName) {
    NSURL *candidate = [directoryURL URLByAppendingPathComponent:fileName isDirectory:NO];
    if ([[NSFileManager defaultManager] fileExistsAtPath:candidate.path]) {
        return candidate.path;
    }
    return nil;
}

NSString *FindFirstFileWithSuffix(NSURL *directoryURL, NSString *suffix) {
    NSDirectoryEnumerator<NSURL *> *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:directoryURL
                                                                      includingPropertiesForKeys:nil
                                                                                         options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                    errorHandler:nil];
    for (NSURL *candidate in enumerator) {
        if ([candidate hasDirectoryPath]) {
            continue;
        }
        if ([candidate.lastPathComponent hasSuffix:suffix]) {
            return candidate.path;
        }
    }
    return nil;
}

NSString *FindDirectoryNamed(NSURL *directoryURL, NSString *name) {
    NSURL *candidate = [directoryURL URLByAppendingPathComponent:name isDirectory:YES];
    if ([[NSFileManager defaultManager] fileExistsAtPath:candidate.path]) {
        return candidate.path;
    }
    return nil;
}

NSString *NormalizedConfigValue(NSString *value) {
    NSString *trimmed = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.length == 0 ? nil : trimmed;
}

int32_t RecommendedThreadCount() {
    NSInteger activeCount = NSProcessInfo.processInfo.activeProcessorCount;
    return static_cast<int32_t>(std::max<NSInteger>(1, std::min<NSInteger>(4, activeCount / 2)));
}

}  // namespace

@implementation SherpaOnnxASRResult

- (instancetype)initWithText:(NSString *)text endpointDetected:(BOOL)endpointDetected {
    self = [super init];
    if (self) {
        _text = [text copy];
        _endpointDetected = endpointDetected;
    }
    return self;
}

@end

@implementation SherpaOnnxTTSResult

- (instancetype)initWithPCMFloatData:(NSData *)pcmFloatData
                          sampleRate:(NSInteger)sampleRate
                         sampleCount:(NSInteger)sampleCount {
    self = [super init];
    if (self) {
        _pcmFloatData = pcmFloatData;
        _sampleRate = sampleRate;
        _sampleCount = sampleCount;
    }
    return self;
}

@end

@implementation SherpaOnnxASRBridge {
    const SherpaOnnxOnlineRecognizer *_recognizer;
    const SherpaOnnxOnlineStream *_stream;
    NSString *_preparedAssetPath;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _recognizer = nullptr;
        _stream = nullptr;
    }
    return self;
}

- (void)dealloc {
    [self destroyRuntime];
}

- (BOOL)prepareWithAssetDirectoryURL:(NSURL *)assetDirectoryURL error:(NSError **)error {
    if (assetDirectoryURL == nil) {
        if (error != nil) {
            *error = SherpaError(3001, @"Missing ASR asset directory.");
        }
        return NO;
    }

    if (_recognizer != nullptr &&
        _stream != nullptr &&
        [_preparedAssetPath isEqualToString:assetDirectoryURL.path]) {
        return YES;
    }

    NSString *encoderPath = FindFilePathMatchingName(assetDirectoryURL, @"encoder.int8.onnx")
        ?: FindFirstFileWithSuffix(assetDirectoryURL, @"encoder.int8.onnx");
    NSString *decoderPath = FindFilePathMatchingName(assetDirectoryURL, @"decoder.int8.onnx")
        ?: FindFirstFileWithSuffix(assetDirectoryURL, @"decoder.int8.onnx");
    NSString *joinerPath = FindFilePathMatchingName(assetDirectoryURL, @"joiner.int8.onnx")
        ?: FindFirstFileWithSuffix(assetDirectoryURL, @"joiner.int8.onnx");
    NSString *tokensPath = FindFilePathMatchingName(assetDirectoryURL, @"tokens.txt")
        ?: FindFirstFileWithSuffix(assetDirectoryURL, @"tokens.txt");

    if (encoderPath == nil || decoderPath == nil || joinerPath == nil || tokensPath == nil) {
        if (error != nil) {
            *error = SherpaError(3002, @"Bundled ASR asset is incomplete. Expected encoder/decoder/joiner/tokens files.");
        }
        return NO;
    }

    [self destroyRuntime];

    SherpaOnnxOnlineRecognizerConfig config;
    std::memset(&config, 0, sizeof(config));
    config.feat_config.sample_rate = 16000;
    config.feat_config.feature_dim = 80;
    config.model_config.transducer.encoder = encoderPath.UTF8String;
    config.model_config.transducer.decoder = decoderPath.UTF8String;
    config.model_config.transducer.joiner = joinerPath.UTF8String;
    config.model_config.tokens = tokensPath.UTF8String;
    config.model_config.num_threads = RecommendedThreadCount();
    config.model_config.provider = "cpu";
    config.decoding_method = "greedy_search";
    config.enable_endpoint = 1;
    config.rule1_min_trailing_silence = 1.2f;
    config.rule2_min_trailing_silence = 0.45f;
    config.rule3_min_utterance_length = 12.0f;

    _recognizer = SherpaOnnxCreateOnlineRecognizer(&config);
    if (_recognizer == nullptr) {
        if (error != nil) {
            *error = SherpaError(3003, @"Failed to create the bundled sherpa-onnx recognizer.");
        }
        return NO;
    }

    _stream = SherpaOnnxCreateOnlineStream(_recognizer);
    if (_stream == nullptr) {
        [self destroyRuntime];
        if (error != nil) {
            *error = SherpaError(3004, @"Failed to create the bundled sherpa-onnx stream.");
        }
        return NO;
    }

    _preparedAssetPath = [assetDirectoryURL.path copy];
    return YES;
}

- (SherpaOnnxASRResult *)processAudioSamples:(NSData *)pcmFloatData
                                  sampleRate:(NSInteger)sampleRate
                               inputFinished:(BOOL)inputFinished
                                       error:(NSError **)error {
    if (_recognizer == nullptr || _stream == nullptr) {
        if (error != nil) {
            *error = SherpaError(3005, @"Bundled ASR runtime is not prepared.");
        }
        return nil;
    }

    if (pcmFloatData.length > 0) {
        const auto sampleCount = static_cast<int32_t>(pcmFloatData.length / sizeof(float));
        if (sampleCount > 0) {
            const auto *samples = static_cast<const float *>(pcmFloatData.bytes);
            SherpaOnnxOnlineStreamAcceptWaveform(
                _stream,
                static_cast<int32_t>(sampleRate),
                samples,
                sampleCount
            );
        }
    }

    if (inputFinished) {
        SherpaOnnxOnlineStreamInputFinished(_stream);
    }

    while (SherpaOnnxIsOnlineStreamReady(_recognizer, _stream)) {
        SherpaOnnxDecodeOnlineStream(_recognizer, _stream);
    }

    const SherpaOnnxOnlineRecognizerResult *result = SherpaOnnxGetOnlineStreamResult(_recognizer, _stream);
    if (result == nullptr) {
        if (error != nil) {
            *error = SherpaError(3006, @"Bundled ASR returned an empty recognition result.");
        }
        return nil;
    }

    NSString *text = result->text != nullptr ? @(result->text) : @"";
    const BOOL endpointDetected = SherpaOnnxOnlineStreamIsEndpoint(_recognizer, _stream) != 0;
    SherpaOnnxDestroyOnlineRecognizerResult(result);

    if (endpointDetected) {
        [self recreateStream];
    }

    return [[SherpaOnnxASRResult alloc] initWithText:text endpointDetected:endpointDetected];
}

- (void)reset {
    if (_recognizer == nullptr) {
        return;
    }
    [self recreateStream];
}

- (void)recreateStream {
    if (_stream != nullptr) {
        SherpaOnnxDestroyOnlineStream(_stream);
        _stream = nullptr;
    }
    if (_recognizer != nullptr) {
        _stream = SherpaOnnxCreateOnlineStream(_recognizer);
    }
}

- (void)destroyRuntime {
    if (_stream != nullptr) {
        SherpaOnnxDestroyOnlineStream(_stream);
        _stream = nullptr;
    }
    if (_recognizer != nullptr) {
        SherpaOnnxDestroyOnlineRecognizer(_recognizer);
        _recognizer = nullptr;
    }
    _preparedAssetPath = nil;
}

@end

@implementation SherpaOnnxTTSBridge {
    const SherpaOnnxOfflineTts *_tts;
    NSString *_preparedAssetPath;
    NSString *_preparedLexiconPath;
    NSString *_preparedLanguageHint;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _tts = nullptr;
    }
    return self;
}

- (void)dealloc {
    if (_tts != nullptr) {
        SherpaOnnxDestroyOfflineTts(_tts);
        _tts = nullptr;
    }
}

- (BOOL)prepareWithAssetDirectoryURL:(NSURL *)assetDirectoryURL error:(NSError **)error {
    return [self prepareWithAssetDirectoryURL:assetDirectoryURL lexiconPath:nil languageHint:nil error:error];
}

- (BOOL)prepareWithAssetDirectoryURL:(NSURL *)assetDirectoryURL
                         lexiconPath:(NSString *)lexiconPath
                        languageHint:(NSString *)languageHint
                               error:(NSError **)error {
    if (assetDirectoryURL == nil) {
        if (error != nil) {
            *error = SherpaError(3101, @"Missing TTS asset directory.");
        }
        return NO;
    }

    NSString *resolvedLexiconPath = NormalizedConfigValue(lexiconPath);
    NSString *resolvedLanguageHint = NormalizedConfigValue(languageHint);
    NSString *preparedLexiconPath = _preparedLexiconPath ?: @"";
    NSString *preparedLanguageHint = _preparedLanguageHint ?: @"";
    NSString *requestedLexiconPath = resolvedLexiconPath ?: @"";
    NSString *requestedLanguageHint = resolvedLanguageHint ?: @"";

    if (_tts != nullptr &&
        [_preparedAssetPath isEqualToString:assetDirectoryURL.path] &&
        [preparedLexiconPath isEqualToString:requestedLexiconPath] &&
        [preparedLanguageHint isEqualToString:requestedLanguageHint]) {
        return YES;
    }

    NSString *kokoroModelPath = FindFilePathMatchingName(assetDirectoryURL, @"model.onnx")
        ?: FindFirstFileWithSuffix(assetDirectoryURL, @"model.onnx");
    NSString *voicesPath = FindFilePathMatchingName(assetDirectoryURL, @"voices.bin")
        ?: FindFirstFileWithSuffix(assetDirectoryURL, @"voices.bin");
    NSString *modelPath = kokoroModelPath ?: FindFirstFileWithSuffix(assetDirectoryURL, @".onnx");
    NSString *tokensPath = FindFilePathMatchingName(assetDirectoryURL, @"tokens.txt")
        ?: FindFirstFileWithSuffix(assetDirectoryURL, @"tokens.txt");
    NSString *dataDirPath = FindDirectoryNamed(assetDirectoryURL, @"espeak-ng-data");

    if (modelPath == nil || tokensPath == nil) {
        if (error != nil) {
            *error = SherpaError(3102, @"Bundled TTS asset is incomplete. Expected an ONNX model and tokens.txt.");
        }
        return NO;
    }

    if (_tts != nullptr) {
        SherpaOnnxDestroyOfflineTts(_tts);
        _tts = nullptr;
    }

    SherpaOnnxOfflineTtsConfig config;
    std::memset(&config, 0, sizeof(config));
    if (voicesPath != nil) {
        config.model.kokoro.model = modelPath.UTF8String;
        config.model.kokoro.voices = voicesPath.UTF8String;
        config.model.kokoro.tokens = tokensPath.UTF8String;
        config.model.kokoro.data_dir = dataDirPath.UTF8String;
        config.model.kokoro.length_scale = 1.0f;
        config.model.kokoro.lexicon = resolvedLexiconPath.UTF8String;
        config.model.kokoro.lang = resolvedLanguageHint.UTF8String;
    } else {
        config.model.vits.model = modelPath.UTF8String;
        config.model.vits.tokens = tokensPath.UTF8String;
        config.model.vits.data_dir = dataDirPath.UTF8String;
        config.model.vits.length_scale = 1.0f;
        config.model.vits.noise_scale = 0.667f;
        config.model.vits.noise_scale_w = 0.8f;
    }
    config.model.num_threads = RecommendedThreadCount();
    config.model.provider = "cpu";
    config.max_num_sentences = 2;
    config.silence_scale = 0.2f;

    _tts = SherpaOnnxCreateOfflineTts(&config);
    if (_tts == nullptr) {
        if (error != nil) {
            *error = SherpaError(3103, @"Failed to create the bundled sherpa-onnx TTS runtime.");
        }
        return NO;
    }

    _preparedAssetPath = [assetDirectoryURL.path copy];
    _preparedLexiconPath = [resolvedLexiconPath copy];
    _preparedLanguageHint = [resolvedLanguageHint copy];
    return YES;
}

- (SherpaOnnxTTSResult *)generateSpeechForText:(NSString *)text
                                     speakerID:(NSInteger)speakerID
                                         speed:(float)speed
                                  silenceScale:(float)silenceScale
                                     extraJSON:(NSString *)extraJSON
                                         error:(NSError **)error {
    if (_tts == nullptr) {
        if (error != nil) {
            *error = SherpaError(3104, @"Bundled TTS runtime is not prepared.");
        }
        return nil;
    }

    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) {
        return [[SherpaOnnxTTSResult alloc] initWithPCMFloatData:[NSData data]
                                                      sampleRate:SherpaOnnxOfflineTtsSampleRate(_tts)
                                                     sampleCount:0];
    }

    SherpaOnnxGenerationConfig generationConfig;
    std::memset(&generationConfig, 0, sizeof(generationConfig));
    generationConfig.sid = static_cast<int32_t>(std::max<NSInteger>(0, speakerID));
    generationConfig.speed = std::max(0.72f, std::min(speed, 1.28f));
    generationConfig.silence_scale = std::max(0.08f, std::min(silenceScale, 0.35f));
    generationConfig.extra = NormalizedConfigValue(extraJSON).UTF8String;

    const SherpaOnnxGeneratedAudio *generated = SherpaOnnxOfflineTtsGenerateWithConfig(
        _tts,
        trimmed.UTF8String,
        &generationConfig,
        nullptr,
        nullptr
    );
    if (generated == nullptr) {
        if (error != nil) {
            *error = SherpaError(3105, @"Bundled TTS failed to generate audio.");
        }
        return nil;
    }

    const auto byteCount = static_cast<NSUInteger>(generated->n) * sizeof(float);
    NSData *sampleData = [NSData dataWithBytes:generated->samples length:byteCount];
    SherpaOnnxDestroyOfflineTtsGeneratedAudio(generated);

    return [[SherpaOnnxTTSResult alloc] initWithPCMFloatData:sampleData
                                                  sampleRate:SherpaOnnxOfflineTtsSampleRate(_tts)
                                                 sampleCount:sampleData.length / sizeof(float)];
}

@end
