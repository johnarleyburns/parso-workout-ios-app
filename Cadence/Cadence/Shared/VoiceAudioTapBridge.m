#import "VoiceAudioTapBridge.h"

void CadenceInstallAudioTap(AVAudioInputNode *inputNode,
                            AVAudioFrameCount bufferSize,
                            AVAudioFormat * _Nullable format,
                            AVAudioNodeTapBlock block) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [inputNode installTapOnBus:0 bufferSize:bufferSize format:format block:block];
#pragma clang diagnostic pop
}
