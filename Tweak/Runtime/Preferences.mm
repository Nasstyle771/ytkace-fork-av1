#import "Preferences.h"
#import "Localization.h"
#import "../Features/Downloads/SABRDownloader.h"

#import <UIKit/UIKit.h>

NSString * const YTKACEMasterEnabledKey = @"YTKACE.Preference.Enabled";
NSString * const YTKACEOLEDKey = @"YTKACE.Preference.Appearance.OLED";
NSString * const YTKACENoAdsKey = @"YTKACE.Preference.Ads.Blocking";
NSString * const YTKACESponsorBlockKey = @"YTKACE.Preference.SponsorBlock.Enabled";
NSString * const YTKACEDownloadKey = @"YTKACE.Preference.Downloads.Enabled";
NSString * const YTKACEBackgroundPlaybackKey = @"YTKACE.Preference.Playback.BackgroundAudio";
NSString * const YTKACEPiPKey = @"YTKACE.Preference.Player.PiP";
NSString * const YTKACESpeedKey = @"YTKACE.Preference.Player.SpeedControls";
NSString * const YTKACELoopKey = @"YTKACE.Preference.Player.Loop";
NSString * const YTKACESleepTimerKey = @"YTKACE.Preference.Player.SleepTimer";
NSString * const YTKACEPreferencesDidChangeNotification =
    @"YTKACEPreferencesDidChangeNotification";

NSString * const YTKACEThemePresetKey = @"YTKACE.Preference.Appearance.ThemePreset";
NSString * const YTKACEThemeCustomBgKey = @"YTKACE.Preference.Appearance.ThemeCustomBg";
NSString * const YTKACEThemeCustomSurfaceKey = @"YTKACE.Preference.Appearance.ThemeCustomSurface";
NSString * const YTKACEAccentPresetKey = @"YTKACE.Preference.Appearance.AccentPreset";
NSString * const YTKACEAccentCustomHexKey = @"YTKACE.Preference.Appearance.AccentCustomHex";
NSString * const YTKACE120HzEnabledKey = @"YTKACE.Preference.Display.120HzEnabled";
NSString * const YTKACE120HzModeKey = @"YTKACE.Preference.Display.120HzMode";
NSString * const YTKACESmoothScrollBoostKey = @"YTKACE.Preference.Display.SmoothScrollBoost";
NSString * const YTKACEPreserveVideoFPSKey = @"YTKACE.Preference.Display.PreserveVideoFPS";
NSString * const YTKACEPreferredCodecKey = @"YTKACE.Preference.Streaming.PreferredCodec";
NSString * const YTKACEHighBitrateBufferBoostKey = @"YTKACE.Preference.Streaming.HighBitrateBufferBoost";

static NSUserDefaults *YTKACEDefaults(void) {
    return NSUserDefaults.standardUserDefaults;
}

static void YTKACEAnnouncePreferenceChange(NSString *key) {
    if (key.length == 0) return;
    if ([key isEqualToString:@"YTKACE.Preference.Language"]) {
        YTKACEResetLocalizationCache();
    }
    if ([key hasPrefix:@"YTKACE.Preference.Appearance.Theme"] ||
        [key hasPrefix:@"YTKACE.Preference.Appearance.Accent"] ||
        [key isEqualToString:YTKACEOLEDKey]) {
        YTKACEClearThemeColorCache();
    }
    void (^post)(void) = ^{
        [NSNotificationCenter.defaultCenter
            postNotificationName:YTKACEPreferencesDidChangeNotification
                          object:nil
                        userInfo:@{@"key": key}];
    };
    if (NSThread.isMainThread) {
        post();
    } else {
        dispatch_async(dispatch_get_main_queue(), post);
    }
}

