#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"
#import "../Interface/NavigationVisibility.h"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <string.h>

static NSMutableDictionary<NSString *, NSValue *> *YTKACEOLEDOriginals;
static IMP OriginalQualitySheetDidAppear;
static IMP OriginalAppTraitChanged;
static IMP OriginalAppStatusBarStyle;
static IMP OriginalPivotBarItemSelect;

static NSValue *YTKACEOLEDValue(IMP implementation) {
    return [NSValue value:&implementation withObjCType:@encode(IMP)];
}

static IMP YTKACEOLEDImplementation(NSValue *value) {
    IMP implementation = NULL;
    [value getValue:&implementation];
    return implementation;
}

static NSString *YTKACEOLEDOriginalKey(id receiver, SEL selector) {
    BOOL classMethod = object_isClass(receiver);
    Class cls = classMethod ? receiver : [receiver class];
    return [NSString stringWithFormat:@"%@|%@|%@",
            classMethod ? @"+" : @"-",
            NSStringFromClass(cls),
            NSStringFromSelector(selector)];
}

static BOOL YTKACEIsSurfaceSelector(SEL selector) {
    const char *name = sel_getName(selector);
    if (name == NULL) return NO;
    return (strstr(name, "menu") != NULL ||
            strstr(name, "dialog") != NULL ||
            strstr(name, "elevated") != NULL ||
            strstr(name, "raised") != NULL ||
            strstr(name, "Surface") != NULL ||
            strstr(name, "Container") != NULL ||
            strstr(name, "chip") != NULL ||
            strstr(name, "overlay") != NULL ||
            strstr(name, "Secondary") != NULL ||
            strstr(name, "background2") != NULL ||
            strstr(name, "background3") != NULL);
}

static UIColor *YTKACEOLEDColor(id receiver, SEL selector) {
    IMP original = YTKACEOLEDImplementation(
        YTKACEOLEDOriginals[YTKACEOLEDOriginalKey(receiver, selector)]
    );
    UIColor *base = original == NULL
        ? nil
        : ((id (*)(id, SEL))original)(receiver, selector);
    if (!YTKACEOLEDActive(nil)) return base;
    __weak id weakReceiver = receiver;
    BOOL isSurface = YTKACEIsSurfaceSelector(selector);
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        if (YTKACEOLEDActive(traits)) {
            return isSurface ? YTKACEThemeSurfaceColor(traits) : YTKACEThemeBackgroundColor(traits);
        }
        id target = weakReceiver;
        UIColor *current = target == nil || original == NULL
            ? base
            : ((id (*)(id, SEL))original)(target, selector);
        return current == nil ? [UIColor.systemBackgroundColor
            resolvedColorWithTraitCollection:traits]
            : [current resolvedColorWithTraitCollection:traits];
    }];
}

static UIColor *YTKACEAccentColorHook(id receiver, SEL selector) {
    id presetVal = YTKACEPreferenceObject(YTKACEAccentPresetKey);
    NSInteger preset = [presetVal respondsToSelector:@selector(integerValue)] ? [presetVal integerValue] : 0;
    if (preset > 0) {
        return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            return YTKACEAppAccentColorForTraits(traits);
        }];
    }
    IMP original = YTKACEOLEDImplementation(
        YTKACEOLEDOriginals[YTKACEOLEDOriginalKey(receiver, selector)]
    );
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
    NSInteger result = style == UIUserInterfaceStyleDark
        ? UIStatusBarStyleLightContent
        : UIStatusBarStyleDarkContent;
    return result;
}

static void YTKACERefreshAllThemeViews(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class] ||
                scene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                YTKACERefreshStatusBars(window.rootViewController);
                [window setNeedsLayout];
                [window layoutIfNeeded];
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
    YTKACERefreshAllThemeViews();
}

