#import <XCTest/XCTest.h>
#import "../Talkie/Core/Audio/AudioCapture.h"

// Selector-compatible doubles keep these failure tests independent of real microphones.
@interface CaptureInput : NSObject
@property double tappedRate;
@property BOOL removed;
@property BOOL failInstallation;
@end
@implementation CaptureInput
- (AVAudioFormat *)inputFormatForBus:(AVAudioNodeBus)bus {
    return [[AVAudioFormat alloc] initStandardFormatWithSampleRate:24000 channels:1];
}
- (AVAudioFormat *)outputFormatForBus:(AVAudioNodeBus)bus {
    return [[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000 channels:1];
}
- (void)installTapOnBus:(AVAudioNodeBus)bus bufferSize:(AVAudioFrameCount)size
                format:(AVAudioFormat *)format block:(AVAudioNodeTapBlock)block {
    if (self.failInstallation) [NSException raise:NSInvalidArgumentException format:@"Format changed"];
    self.tappedRate = format.sampleRate;
}
- (void)removeTapOnBus:(AVAudioNodeBus)bus { self.removed = YES; }
@end

@interface CaptureEngine : NSObject
@property CaptureInput *input;
@property BOOL failStart;
@property BOOL stopped;
@end
@implementation CaptureEngine
- (instancetype)init {
    if ((self = [super init])) _input = [CaptureInput new];
    return self;
}
- (AVAudioInputNode *)inputNode { return (id)self.input; }
- (void)prepare {}
- (BOOL)startAndReturnError:(NSError **)error {
    if (!self.failStart) return YES;
    *error = [NSError errorWithDomain:@"Test" code:1 userInfo:nil];
    return NO;
}
- (void)stop { self.stopped = YES; }
@end

@interface AudioCaptureTests : XCTestCase
@end
@implementation AudioCaptureTests
- (void)testTapUsesHardwareRateInsteadOfStaleOutputRate {
    CaptureEngine *engine = [CaptureEngine new];
    NSError *error = nil;
    XCTAssertTrue(TalkieStartAudioCapture((id)engine, ^(AVAudioPCMBuffer *b, AVAudioTime *t) {}, &error));
    XCTAssertNil(error);
    XCTAssertEqual(engine.input.tappedRate, 24000);
}
- (void)testFormatExceptionBecomesRecoverableError {
    CaptureEngine *engine = [CaptureEngine new];
    engine.input.failInstallation = YES;
    NSError *error = nil;
    XCTAssertFalse(TalkieStartAudioCapture((id)engine, ^(AVAudioPCMBuffer *b, AVAudioTime *t) {}, &error));
    XCTAssertNotNil(error);
    XCTAssertTrue(engine.stopped);
    XCTAssertFalse(engine.input.removed);
}
- (void)testFailedStartRemovesTapAndStopsEngine {
    CaptureEngine *engine = [CaptureEngine new];
    engine.failStart = YES;
    NSError *error = nil;
    XCTAssertFalse(TalkieStartAudioCapture((id)engine, ^(AVAudioPCMBuffer *b, AVAudioTime *t) {}, &error));
    XCTAssertNotNil(error);
    XCTAssertTrue(engine.stopped);
    XCTAssertTrue(engine.input.removed);
}
@end