void YTKACERegisterDefaults(void) {
    id legacyBrightnessSide = [YTKACEDefaults()
        objectForKey:@"YTKACE.Preference.Gestures.BrightnessSide"];
    id legacyVolumeSide = [YTKACEDefaults()
        objectForKey:@"YTKACE.Preference.Gestures.VolumeSide"];
    BOOL hasLeftAction = [YTKACEDefaults()
        objectForKey:@"YTKACE.Preference.Gestures.LeftAction"] != nil;
    BOOL hasRightAction = [YTKACEDefaults()
        objectForKey:@"YTKACE.Preference.Gestures.RightAction"] != nil;
    id legacyDownloadButton = [YTKACEDefaults()
        objectForKey:@"YTKACE.Preference.Downloads.Enabled"];
    BOOL hasPlacement = [YTKACEDefaults()
        objectForKey:@"YTKACE.Preference.Downloads.Placement"] != nil;
    [YTKACEDefaults() registerDefaults:@{
        YTKACEMasterEnabledKey: @YES,
        YTKACENoAdsKey: @YES,
        YTKACEOLEDKey: @NO,
        YTKACEDownloadKey: @NO,
        YTKACEBackgroundPlaybackKey: @YES,
        YTKACEPiPKey: @NO,
        YTKACESpeedKey: @NO,
        YTKACELoopKey: @NO,
        YTKACEThemePresetKey: @0,
        YTKACEThemeCustomBgKey: @"#000000",
        YTKACEThemeCustomSurfaceKey: @"#121212",
        YTKACEAccentPresetKey: @0,
        YTKACEAccentCustomHexKey: @"#FF0000",
        YTKACE120HzEnabledKey: @YES,
        YTKACE120HzModeKey: @0,
        YTKACESmoothScrollBoostKey: @YES,
        YTKACEPreserveVideoFPSKey: @YES,
        YTKACEPreferredCodecKey: @1,
        YTKACEHighBitrateBufferBoostKey: @YES,
        @"YTKACE.Preference.Playback.CustomDoubleTap": @NO,
        @"YTKACE.Preference.Playback.TapToSeek": @NO,
        @"YTKACE.Preference.Sharing.NativeSheet": @NO,
        @"YTKACE.Preference.Playback.OpenPaused": @NO,
        @"YTKACE.Preference.Playback.Transcript": @NO,
        @"YTKACE.Preference.Downloads.Subtitles": @NO,
        @"YTKACE.Preference.Playback.CaptionLanguage": @"",
        @"YTKACE.Preference.Shorts.PinchFullscreen": @NO,
        @"YTKACE.Preference.Shorts.RemixHidden": @NO,
        @"YTKACE.Preference.Shorts.ShareHidden": @NO,
        @"YTKACE.Preference.Shorts.SaveHidden": @NO,
        @"YTKACE.Preference.Downloads.PlaylistEnabled": @NO,
        @"YTKACE.Preference.Downloads.Placement": @0,
        @"YTKACE.Preference.Shorts.CommentsHidden": @NO,
        @"YTKACE.Preference.Shorts.LikeHidden": @NO,
        @"YTKACE.Preference.Shorts.SoundHidden": @NO,
        @"YTKACE.Preference.Shorts.DownloadPosition": @0,
        @"YTKACE.Preference.Overlay.ProductsHidden": @NO,
        @"YTKACE.Preference.Feed.CommunityPostsHidden": @NO,
        @"YTKACE.Preference.Feed.MixesHidden": @NO,
        @"YTKACE.Preference.Feed.PlayablesHidden": @NO,
        @"YTKACE.Preference.Navigation.MessagesHidden": @NO,
        @"YTKACE.Preference.ActionBar.LikeHidden": @NO,
        @"YTKACE.Preference.ActionBar.DislikeHidden": @NO,
        @"YTKACE.Preference.ActionBar.ShareHidden": @NO,
        @"YTKACE.Preference.ActionBar.DownloadHidden": @NO,
        @"YTKACE.Preference.ActionBar.SaveHidden": @NO,
        @"YTKACE.Preference.ActionBar.ClipHidden": @NO,
        @"YTKACE.Preference.ActionBar.RemixHidden": @NO,
        @"YTKACE.Preference.ActionBar.ThanksHidden": @NO,
        @"YTKACE.Preference.ActionBar.HypeHidden": @NO,
        @"YTKACE.Preference.ActionBar.ReportHidden": @NO,
        @"YTKACE.Preference.ActionBar.AskHidden": @NO,
        @"YTKACE.Preference.ActionBar.OverflowHidden": @NO,
        @"YTKACE.Preference.Overlay.FullscreenActionsHidden": @NO,
        @"YTKACE.Preference.Player.HoldSpeedEnabled": @NO,
        @"YTKACE.Preference.Player.HoldSpeedRate": @2.0,
        @"YTKACE.Preference.Gestures.LandscapeOnly": @NO,
        @"YTKACE.Preference.Profiles.Preview": @YES,
        @"YTKACE.Preference.Posts.SaveImage": @YES,
        @"YTKACE.Preference.Downloads.SaveLocation": @0,
        @"YTKACE.Preference.Appearance.LaunchAnimationDisabled": @NO,
        @"YTKACE.Preference.Player.StartRate": @0,
        @"YTKACE.Preference.Player.CustomRate": @1.5,
        @"YTKACE.Preference.Playback.DoubleTapSeconds": @10.0,
        @"YTKACE.Preference.Gestures.HoldSeekSeconds": @10.0,
        @"YTKACE.Preference.Gestures.VolumeSide": @2,
        @"YTKACE.Preference.Gestures.BrightnessSide": @2,
        @"YTKACE.Preference.Gestures.Enabled": @NO,
        @"YTKACE.Preference.Gestures.ActivationArea": @20.0,
        @"YTKACE.Preference.Gestures.LeftAction": @0,
        @"YTKACE.Preference.Gestures.RightAction": @0,
        @"YTKACE.Preference.Gestures.HUDEnabled": @YES,
        @"YTKACE.Preference.Gestures.HUDSize": @1,
        @"YTKACE.Preference.Gestures.HUDPosition": @0,
        @"YTKACE.Preference.Tabs.Startup": @"",
        @"YTKACE.Preference.Shorts.LimitEnabled": @NO,
        @"YTKACE.Preference.Playback.Fix": @NO,
        @"YTKACE.Preference.Shorts.LimitCount": @20,
        @"YTKACE.Preference.Tabs.FrostedHidden": @NO,
        @"YTKACE.Preference.Playback.WiFiQuality": @0,
        @"YTKACE.Preference.Playback.CellularQuality": @0,
        @"YTKACE.Preference.SponsorBlock.Mode": @0,
        @"YTKACE.Preference.SponsorBlock.SkipAlertSeconds": @4.0,
        @"YTKACE.Preference.SponsorBlock.UnskipAlertSeconds": @4.0,
        @"YTKACE.Preference.Downloads.ClearOnStartup": @NO,
        @"YTKACE.Preference.Tabs.Hidden.Create": @YES,
        @"YTKACE.Preference.Tabs.Hidden.Music": @YES,
        @"YTKACE.Preference.Tabs.Hidden.Live": @YES,
        @"YTKACE.Preference.Tabs.Hidden.Gaming": @YES,
        @"YTKACE.Preference.Tabs.Hidden.News": @YES,
        @"YTKACE.Preference.Tabs.Hidden.Posts": @YES,
        @"YTKACE.Preference.Tabs.Hidden.Sports": @YES,
        @"YTKACE.Preference.Tabs.Hidden.Learning": @YES,
        @"YTKACE.Preference.Tabs.Hidden.Fashion": @YES,
        @"YTKACE.Preference.Tabs.Hidden.Playlists": @YES,
        @"YTKACE.Preference.Tabs.Hidden.History": @YES,
        @"YTKACE.Preference.Tabs.Hidden.Notifs": @YES,
        @"YTKACE.Preference.Tabs.Hidden.WatchLater": @YES,
        @"YTKACE.Preference.Tabs.Order": @[@"home", @"shorts", @"subscriptions", @"library", @"ytkace"]
    }];
    if (!hasPlacement && [legacyDownloadButton boolValue]) {
        [YTKACEDefaults() setInteger:1
                              forKey:@"YTKACE.Preference.Downloads.Placement"];
    }
    if ((!hasLeftAction || !hasRightAction) &&
        (legacyBrightnessSide != nil || legacyVolumeSide != nil)) {
        NSInteger brightness = legacyBrightnessSide != nil
            ? [legacyBrightnessSide integerValue] : 2;
        NSInteger volume = legacyVolumeSide != nil
            ? [legacyVolumeSide integerValue] : 2;
        BOOL leftBrightness = brightness == 1;
        BOOL rightBrightness = brightness == 0;
        BOOL leftVolume = volume == 1 || volume == 3;
        BOOL rightVolume = volume == 0 || volume == 3;
        NSInteger leftAction = leftBrightness && leftVolume
            ? 3 : (leftVolume ? 2 : (leftBrightness ? 1 : 0));
        NSInteger rightAction = rightBrightness && rightVolume
            ? 3 : (rightVolume ? 2 : (rightBrightness ? 1 : 0));
        if (!hasLeftAction) {
            [YTKACEDefaults() setInteger:leftAction
                                  forKey:@"YTKACE.Preference.Gestures.LeftAction"];
        }
        if (!hasRightAction) {
            [YTKACEDefaults() setInteger:rightAction
                                   forKey:@"YTKACE.Preference.Gestures.RightAction"];
        }
    }
    [YTKACEDefaults() setBool:YES forKey:YTKACEMasterEnabledKey];
    if ([YTKACEDefaults() objectForKey:@"YTKACE.Preference.Shorts.ProductsHidden"] != nil) {
        if ([YTKACEDefaults() boolForKey:@"YTKACE.Preference.Shorts.ProductsHidden"]) {
            [YTKACEDefaults() setBool:YES
                               forKey:@"YTKACE.Preference.Overlay.ProductsHidden"];
        }
        [YTKACEDefaults() removeObjectForKey:@"YTKACE.Preference.Shorts.ProductsHidden"];
    }
    if ([YTKACEDefaults() boolForKey:@"YTKACE.Preference.Downloads.ClearOnStartup"]) {
        NSDate *lastClear = [YTKACEDefaults() objectForKey:@"YTKACE.Preference.Downloads.LastCacheClear"];
        if (![lastClear isKindOfClass:NSDate.class] ||
            -lastClear.timeIntervalSinceNow >= 86400.0) {
            NSURL *cache = [YTKACEApplicationSupportDirectory()
                URLByAppendingPathComponent:@"Cache"
                                isDirectory:YES];
            [NSFileManager.defaultManager removeItemAtURL:cache error:nil];
            YTKACEPurgeSystemCaches();
            [YTKACEDefaults() setObject:NSDate.date
                                 forKey:@"YTKACE.Preference.Downloads.LastCacheClear"];
        }
    }
    YTKACEPurgeDownloadScratch(NO);
}