static void YTKACEInstallColorHook(NSString *className,
                                   NSString *selectorName,
                                   BOOL classMethod) {
    IMP original = NULL;
    BOOL installed = classMethod
        ? YTKACEInstallClassHook(className,
                                selectorName,
                                (IMP)YTKACEOLEDColor,
                                &original)
        : YTKACEInstallInstanceHook(className,
                                   selectorName,
                                   (IMP)YTKACEOLEDColor,
                                   &original);
    if (!installed || original == NULL) {
        return;
    }
    NSString *key = [NSString stringWithFormat:@"%@|%@|%@",
                     classMethod ? @"+" : @"-",
                     className,
                     selectorName];
    if (YTKACEOLEDOriginals[key] == nil) {
        YTKACEOLEDOriginals[key] = YTKACEOLEDValue(original);
    }
}

static void YTKACEInstallAccentHook(NSString *className,
                                    NSString *selectorName,
                                    BOOL classMethod) {
    IMP original = NULL;
    BOOL installed = classMethod
        ? YTKACEInstallClassHook(className,
                                selectorName,
                                (IMP)YTKACEAccentColorHook,
                                &original)
        : YTKACEInstallInstanceHook(className,
                                   selectorName,
                                   (IMP)YTKACEAccentColorHook,
                                   &original);
    if (!installed || original == NULL) {
        return;
    }
    NSString *key = [NSString stringWithFormat:@"%@|%@|%@",
                     classMethod ? @"+" : @"-",
                     className,
                     selectorName];
    if (YTKACEOLEDOriginals[key] == nil) {
        YTKACEOLEDOriginals[key] = YTKACEOLEDValue(original);
    }
}

static void YTKACECollectQualityLabels(UIView *view,
                                       NSMutableArray<UILabel *> *labels) {
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        NSString *text = label.text ?: @"";
        NSRegularExpression *pattern = [NSRegularExpression
            regularExpressionWithPattern:@"^\\s*\\d{3,4}p(?:60)?" options:0 error:nil];
        if ([text localizedCaseInsensitiveContainsString:@"quality"] ||
            [pattern firstMatchInString:text options:0
                range:NSMakeRange(0, text.length)] != nil) {
            [labels addObject:label];
        }
    }
    for (UIView *child in view.subviews) {
        YTKACECollectQualityLabels(child, labels);
    }
}

static UIView *YTKACECommonAncestor(NSArray<UIView *> *views, UIView *limit) {
    UIView *candidate = views.firstObject;
    while (candidate != nil && candidate != limit.superview) {
        BOOL containsAll = YES;
        for (UIView *view in views) {
            if (view != candidate && ![view isDescendantOfView:candidate]) {
                containsAll = NO;
                break;
            }
        }
        if (containsAll) return candidate;
        candidate = candidate.superview;
    }
    return nil;
}

static void YTKACEBlackenQualitySurface(UIView *view) {
    UIColor *surfaceColor = YTKACEThemeSurfaceColor(view.traitCollection);
    UIColor *bgColor = YTKACEThemeBackgroundColor(view.traitCollection);
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
        NSMutableArray<UILabel *> *labels = [NSMutableArray array];
        YTKACECollectQualityLabels(root, labels);
        NSUInteger qualityRows = 0;
        for (UILabel *label in labels) {
            if ([label.text rangeOfString:@"p"].location != NSNotFound) qualityRows++;
        }
        if (qualityRows < 2) return;
        UIView *surface = YTKACECommonAncestor(labels, root);
        if (surface == nil || surface == root) {
            for (UIView *child in root.subviews) {
                NSUInteger count = 0;
                for (UILabel *label in labels) {
                    if ([label isDescendantOfView:child]) count++;
                }
                if (count == labels.count) {
                    surface = child;
                    break;
                }
            }
        }
        if (surface != nil && surface != root) {
            surface.backgroundColor = YTKACEThemeSurfaceColor(root.traitCollection);
            YTKACEBlackenQualitySurface(surface);
        }
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
        YTKACEOLEDOriginals = [NSMutableDictionary dictionary];

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
        YTKACEInstallColorHook(@"YTColor", selector, YES);
    }

    NSArray<NSString *> *paletteSelectors = @[
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
        @"generalBackgroundC",
        @"menuBackground",
        @"dialogBackgroundColor",
        @"elevatedBackgroundColor"
    ];
    for (NSString *selector in paletteSelectors) {
        YTKACEInstallColorHook(@"YTCommonColorPalette", selector, NO);
        YTKACEInstallColorHook(@"YTCommonColorPalette", selector, YES);
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
