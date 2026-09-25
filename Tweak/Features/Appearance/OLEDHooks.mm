#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"
#import "../Interface/NavigationVisibility.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <string.h>

static CFMutableDictionaryRef s_originalHooksMap = NULL;
static IMP OriginalQualitySheetDidAppear;
static IMP OriginalAppTraitChanged;
static IMP OriginalAppStatusBarStyle;
static IMP OriginalPivotBarItemSelect;

static UIColor *s_dynamicThemeBgColor = nil;
static UIColor *s_dynamicThemeSurfaceColor = nil;
static UIColor *s_dynamicAccentColor = nil;

static inline void YTKACERegisterOriginal(SEL selector, IMP implementation) {
    if (s_originalHooksMap != NULL && selector != NULL && implementation != NULL) {
        CFDictionarySetValue(s_originalHooksMap, (const void *)selector, (const void *)implementation);
    }
}

static inline IMP YTKACEGetOriginal(SEL selector) {
    if (s_originalHooksMap == NULL || selector == NULL) return NULL;
    return (IMP)CFDictionaryGetValue(s_originalHooksMap, (const void *)selector);
}

static UIColor *YTKACEOLEDBgColor(id receiver, SEL selector) {
    if (!YTKACEOLEDActive(nil)) {
        IMP original = YTKACEGetOriginal(selector);
        if (original != NULL) {
            return ((id (*)(id, SEL))original)(receiver, selector);
        }
    }
    return s_dynamicThemeBgColor;
}

static UIColor *YTKACEOLEDSurfaceColor(id receiver, SEL selector) {
    if (!YTKACEOLEDActive(nil)) {
        IMP original = YTKACEGetOriginal(selector);
        if (original != NULL) {
            return ((id (*)(id, SEL))original)(receiver, selector);
        }
    }
    return s_dynamicThemeSurfaceColor;
}

static UIColor *YTKACEAccentColorHook(id receiver, SEL selector) {
    id presetVal = YTKACEPreferenceObject(YTKACEAccentPresetKey);
    NSInteger preset = [presetVal respondsToSelector:@selector(integerValue)] ? [presetVal integerValue] : 0;
    if (preset > 0) {
        return s_dynamicAccentColor;
    }
    IMP original = YTKACEGetOriginal(selector);
    return original == NULL ? YTKACEAppAccentColor() : ((id (*)(id, SEL))original)(receiver, selector);
}

static void YTKACERefreshStatusBars(UIViewController *controller) {
    if (controller == nil) return;
    [controller setNeedsStatusBarAppearanceUpdate];
    if ([controller isKindOfClass:UINavigationController.class]) {
        YTKACERefreshStatusBars(((UINavigationController *)controller).visibleViewController);
    } else if ([controller isKindOfClass:UITabBarController.class]) {
        YTKACERefreshStatusBars(((UITabBarController *)controller).selectedViewController);
    }
    YTKACERefreshStatusBars(controller.presentedViewController);
}

static NSInteger YTKACEAppStatusBarStyle(UIViewController *receiver,
                                         SEL selector) {
    NSInteger original = OriginalAppStatusBarStyle == NULL
        ? UIStatusBarStyleDefault
        : ((NSInteger (*)(id, SEL))OriginalAppStatusBarStyle)(receiver, selector);
    if (!YTKACEOLEDActive(receiver.traitCollection)) return original;
    UIUserInterfaceStyle style = receiver.traitCollection.userInterfaceStyle;
    return style == UIUserInterfaceStyleDark
        ? UIStatusBarStyleLightContent
        : UIStatusBarStyleDarkContent;
}

static void YTKACERefreshAllThemeViews(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class] ||
                scene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                YTKACERefreshStatusBars(window.rootViewController);
                [window setNeedsLayout];
            }
        }
        YTKACERefreshNavigationAppearance();
    });
}

static void YTKACEAppTraitChanged(UIViewController *receiver,
                                  SEL selector,
                                  UITraitCollection *previous) {
    if (OriginalAppTraitChanged != NULL) {
        ((void (*)(id, SEL, id))OriginalAppTraitChanged)(receiver, selector, previous);
    }
    if (previous != nil &&
        ![receiver.traitCollection
            hasDifferentColorAppearanceComparedToTraitCollection:previous]) return;
    if (!YTKACEOLEDActive(receiver.traitCollection)) return;
    [receiver setNeedsStatusBarAppearanceUpdate];
    [receiver.view setNeedsLayout];
    YTKACERefreshNavigationAppearance();
}