NSInteger YTKACEDownloadPlacement(void) {
    return [YTKACEDefaults() integerForKey:@"YTKACE.Preference.Downloads.Placement"];
}

BOOL YTKACEDownloadsEnabled(void) {
    return YTKACEDownloadPlacement() != 0;
}

BOOL YTKACEMasterEnabled(void) {
    return YES;
}

BOOL YTKACEFeatureEnabled(NSString *key) {
    if (!YTKACEMasterEnabled() || key.length == 0) {
        return NO;
    }
    return [YTKACEDefaults() boolForKey:key];
}

static UIColor *s_cachedThemeBg[16] = {nil};
static UIColor *s_cachedThemeSurface[16] = {nil};
static UIColor *s_cachedAccent[16] = {nil};

void YTKACEClearThemeColorCache(void) {
    for (int i = 0; i < 16; i++) {
        s_cachedThemeBg[i] = nil;
        s_cachedThemeSurface[i] = nil;
        s_cachedAccent[i] = nil;
    }
}

UIColor *YTKACEColorFromHex(NSString *hex, UIColor *fallback) {
    if (hex.length == 0) return fallback ?: UIColor.blackColor;
    const char *cStr = hex.UTF8String;
    if (!cStr) return fallback ?: UIColor.blackColor;
    if (*cStr == '#') cStr++;
    if (strlen(cStr) != 6) return fallback ?: UIColor.blackColor;
    char *end = NULL;
    unsigned long rgb = strtoul(cStr, &end, 16);
    if (end == cStr || *end != '\0') return fallback ?: UIColor.blackColor;
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

BOOL YTKACEIsLightMode(UITraitCollection *traits) {
    UIUserInterfaceStyle style = traits ? traits.userInterfaceStyle : UIUserInterfaceStyleUnspecified;
    if (style == UIUserInterfaceStyleUnspecified) {
        if (@available(iOS 13.0, *)) {
            style = UIScreen.mainScreen.traitCollection.userInterfaceStyle;
        }
    }
    return (style == UIUserInterfaceStyleLight);
}

BOOL YTKACEOLEDActive(UITraitCollection *traits) {
    BOOL oledEnabled = YTKACEFeatureEnabled(YTKACEOLEDKey);
    id themeVal = YTKACEPreferenceObject(YTKACEThemePresetKey);
    NSInteger themePreset = [themeVal respondsToSelector:@selector(integerValue)] ? [themeVal integerValue] : 0;
    if (!oledEnabled && themePreset == 0) {
        return NO;
    }
    UITraitCollection *current = traits;
    if (current == nil) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class] ||
                scene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.isKeyWindow) {
                    current = window.traitCollection;
                    break;
                }
            }
            if (current != nil) break;
        }
    }
    current = current ?: UIScreen.mainScreen.traitCollection;
    return current.userInterfaceStyle == UIUserInterfaceStyleDark;
}

