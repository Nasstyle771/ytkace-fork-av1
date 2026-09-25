#import "DisplayRateHooks.h"
#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static IMP OriginalObjectForInfoDictionaryKey;
static IMP OriginalInfoDictionary;
static IMP OriginalDisplayLinkSetPreferredFrameRateRange;
static IMP OriginalDisplayLinkSetPreferredFramesPerSecond;
static IMP OriginalLayerSetPreferredFrameRateRange;
static IMP OriginalAnimationSetPreferredFrameRateRange;
static IMP OriginalAVPlayerPlay;
static IMP OriginalAVPlayerPause;
static IMP OriginalAVPlayerSetRate;
static IMP OriginalAVPlayerReplaceCurrentItem;
static IMP OriginalAppSendEvent;
static IMP OriginalScrollViewSetContentOffset;

static BOOL s_videoPlaybackActive = NO;
static CFTimeInterval s_lastTouchInteraction = 0.0;

void YTKACESetVideoPlaybackActive(BOOL active) {
    s_videoPlaybackActive = active;
}

BOOL YTKACEIsVideoPlaybackActive(void) {
    return s_videoPlaybackActive;
}

void YTKACENoteTouchInteraction(void) {
    s_lastTouchInteraction = CACurrentMediaTime();
}

static inline BOOL YTKACEIsTouchOrScrollActive(void) {
    return (CACurrentMediaTime() - s_lastTouchInteraction) < 0.45;
}

static void YTKACEAppSendEvent(UIApplication *receiver, SEL selector, UIEvent *event) {
    if (OriginalAppSendEvent != NULL) {
        ((void (*)(id, SEL, id))OriginalAppSendEvent)(receiver, selector, event);
    }
    if (event.type == UIEventTypeTouches) {
        s_lastTouchInteraction = CACurrentMediaTime();
    }
}

static void YTKACEScrollViewSetContentOffset(UIScrollView *receiver, SEL selector, CGPoint offset) {
    if (OriginalScrollViewSetContentOffset != NULL) {
        ((void (*)(id, SEL, CGPoint))OriginalScrollViewSetContentOffset)(receiver, selector, offset);
    }
    if (receiver.isDragging || receiver.isDecelerating || receiver.isTracking) {
        s_lastTouchInteraction = CACurrentMediaTime();
    }
}

static void YTKACEAVPlayerPlay(AVPlayer *receiver, SEL selector) {
    s_videoPlaybackActive = YES;
    if (OriginalAVPlayerPlay != NULL) {
        ((void (*)(id, SEL))OriginalAVPlayerPlay)(receiver, selector);
    }
}

static void YTKACEAVPlayerPause(AVPlayer *receiver, SEL selector) {
    s_videoPlaybackActive = NO;
    if (OriginalAVPlayerPause != NULL) {
        ((void (*)(id, SEL))OriginalAVPlayerPause)(receiver, selector);
    }
}

static void YTKACEAVPlayerSetRate(AVPlayer *receiver, SEL selector, float rate) {
    s_videoPlaybackActive = (rate > 0.01f);
    if (OriginalAVPlayerSetRate != NULL) {
        ((void (*)(id, SEL, float))OriginalAVPlayerSetRate)(receiver, selector, rate);
    }
}

static void YTKACEAVPlayerReplaceCurrentItem(AVPlayer *receiver, SEL selector, AVPlayerItem *item) {
    if (item == nil) {
        s_videoPlaybackActive = NO;
    }
    if (OriginalAVPlayerReplaceCurrentItem != NULL) {
        ((void (*)(id, SEL, id))OriginalAVPlayerReplaceCurrentItem)(receiver, selector, item);
    }
}

static id YTKACEObjectForInfoDictionaryKey(NSBundle *receiver, SEL selector, NSString *key) {
    if ([key isEqualToString:@"CADisableMinimumFrameDurationOnPhone"] ||
        [key isEqualToString:@"CADisableMinimumFrameDuration"]) {
        return @YES;
    }
    if (OriginalObjectForInfoDictionaryKey != NULL) {
        return ((id (*)(id, SEL, id))OriginalObjectForInfoDictionaryKey)(receiver, selector, key);
    }
    return nil;
}

