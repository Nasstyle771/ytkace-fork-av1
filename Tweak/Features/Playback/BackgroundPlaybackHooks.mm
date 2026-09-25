#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"
#import <AVFoundation/AVFoundation.h>

static IMP OriginalPlayableInBackground;
static IMP OriginalMLPlayableInBackground;
static IMP OriginalBackgroundEnabled;
static IMP OriginalAudioSessionSetActive;

static BOOL YTKACEBackgroundBoolean(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(YTKACEBackgroundPlaybackKey)) {
        return YES;
    }

    IMP original = NULL;
    NSString *selName = NSStringFromSelector(selector);
    if ([selName isEqualToString:@"isPlayableInBackground"]) {
        original = OriginalPlayableInBackground;
    } else if ([selName isEqualToString:@"playableInBackground"]) {
        original = OriginalMLPlayableInBackground;
    } else {
        original = OriginalBackgroundEnabled;
    }
    return original == NULL
        ? NO
        : ((BOOL (*)(id, SEL))original)(receiver, selector);
}

static BOOL YTKACEAudioSessionSetActive(AVAudioSession *receiver, SEL selector, BOOL active, AVAudioSessionSetActiveOptions options, NSError **outError) {
    if (!active && YTKACEFeatureEnabled(YTKACEBackgroundPlaybackKey)) {
        // Prevent background deactivation of audio session to ensure zero audio interruption
        return YES;
    }
    if (OriginalAudioSessionSetActive != NULL) {
        return ((BOOL (*)(id, SEL, BOOL, AVAudioSessionSetActiveOptions, NSError **))OriginalAudioSessionSetActive)(
            receiver, selector, active, options, outError);
    }
    return YES;
}

static void YTKACEConfigureAudioSession(void) {
    if (!YTKACEFeatureEnabled(YTKACEBackgroundPlaybackKey)) return;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    @try {
        [session setCategory:AVAudioSessionCategoryPlayback
                 withOptions:AVAudioSessionCategoryOptionMixWithOthers | AVAudioSessionCategoryOptionAllowAirPlay | AVAudioSessionCategoryOptionAllowBluetoothA2DP
                       error:nil];
        [session setActive:YES error:nil];
    } @catch (__unused NSException *exception) {
    }
}

void YTKACEInstallBackgroundPlaybackHooks(void) {
    YTKACEConfigureAudioSession();

    YTKACEInstallInstanceHook(@"YTIPlayabilityStatus",
                              @"isPlayableInBackground",
                              (IMP)YTKACEBackgroundBoolean,
                              &OriginalPlayableInBackground);
    YTKACEInstallInstanceHook(@"MLVideo",
                              @"playableInBackground",
                              (IMP)YTKACEBackgroundBoolean,
                              &OriginalMLPlayableInBackground);
    YTKACEInstallInstanceHook(@"YTPlaybackData",
                              @"isPlayableInBackground",
                              (IMP)YTKACEBackgroundBoolean,
                              NULL);
    YTKACEInstallInstanceHook(@"YTPlaybackData",
                              @"playableInBackground",
                              (IMP)YTKACEBackgroundBoolean,
                              NULL);
    YTKACEInstallInstanceHook(@"YTBackgroundPlaybackController",
                              @"isBackgroundPlaybackAllowed",
                              (IMP)YTKACEBackgroundBoolean,
                              NULL);
    YTKACEInstallInstanceHook(@"YTBackgroundPlaybackController",
                              @"shouldAllowBackgroundPlayback",
                              (IMP)YTKACEBackgroundBoolean,
                              NULL);
    YTKACEInstallInstanceHook(@"YTIPlayerConfig",
                              @"isBackgroundPlaybackEnabled",
                              (IMP)YTKACEBackgroundBoolean,
                              NULL);

    YTKACEInstallInstanceHook(@"AVAudioSession",
                              @"setActive:withOptions:error:",
                              (IMP)YTKACEAudioSessionSetActive,
                              &OriginalAudioSessionSetActive);

    if (!YTKACEInstallInstanceHook(
            @"YTIBackgroundOfflineSettingCategoryEntryRenderer",
            @"isBackgroundEnabled",
            (IMP)YTKACEBackgroundBoolean,
            &OriginalBackgroundEnabled)) {
        YTKACEAddInstanceMethod(
            @"YTIBackgroundOfflineSettingCategoryEntryRenderer",
            @"isBackgroundEnabled",
            (IMP)YTKACEBackgroundBoolean,
            "B@:"
        );
    }

    [NSNotificationCenter.defaultCenter
        addObserverForName:UIApplicationDidEnterBackgroundNotification
                    object:nil
                     queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *note) {
        (void)note;
        YTKACEConfigureAudioSession();
    }];
}