UIColor *YTKACEThemeBackgroundColor(UITraitCollection *traits) {
    if (!YTKACEOLEDActive(traits)) {
        return YTKACEInterfaceBackgroundColor(traits);
    }
    id themeVal = YTKACEPreferenceObject(YTKACEThemePresetKey);
    NSInteger preset = [themeVal respondsToSelector:@selector(integerValue)] ? [themeVal integerValue] : 0;
    if (preset == 0 && YTKACEFeatureEnabled(YTKACEOLEDKey)) {
        preset = 1; // Default OLED pure black
    }
    if (preset >= 0 && preset < 16 && s_cachedThemeBg[preset] != nil) {
        return s_cachedThemeBg[preset];
    }
    UIColor *color = nil;
    switch (preset) {
        case 1: // OLED Pure Black
            color = UIColor.blackColor;
            break;
        case 2: // Midnight Navy
            color = [UIColor colorWithRed:8.0/255.0 green:13.0/255.0 blue:26.0/255.0 alpha:1.0];
            break;
        case 3: // Crimson Ember
            color = [UIColor colorWithRed:18.0/255.0 green:5.0/255.0 blue:7.0/255.0 alpha:1.0];
            break;
        case 4: // Amethyst Purple
            color = [UIColor colorWithRed:13.0/255.0 green:7.0/255.0 blue:20.0/255.0 alpha:1.0];
            break;
        case 5: // Emerald Matrix
            color = [UIColor colorWithRed:5.0/255.0 green:17.0/255.0 blue:9.0/255.0 alpha:1.0];
            break;
        case 6: // Cyberpunk Neon
            color = [UIColor colorWithRed:5.0/255.0 green:8.0/255.0 blue:17.0/255.0 alpha:1.0];
            break;
        case 7: // Sunset Orange
            color = [UIColor colorWithRed:20.0/255.0 green:8.0/255.0 blue:11.0/255.0 alpha:1.0];
            break;
        case 8: { // Custom Hex
            NSString *hex = [YTKACEDefaults() stringForKey:YTKACEThemeCustomBgKey];
            color = YTKACEColorFromHex(hex, UIColor.blackColor);
            break;
        }
        default:
            color = UIColor.blackColor;
            break;
    }
    if (preset >= 0 && preset < 16) {
        s_cachedThemeBg[preset] = color;
    }
    return color;
}