static NSDictionary *YTKACEInfoDictionary(NSBundle *receiver, SEL selector) {
    NSDictionary *dict = OriginalInfoDictionary == NULL
        ? nil
        : ((id (*)(id, SEL))OriginalInfoDictionary)(receiver, selector);
    if (dict == nil) return @{@"CADisableMinimumFrameDurationOnPhone": @YES};
    if (dict[@"CADisableMinimumFrameDurationOnPhone"] == nil) {
        NSMutableDictionary *mutableDict = [dict mutableCopy];
        mutableDict[@"CADisableMinimumFrameDurationOnPhone"] = @YES;
        return mutableDict;
    }
    return dict;
}

static void YTKACEDisplayLinkSetPreferredFrameRateRange(CADisplayLink *receiver,
                                                       SEL selector,
                                                       CAFrameRateRange range) {
    if (YTKACE120HzActive()) {
        BOOL preserveVideo = YTKACEFeatureEnabled(YTKACEPreserveVideoFPSKey);
        if (preserveVideo && s_videoPlaybackActive && range.maximum <= 60.0f && range.maximum >= 23.0f) {
            // Keep exact video frame pacing (24/30/60fps) unchanged to avoid micro-stutter/judder
        } else if (range.maximum >= 59.0f || range.preferred >= 59.0f) {
            id modeVal = YTKACEPreferenceObject(YTKACE120HzModeKey);
            NSInteger mode = [modeVal respondsToSelector:@selector(integerValue)] ? [modeVal integerValue] : 0;
            if (mode == 1) { // Locked 120Hz
                range = CAFrameRateRangeMake(120.0f, 120.0f, 120.0f);
            } else { // Dynamic Adaptive 80-120Hz scaling
                if (YTKACEIsTouchOrScrollActive()) {
                    range = CAFrameRateRangeMake(80.0f, 120.0f, 120.0f);
                } else {
                    range = CAFrameRateRangeMake(60.0f, 120.0f, 120.0f);
                }
            }
        }
    }
    if (OriginalDisplayLinkSetPreferredFrameRateRange != NULL) {
        ((void (*)(id, SEL, CAFrameRateRange))OriginalDisplayLinkSetPreferredFrameRateRange)(
            receiver, selector, range);
    }
}

static void YTKACEDisplayLinkSetPreferredFramesPerSecond(CADisplayLink *receiver,
                                                         SEL selector,
                                                         NSInteger fps) {
    if (YTKACE120HzActive()) {
        BOOL preserveVideo = YTKACEFeatureEnabled(YTKACEPreserveVideoFPSKey);
        if (preserveVideo && s_videoPlaybackActive && fps <= 60 && fps >= 24) {
            // Keep exact video fps to preserve cadence
        } else if (fps >= 59) {
            fps = 120;
        }
    }
    if (OriginalDisplayLinkSetPreferredFramesPerSecond != NULL) {
        ((void (*)(id, SEL, NSInteger))OriginalDisplayLinkSetPreferredFramesPerSecond)(
            receiver, selector, fps);
    }
}

static void YTKACELayerSetPreferredFrameRateRange(CALayer *receiver,
                                                 SEL selector,
                                                 CAFrameRateRange range) {
    if (YTKACE120HzActive()) {
        if (range.maximum >= 59.0f || range.preferred >= 59.0f) {
            id modeVal = YTKACEPreferenceObject(YTKACE120HzModeKey);
            NSInteger mode = [modeVal respondsToSelector:@selector(integerValue)] ? [modeVal integerValue] : 0;
            if (mode == 1) {
                range = CAFrameRateRangeMake(120.0f, 120.0f, 120.0f);
            } else {
                range = YTKACEIsTouchOrScrollActive()
                    ? CAFrameRateRangeMake(80.0f, 120.0f, 120.0f)
                    : CAFrameRateRangeMake(60.0f, 120.0f, 120.0f);
            }
        }
    }
    if (OriginalLayerSetPreferredFrameRateRange != NULL) {
        ((void (*)(id, SEL, CAFrameRateRange))OriginalLayerSetPreferredFrameRateRange)(
            receiver, selector, range);
    }
}

