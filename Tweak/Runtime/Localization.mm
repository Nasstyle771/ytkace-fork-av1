#import "Localization.h"
#import "Preferences.h"
#import "../UI/Assets.h"

#import <UIKit/UIKit.h>

NSString * const YTKACELanguageKey = @"YTKACE.Preference.Language";

NSArray<NSString *> *YTKACEAvailableLanguages(void) {
    return @[@"system", @"en", @"ar", @"ckb", @"de", @"es", @"fr", @"it",
             @"ja", @"ko", @"pl", @"ru", @"tr", @"vi", @"zh-Hans", @"zh-Hant"];
}

NSString *YTKACELanguageDisplayName(NSString *code) {
    if ([code isEqualToString:@"system"]) return @"System";
    static NSDictionary<NSString *, NSString *> *names;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = @{
            @"en": @"English",
            @"ar": @"العربية",
            @"ckb": @"کوردی",
            @"de": @"Deutsch",
            @"es": @"Español",
            @"fr": @"Français",
            @"it": @"Italiano",
            @"ja": @"日本語",
            @"ko": @"한국어",
            @"pl": @"Polski",
            @"ru": @"Русский",
            @"tr": @"Türkçe",
            @"vi": @"Tiếng Việt",
            @"zh-Hans": @"简体中文",
            @"zh-Hant": @"繁體中文"
        };
    });
    return names[code] ?: code;
}

static NSString *YTKACEPreferredLanguage(void) {
    id stored = YTKACEPreferenceObject(YTKACELanguageKey);
    NSString *choice = [stored isKindOfClass:NSString.class] ? stored : @"system";
    if (![choice isEqualToString:@"system"]) return choice;

    NSArray<NSString *> *available = YTKACEAvailableLanguages();
    for (NSString *preferred in NSLocale.preferredLanguages) {
        NSString *code = preferred;
        if ([code hasPrefix:@"zh-Hans"] || [code hasPrefix:@"zh-CN"] ||
            [code hasPrefix:@"zh-SG"]) {
            return @"zh-Hans";
        }
        if ([code hasPrefix:@"zh"]) return @"zh-Hant";
        NSRange separator = [code rangeOfString:@"-"];
        if (separator.location != NSNotFound) {
            code = [code substringToIndex:separator.location];
        }
        if ([available containsObject:code]) return code;
    }
    return @"en";
}

static NSDictionary<NSString *, NSString *> *YTKACEStringsForLanguage(NSString *code) {
    NSBundle *bundle = YTKACEAssetsBundle();
    if (bundle == nil) return nil;
    NSString *path = [bundle pathForResource:@"Localizable"
                                      ofType:@"strings"
                                 inDirectory:nil
                             forLocalization:code];
    if (path == nil) {
        path = [bundle.resourcePath stringByAppendingPathComponent:
            [NSString stringWithFormat:@"%@.lproj/Localizable.strings", code]];
    }
    return [NSDictionary dictionaryWithContentsOfFile:path];
}

#include <os/lock.h>

static os_unfair_lock s_locLock = OS_UNFAIR_LOCK_INIT;
static NSDictionary<NSString *, NSString *> *YTKACEActiveStrings = nil;
static NSDictionary<NSString *, NSString *> *s_englishStrings = nil;
static NSString *YTKACEActiveLanguage = nil;

void YTKACEResetLocalizationCache(void) {
    os_unfair_lock_lock(&s_locLock);
    YTKACEActiveStrings = nil;
    YTKACEActiveLanguage = nil;
    os_unfair_lock_unlock(&s_locLock);
}

NSString *YTKACELocalized(NSString *key) {
    if (key.length == 0) return key;

    NSString *language = YTKACEPreferredLanguage();
    NSDictionary<NSString *, NSString *> *strings = nil;
    NSDictionary<NSString *, NSString *> *fallbackStrings = nil;

    os_unfair_lock_lock(&s_locLock);
    if (![language isEqualToString:YTKACEActiveLanguage] || YTKACEActiveStrings == nil) {
        YTKACEActiveLanguage = [language copy];
        YTKACEActiveStrings = YTKACEStringsForLanguage(language);
    }
    strings = YTKACEActiveStrings;
    if (s_englishStrings == nil) {
        s_englishStrings = YTKACEStringsForLanguage(@"en");
    }
    fallbackStrings = s_englishStrings;
    os_unfair_lock_unlock(&s_locLock);

    NSString *value = strings ? strings[key] : nil;
    if (value.length != 0) return value;

    if (fallbackStrings != nil && fallbackStrings != strings) {
        NSString *fallback = fallbackStrings[key];
        if (fallback.length != 0) return fallback;
    }

    return key;
}