UIColor *YTKACEThemeSurfaceColor(UITraitCollection *traits) {
    if (!YTKACEOLEDActive(traits)) {
        return YTKACEInterfaceSurfaceColor(traits);
    }
    id themeVal = YTKACEPreferenceObject(YTKACEThemePresetKey);
    NSInteger preset = [themeVal respondsToSelector:@selector(integerValue)] ? [themeVal integerValue] : 0;
    if (preset == 0 && YTKACEFeatureEnabled(YTKACEOLEDKey)) {
        preset = 1;
    }
    if (preset >= 0 && preset < 16 && s_cachedThemeSurface[preset] != nil) {
        return s_cachedThemeSurface[preset];
    }
    UIColor *color = nil;
    switch (preset) {
        case 1: // OLED Surface
            color = [UIColor colorWithWhite:0.07 alpha:1.0];
            break;
        case 2: // Midnight Navy Surface
            color = [UIColor colorWithRed:16.0/255.0 green:23.0/255.0 blue:42.0/255.0 alpha:1.0];
            break;
        case 3: // Crimson Ember Surface
            color = [UIColor colorWithRed:30.0/255.0 green:12.0/255.0 blue:16.0/255.0 alpha:1.0];
            break;
        case 4: // Amethyst Purple Surface
            color = [UIColor colorWithRed:27.0/255.0 green:15.0/255.0 blue:42.0/255.0 alpha:1.0];
            break;
        case 5: // Emerald Matrix Surface
            color = [UIColor colorWithRed:12.0/255.0 green:32.0/255.0 blue:20.0/255.0 alpha:1.0];
            break;
        case 6: // Cyberpunk Neon Surface
            color = [UIColor colorWithRed:10.0/255.0 green:19.0/255.0 blue:38.0/255.0 alpha:1.0];
            break;
        case 7: // Sunset Orange Surface
            color = [UIColor colorWithRed:36.0/255.0 green:14.0/255.0 blue:20.0/255.0 alpha:1.0];
            break;
        case 8: { // Custom Hex Surface
            NSString *hex = [YTKACEDefaults() stringForKey:YTKACEThemeCustomSurfaceKey];
            color = YTKACEColorFromHex(hex, [UIColor colorWithWhite:0.08 alpha:1.0]);
            break;
        }
        default:
            color = [UIColor colorWithWhite:0.07 alpha:1.0];
            break;
    }
    if (preset >= 0 && preset < 16) {
        s_cachedThemeSurface[preset] = color;
    }
    return color;
}