static void YTKACEAnimationSetPreferredFrameRateRange(CAAnimation *receiver,
                                                     SEL selector,
                                                     CAFrameRateRange range) {
    if (YTKACE120HzActive()) {
        if (range.maximum >= 59.0f || range.preferred >= 59.0f) {
            id modeVal = YTKACEPreferenceObject(YTKACE120HzModeKey);
            NSInteger mode = [modeVal respondsToSelector:@selector(integerValue)] ? [modeVal integerValue] : 0;
            if (mode == 1) {
                range = CAFrameRateRangeMake(120.0f, 120.0f, 120.0f);
            } else {
                range = YTKACEIsTouchOrScrollActive()
                    ? CAFrameRateRangeMake(80.0f, 120.0f, 120.0f)
                    : CAFrameRateRangeMake(60.0f, 120.0f, 120.0f);
            }
        }
    }
    if (OriginalAnimationSetPreferredFrameRateRange != NULL) {
        ((void (*)(id, SEL, CAFrameRateRange))OriginalAnimationSetPreferredFrameRateRange)(
            receiver, selector, range);
    }
}

struct YTKACEASRangeTuningParams {
    CGFloat leadingBufferScreenfuls;
    CGFloat trailingBufferScreenfuls;
};

static struct YTKACEASRangeTuningParams YTKACECollectionNodeRangeTuning(id receiver, SEL selector, NSInteger rangeType) {
    (void)receiver;
    (void)selector;
    struct YTKACEASRangeTuningParams params;
    BOOL boost = YTKACEFeatureEnabled(YTKACESmoothScrollBoostKey);
    // rangeType 0 = FetchData (network download) -> 4.5 screens ahead
    // rangeType 1 = Display (render bitmaps/layers) -> 2.5 screens ahead
    if (rangeType == 0) {
        params.leadingBufferScreenfuls = boost ? 4.5f : 2.0f;
        params.trailingBufferScreenfuls = 1.0f;
    } else {
        params.leadingBufferScreenfuls = boost ? 2.5f : 1.5f;
        params.trailingBufferScreenfuls = 0.5f;
    }
    return params;
}

static struct YTKACEASRangeTuningParams YTKACECollectionNodeRangeTuningMode(id receiver, SEL selector, NSInteger rangeMode, NSInteger rangeType) {
    (void)receiver;
    (void)selector;
    (void)rangeMode;
    return YTKACECollectionNodeRangeTuning(receiver, selector, rangeType);
}

static CGFloat YTKACECollectionViewLeadingScreens(id receiver, SEL selector) {
    (void)receiver;
    (void)selector;
    BOOL boost = YTKACEFeatureEnabled(YTKACESmoothScrollBoostKey);
    return boost ? 4.0f : 2.0f;
}