static void YTKACEInstallColorHook(NSString *className,
                                   NSString *selectorName,
                                   BOOL classMethod,
                                   BOOL isSurface) {
    SEL selector = NSSelectorFromString(selectorName);
    IMP replacement = isSurface ? (IMP)YTKACEOLEDSurfaceColor : (IMP)YTKACEOLEDBgColor;
    IMP original = NULL;
    BOOL installed = classMethod
        ? YTKACEInstallClassHook(className, selectorName, replacement, &original)
        : YTKACEInstallInstanceHook(className, selectorName, replacement, &original);
    if (installed && original != NULL) {
        YTKACERegisterOriginal(selector, original);
    }
}

static void YTKACEInstallAccentHook(NSString *className,
                                    NSString *selectorName,
                                    BOOL classMethod) {
    SEL selector = NSSelectorFromString(selectorName);
    IMP original = NULL;
    BOOL installed = classMethod
        ? YTKACEInstallClassHook(className, selectorName, (IMP)YTKACEAccentColorHook, &original)
        : YTKACEInstallInstanceHook(className, selectorName, (IMP)YTKACEAccentColorHook, &original);
    if (installed && original != NULL) {
        YTKACERegisterOriginal(selector, original);
    }
}

static void YTKACECollectQualityLabelsFast(UIView *view,
                                           NSMutableArray<UILabel *> *labels,
                                           NSRegularExpression *pattern) {
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        NSString *text = label.text ?: @"";
        if ([text containsString:@"p"] || [text localizedCaseInsensitiveContainsString:@"quality"]) {
            if ([text localizedCaseInsensitiveContainsString:@"quality"] ||
                [pattern firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] != nil) {
                [labels addObject:label];
            }
        }
    }
    for (UIView *child in view.subviews) {
        YTKACECollectQualityLabelsFast(child, labels, pattern);
    }
}

static void YTKACEBlackenQualitySurface(UIView *view) {
    UIColor *surfaceColor = YTKACEThemeSurfaceColor(view.traitCollection);
    if ([view isKindOfClass:UIVisualEffectView.class]) {
        UIVisualEffectView *effect = (UIVisualEffectView *)view;
        effect.effect = nil;
        effect.contentView.backgroundColor = surfaceColor;
    }
    UIColor *background = view.backgroundColor;
    CGFloat alpha = background == nil ? 0.0 : CGColorGetAlpha(background.CGColor);
    if (alpha > 0.01 || [view isKindOfClass:UITableView.class] ||
        [view isKindOfClass:UICollectionView.class]) {
        view.backgroundColor = surfaceColor;
    }
    if ([view isKindOfClass:UILabel.class]) {
        ((UILabel *)view).textColor = UIColor.whiteColor;
    }
    for (UIView *child in view.subviews) {
        YTKACEBlackenQualitySurface(child);
    }
}

static void YTKACEQualitySheetDidAppear(id receiver, SEL selector, BOOL animated) {
    if (OriginalQualitySheetDidAppear != NULL) {
        ((void (*)(id, SEL, BOOL))OriginalQualitySheetDidAppear)(
            receiver, selector, animated);
    }
    if (![receiver isKindOfClass:UIViewController.class] ||
        !YTKACEOLEDActive(((UIViewController *)receiver).traitCollection)) return;
    UIView *root = ((UIViewController *)receiver).view;
    dispatch_async(dispatch_get_main_queue(), ^{
        static NSRegularExpression *qualityPattern;
        static dispatch_once_t patToken;
        dispatch_once(&patToken, ^{
            qualityPattern = [NSRegularExpression
                regularExpressionWithPattern:@"^\\s*\\d{3,4}p(?:60)?" options:0 error:nil];
        });
        NSMutableArray<UILabel *> *labels = [NSMutableArray array];
        YTKACECollectQualityLabelsFast(root, labels, qualityPattern);
        NSUInteger qualityRows = 0;
        for (UILabel *label in labels) {
            if ([label.text rangeOfString:@"p"].location != NSNotFound) qualityRows++;
        }
        if (qualityRows < 2) return;
        UIView *container = labels.firstObject.superview;
        while (container != nil && container != root &&
               ![container isKindOfClass:UITableView.class] &&
               ![container isKindOfClass:UICollectionView.class] &&
               ![container isKindOfClass:UIScrollView.class]) {
            container = container.superview;
        }
        UIView *surface = container ?: root;
        surface.backgroundColor = YTKACEThemeSurfaceColor(root.traitCollection);
        YTKACEBlackenQualitySurface(surface);
    });
}