UIColor *YTKACEInterfaceBackgroundColor(UITraitCollection *traits) {
    if (YTKACEOLEDActive(traits)) return YTKACEThemeBackgroundColor(traits);
    UIUserInterfaceStyle style = traits.userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified) {
        style = UIScreen.mainScreen.traitCollection.userInterfaceStyle;
    }
    return style == UIUserInterfaceStyleDark
        ? [UIColor colorWithWhite:0.075 alpha:1.0]
        : UIColor.whiteColor;
}

UIColor *YTKACEInterfaceSurfaceColor(UITraitCollection *traits) {
    if (YTKACEOLEDActive(traits)) return YTKACEThemeSurfaceColor(traits);
    UIUserInterfaceStyle style = traits.userInterfaceStyle;
    if (style == UIUserInterfaceStyleUnspecified) {
        style = UIScreen.mainScreen.traitCollection.userInterfaceStyle;
    }
    return style == UIUserInterfaceStyleDark
        ? [UIColor colorWithWhite:0.16 alpha:1.0]
        : [UIColor colorWithWhite:0.95 alpha:1.0];
}

UIColor *YTKACEAppAccentColor(void) {
    return YTKACEAppAccentColorForTraits(nil);
}

UIColor *YTKACEAppAccentColorForTraits(UITraitCollection *traits) {
    (void)traits;
    id presetVal = YTKACEPreferenceObject(YTKACEAccentPresetKey);
    NSInteger preset = [presetVal respondsToSelector:@selector(integerValue)] ? [presetVal integerValue] : 0;
    if (preset >= 0 && preset < 16 && s_cachedAccent[preset] != nil) {
        return s_cachedAccent[preset];
    }
    UIColor *color = nil;
    switch (preset) {
        case 1: // Electric Blue
            color = [UIColor colorWithRed:0.23 green:0.51 blue:0.96 alpha:1.0]; // #3B82F6
            break;
        case 2: // Neon Cyan
            color = [UIColor colorWithRed:0.02 green:0.71 blue:0.83 alpha:1.0]; // #06B6D4
            break;
        case 3: // Emerald Green
            color = [UIColor colorWithRed:0.06 green:0.73 blue:0.51 alpha:1.0]; // #10B981
            break;
        case 4: // Amethyst Purple
            color = [UIColor colorWithRed:0.66 green:0.33 blue:0.97 alpha:1.0]; // #A855F7
            break;
        case 5: // Sunset Orange
            color = [UIColor colorWithRed:0.98 green:0.45 blue:0.09 alpha:1.0]; // #F97316
            break;
        case 6: // Hot Pink
            color = [UIColor colorWithRed:0.93 green:0.28 blue:0.60 alpha:1.0]; // #EC4899
            break;
        case 7: // Pure Amber
            color = [UIColor colorWithRed:0.96 green:0.62 blue:0.04 alpha:1.0]; // #F59E0B
            break;
        case 8: { // Custom Hex
            NSString *hex = [YTKACEDefaults() stringForKey:YTKACEAccentCustomHexKey];
            color = YTKACEColorFromHex(hex, [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:1.0]);
            break;
        }
        default: // YouTube Red
            color = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:1.0]; // #FF0000
            break;
    }
    if (preset >= 0 && preset < 16) {
        s_cachedAccent[preset] = color;
    }
    return color;
}