void YTKACEInstallDisplayRateHooks(void) {
    static dispatch_once_t cacheToken;
    dispatch_once(&cacheToken, ^{
        NSURLCache *shared = [[NSURLCache alloc] initWithMemoryCapacity:256 * 1024 * 1024
                                                           diskCapacity:1024 * 1024 * 1024
                                                               diskPath:@"ytkace_image_cache"];
        [NSURLCache setSharedURLCache:shared];

        // Automatic AVPlayer state observation
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification *note) {
            s_videoPlaybackActive = NO;
        }];
        [nc addObserverForName:AVPlayerItemFailedToPlayToEndTimeNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification *note) {
            s_videoPlaybackActive = NO;
        }];
        [nc addObserverForName:AVPlayerItemPlaybackStalledNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification *note) {
            s_videoPlaybackActive = NO;
        }];
    });

    // ProMotion 120Hz Info.plist hooks
    YTKACEInstallInstanceHook(@"NSBundle",
                              @"objectForInfoDictionaryKey:",
                              (IMP)YTKACEObjectForInfoDictionaryKey,
                              &OriginalObjectForInfoDictionaryKey);
    YTKACEInstallInstanceHook(@"NSBundle",
                              @"infoDictionary",
                              (IMP)YTKACEInfoDictionary,
                              &OriginalInfoDictionary);

    // CADisplayLink ProMotion hooks
    YTKACEInstallInstanceHook(@"CADisplayLink",
                              @"setPreferredFrameRateRange:",
                              (IMP)YTKACEDisplayLinkSetPreferredFrameRateRange,
                              &OriginalDisplayLinkSetPreferredFrameRateRange);
    YTKACEInstallInstanceHook(@"CADisplayLink",
                              @"setPreferredFramesPerSecond:",
                              (IMP)YTKACEDisplayLinkSetPreferredFramesPerSecond,
                              &OriginalDisplayLinkSetPreferredFramesPerSecond);

    // CALayer & CAAnimation ProMotion hooks
    YTKACEInstallInstanceHook(@"CALayer",
                              @"setPreferredFrameRateRange:",
                              (IMP)YTKACELayerSetPreferredFrameRateRange,
                              &OriginalLayerSetPreferredFrameRateRange);
    YTKACEInstallInstanceHook(@"CAAnimation",
                              @"setPreferredFrameRateRange:",
                              (IMP)YTKACEAnimationSetPreferredFrameRateRange,
                              &OriginalAnimationSetPreferredFrameRateRange);

    // Touch & scroll activity tracking for dynamic 80-120Hz scaling
    YTKACEInstallInstanceHook(@"UIApplication",
                              @"sendEvent:",
                              (IMP)YTKACEAppSendEvent,
                              &OriginalAppSendEvent);
    YTKACEInstallInstanceHook(@"UIScrollView",
                              @"setContentOffset:",
                              (IMP)YTKACEScrollViewSetContentOffset,
                              &OriginalScrollViewSetContentOffset);

    // AVPlayer video playback status hooks
    YTKACEInstallInstanceHook(@"AVPlayer", @"play", (IMP)YTKACEAVPlayerPlay, &OriginalAVPlayerPlay);
    YTKACEInstallInstanceHook(@"AVPlayer", @"pause", (IMP)YTKACEAVPlayerPause, &OriginalAVPlayerPause);
    YTKACEInstallInstanceHook(@"AVPlayer", @"setRate:", (IMP)YTKACEAVPlayerSetRate, &OriginalAVPlayerSetRate);
    YTKACEInstallInstanceHook(@"AVPlayer", @"replaceCurrentItemWithPlayerItem:",
                              (IMP)YTKACEAVPlayerReplaceCurrentItem, &OriginalAVPlayerReplaceCurrentItem);

    // Texture / AsyncDisplayKit Range Tuning for buttery smooth feed scrolling
    IMP originalRangeTuning = NULL;
    YTKACEInstallInstanceHook(@"ASCollectionNode",
                              @"rangeTuningParametersForRangeType:",
                              (IMP)YTKACECollectionNodeRangeTuning,
                              &originalRangeTuning);

    IMP originalRangeTuningMode = NULL;
    YTKACEInstallInstanceHook(@"ASCollectionNode",
                              @"rangeTuningParametersForRangeMode:rangeType:",
                              (IMP)YTKACECollectionNodeRangeTuningMode,
                              &originalRangeTuningMode);

    IMP originalTableRangeTuning = NULL;
    YTKACEInstallInstanceHook(@"ASTableNode",
                              @"rangeTuningParametersForRangeType:",
                              (IMP)YTKACECollectionNodeRangeTuning,
                              &originalTableRangeTuning);

    IMP originalLeadingScreens = NULL;
    YTKACEInstallInstanceHook(@"ASCollectionView",
                              @"leadingScreensForBatching",
                              (IMP)YTKACECollectionViewLeadingScreens,
                              &originalLeadingScreens);
}
