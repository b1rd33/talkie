#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN
// AVAudioEngine can raise Objective-C exceptions, which Swift do/catch cannot catch.
BOOL TalkieStartAudioCapture(AVAudioEngine *engine, AVAudioNodeTapBlock block,
                             NSError **error);
NS_ASSUME_NONNULL_END