BOOL YTKACE120HzActive(void) {
    return YTKACEFeatureEnabled(YTKACE120HzEnabledKey);
}

BOOL YTKACESponsorBlockEnabled(void) {
    if (!YTKACEMasterEnabled()) {
        return NO;
    }

    return [YTKACEDefaults() boolForKey:YTKACESponsorBlockKey];
}

void YTKACESetPreference(NSString *key, BOOL enabled) {
    if (key.length == 0) {
        return;
    }

    if ([key isEqualToString:YTKACEMasterEnabledKey]) {
        [YTKACEDefaults() setBool:YES forKey:key];
        YTKACEAnnouncePreferenceChange(key);
        return;
    }
    [YTKACEDefaults() setBool:enabled forKey:key];
    YTKACEAnnouncePreferenceChange(key);
}

id YTKACEPreferenceObject(NSString *key) {
    if (key.length == 0) {
        return nil;
    }
    return [YTKACEDefaults() objectForKey:key];
}

void YTKACESetPreferenceObject(NSString *key, id value) {
    if (key.length == 0) {
        return;
    }
    if (value == nil) {
        [YTKACEDefaults() removeObjectForKey:key];
    } else {
        [YTKACEDefaults() setObject:value forKey:key];
    }
    YTKACEAnnouncePreferenceChange(key);
}

static NSString *YTKACERelativeStoragePath(NSURL *URL, NSURL *baseURL) {
    NSString *path = URL.URLByResolvingSymlinksInPath.path.stringByStandardizingPath;
    NSString *base = baseURL.URLByResolvingSymlinksInPath.path.stringByStandardizingPath;
    NSString *prefix = [base stringByAppendingString:@"/"];
    if (![path hasPrefix:prefix]) return nil;
    return [path substringFromIndex:prefix.length];
}

static void YTKACERepairDownloads(NSURL *root) {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *downloads = [root URLByAppendingPathComponent:@"Downloads" isDirectory:YES];
    NSArray<NSURL *> *items = [[manager enumeratorAtURL:downloads
        includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                           options:0 errorHandler:nil] allObjects];
    for (NSURL *source in items) {
        NSNumber *directory = nil;
        [source getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil];
        if (directory.boolValue) continue;
        NSString *relative = YTKACERelativeStoragePath(source, downloads);
        NSArray<NSString *> *components = relative.pathComponents;
        NSUInteger categoryIndex = NSNotFound;
        NSString *category = nil;
        for (NSUInteger index = 0; index < components.count; index++) {
            for (NSString *candidate in @[@"Video", @"Audio", @"Shorts"]) {
                if ([components[index] caseInsensitiveCompare:candidate] == NSOrderedSame) {
                    categoryIndex = index;
                    category = candidate;
                    break;
                }
            }
            if (categoryIndex != NSNotFound) break;
        }
        if (categoryIndex == NSNotFound || categoryIndex + 1 >= components.count) continue;
        NSURL *target = [downloads URLByAppendingPathComponent:category isDirectory:YES];
        for (NSUInteger index = categoryIndex + 1; index < components.count; index++) {
            target = [target URLByAppendingPathComponent:components[index]];
        }
        if ([source.URLByResolvingSymlinksInPath.path
                isEqualToString:target.URLByResolvingSymlinksInPath.path]) continue;
        [manager createDirectoryAtURL:target.URLByDeletingLastPathComponent
          withIntermediateDirectories:YES attributes:nil error:nil];
        if ([manager fileExistsAtPath:target.path]) {
            [manager removeItemAtURL:source error:nil];
        } else {
            [manager moveItemAtURL:source toURL:target error:nil];
        }
    }
    for (NSString *name in @[@"Downloads", @"ownloads"]) {
        [manager removeItemAtURL:[downloads URLByAppendingPathComponent:name isDirectory:YES]
                           error:nil];
    }
}

