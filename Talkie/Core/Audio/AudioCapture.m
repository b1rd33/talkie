#import "AudioCapture.h"

BOOL TalkieStartAudioCapture(AVAudioEngine *engine, AVAudioNodeTapBlock block,
                             NSError **error) {
    BOOL installedTap = NO;
    @try {
        AVAudioInputNode *input = engine.inputNode;
        // Bluetooth can change its hardware rate independently of the cached output bus.
        AVAudioFormat *format = [input inputFormatForBus:0];
        if (format.sampleRate <= 0 || format.channelCount == 0) {
            if (error) *error = [NSError errorWithDomain:@"Talkie.AudioCapture" code:1
                userInfo:@{NSLocalizedDescriptionKey: @"No input device is available."}];
            return NO;
        }
        [input installTapOnBus:0 bufferSize:4096 format:format block:block];
        installedTap = YES;
        [engine prepare];
        if ([engine startAndReturnError:error]) return YES;
    } @catch (NSException *exception) {
        if (error) *error = [NSError errorWithDomain:@"Talkie.AudioCapture" code:2
            userInfo:@{NSLocalizedDescriptionKey:
                @"The microphone format changed during startup. Try again or choose another microphone."}];
    }
    [engine stop];
    if (installedTap) [engine.inputNode removeTapOnBus:0];
    return NO;
}
