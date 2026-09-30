#import <AVFAudio/AVFAudio.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT void CadenceInstallAudioTap(AVAudioInputNode *inputNode,
                                              AVAudioFrameCount bufferSize,
                                              AVAudioFormat * _Nullable format,
                                              AVAudioNodeTapBlock block);

NS_ASSUME_NONNULL_END