NSUInteger YTKACEPurgeSystemCaches(void) {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSArray<NSURL *> *roots = [manager URLsForDirectory:NSCachesDirectory
                                             inDomains:NSUserDomainMask];
    NSUInteger freed = 0;
    for (NSURL *root in roots) {
        NSArray<NSURL *> *entries = [manager contentsOfDirectoryAtURL:root
            includingPropertiesForKeys:@[NSURLTotalFileAllocatedSizeKey]
                               options:0 error:nil];
        for (NSURL *entry in entries) {
            NSDirectoryEnumerator *walker = [manager enumeratorAtURL:entry
                includingPropertiesForKeys:@[NSURLTotalFileAllocatedSizeKey]
                                   options:0 errorHandler:nil];
            NSNumber *own = nil;
            [entry getResourceValue:&own forKey:NSURLTotalFileAllocatedSizeKey
                              error:nil];
            freed += own.unsignedIntegerValue;
            for (NSURL *child in walker) {
                NSNumber *size = nil;
                [child getResourceValue:&size
                                 forKey:NSURLTotalFileAllocatedSizeKey error:nil];
                freed += size.unsignedIntegerValue;
            }
            [manager removeItemAtURL:entry error:nil];
        }
    }
    return freed;
}

NSURL *YTKACEApplicationSupportDirectory(void) {
    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *documents = [manager URLsForDirectory:NSDocumentDirectory
                                        inDomains:NSUserDomainMask].firstObject;
    NSURL *directory = [documents URLByAppendingPathComponent:@"YTKACE"
                                                   isDirectory:YES];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURL *support = [manager URLsForDirectory:NSApplicationSupportDirectory
                                         inDomains:NSUserDomainMask].firstObject;
        NSURL *legacy = [support URLByAppendingPathComponent:@"YTKACE"
                                                  isDirectory:YES];
        BOOL targetExists = [manager fileExistsAtPath:directory.path];
        if (!targetExists && [manager fileExistsAtPath:legacy.path]) {
            [manager moveItemAtURL:legacy toURL:directory error:nil];
        }
        [manager createDirectoryAtURL:directory
          withIntermediateDirectories:YES
                           attributes:nil
                                error:nil];
        if ([manager fileExistsAtPath:legacy.path]) {
            NSDirectoryEnumerator<NSURL *> *items = [manager
                enumeratorAtURL:legacy
     includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                        options:0
                   errorHandler:nil];
            for (NSURL *source in items) {
                NSString *relative = YTKACERelativeStoragePath(source, legacy);
                if (relative.length == 0) continue;
                NSURL *destination = [directory URLByAppendingPathComponent:relative];
                NSNumber *isDirectory = nil;
                [source getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
                if (isDirectory.boolValue) {
                    [manager createDirectoryAtURL:destination
                      withIntermediateDirectories:YES attributes:nil error:nil];
                } else if (![manager fileExistsAtPath:destination.path]) {
                    [manager createDirectoryAtURL:destination.URLByDeletingLastPathComponent
                      withIntermediateDirectories:YES attributes:nil error:nil];
                    [manager moveItemAtURL:source toURL:destination error:nil];
                }
            }
            [manager removeItemAtURL:legacy error:nil];
        }
        YTKACERepairDownloads(directory);
    });
    return directory;
}