static void YTKACEPivotBarItemSetSelected(UIView *receiver, SEL selector, BOOL selected) {
    if (OriginalPivotBarItemSelect != NULL) {
        ((void (*)(id, SEL, BOOL))OriginalPivotBarItemSelect)(receiver, selector, selected);
    }
    id presetVal = YTKACEPreferenceObject(YTKACEAccentPresetKey);
    NSInteger preset = [presetVal respondsToSelector:@selector(integerValue)] ? [presetVal integerValue] : 0;
    if (selected && preset > 0) {
        receiver.tintColor = YTKACEAppAccentColor();
    }
}

void YTKACEInstallOLEDHooks(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_originalHooksMap = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, NULL, NULL);

        s_dynamicThemeBgColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            if (YTKACEOLEDActive(traits)) {
                return YTKACEThemeBackgroundColor(traits);
            }
            return YTKACEInterfaceBackgroundColor(traits);
        }];

        s_dynamicThemeSurfaceColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            if (YTKACEOLEDActive(traits)) {
                return YTKACEThemeSurfaceColor(traits);
            }
            return YTKACEInterfaceSurfaceColor(traits);
        }];

        s_dynamicAccentColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return YTKACEAppAccentColorForTraits(traits);
        }];

        [NSNotificationCenter.defaultCenter
            addObserverForName:YTKACEPreferencesDidChangeNotification
                        object:nil
                         queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *note) {
            NSString *key = note.userInfo[@"key"];
            if ([key hasPrefix:@"YTKACE.Preference.Appearance"] ||
                [key isEqualToString:YTKACEOLEDKey]) {
                YTKACERefreshAllThemeViews();
            }
        }];
    });

    for (NSString *selector in @[@"black0", @"black1", @"black2", @"black3", @"black4"]) {
        YTKACEInstallColorHook(@"YTColor", selector, YES, NO);
    }

    NSArray<NSString *> *bgPaletteSelectors = @[
        @"baseBackground",
        @"brandBackgroundPrimary",
        @"brandBackgroundSecondary",
        @"brandBackgroundSolid",
        @"brandSurfaceContainer",
        @"brandSurfaceContainerHigh",
        @"brandSurfaceContainerHighest",
        @"raisedBackground",
        @"staticBrandBlack",
        @"generalBackgroundA",
        @"generalBackgroundB",
        @"generalBackgroundC"
    ];
    for (NSString *selector in bgPaletteSelectors) {
        YTKACEInstallColorHook(@"YTCommonColorPalette", selector, NO, NO);
        YTKACEInstallColorHook(@"YTCommonColorPalette", selector, YES, NO);
    }

    NSArray<NSString *> *surfacePaletteSelectors = @[
        @"menuBackground",
        @"dialogBackgroundColor",
        @"elevatedBackgroundColor"
    ];
    for (NSString *selector in surfacePaletteSelectors) {
        YTKACEInstallColorHook(@"YTCommonColorPalette", selector, NO, YES);
        YTKACEInstallColorHook(@"YTCommonColorPalette", selector, YES, YES);
    }

    // Accent color hooks
    NSArray<NSString *> *accentSelectors = @[
        @"staticBrandRed",
        @"brandRed",
        @"brandPrimary",
        @"callToAction",
        @"callToActionInverse",
        @"badgeSelected"
    ];
    for (NSString *selector in accentSelectors) {
        YTKACEInstallAccentHook(@"YTColor", selector, YES);
        YTKACEInstallAccentHook(@"YTCommonColorPalette", selector, NO);
        YTKACEInstallAccentHook(@"YTCommonColorPalette", selector, YES);
    }

    YTKACEInstallInstanceHook(@"YTPivotBarItemView",
                              @"setSelected:",
                              (IMP)YTKACEPivotBarItemSetSelected,
                              &OriginalPivotBarItemSelect);

    YTKACEInstallInstanceHook(@"YTActionSheetDialogViewController",
                              @"viewDidAppear:",
                              (IMP)YTKACEQualitySheetDidAppear,
                              &OriginalQualitySheetDidAppear);
    YTKACEInstallInstanceHook(@"YTAppViewController",
                              @"traitCollectionDidChange:",
                              (IMP)YTKACEAppTraitChanged,
                              &OriginalAppTraitChanged);
    YTKACEInstallInstanceHook(@"YTAppViewController",
                              @"preferredStatusBarStyle",
                              (IMP)YTKACEAppStatusBarStyle,
                              &OriginalAppStatusBarStyle);
}
