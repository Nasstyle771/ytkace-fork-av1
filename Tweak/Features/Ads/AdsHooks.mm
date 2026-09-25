#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <os/lock.h>

static IMP OriginalShouldBlockUpgradeDialog;
static IMP OriginalAdShieldSignals;
static IMP OriginalAdShieldSignalsWithoutIDFA;
static IMP OriginalDataSignals;
static IMP OriginalDataSignalsWithoutIDFA;
static IMP OriginalAdsDecorateContext;
static IMP OriginalAccountAdsDecorateContext;
static IMP OriginalPlayerAdsArray;
static IMP OriginalAdSlotsArray;
static IMP OriginalAdPlacementsArray;
static IMP OriginalAdBreakParams;
static IMP OriginalAdNextParams;
static IMP OriginalAdParams;
static IMP OriginalEnableSkippableAd;
static IMP OriginalMDXSessionImplAdPlaying;
static IMP OriginalMDXSessionAdPlaying;
static IMP OriginalIsPlayingAd;
static IMP OriginalIsPlayingAdSurvey;
static IMP OriginalIsPlayingAdIntro;
static IMP OriginalCreateAdsPlaybackCoordinator;
static IMP OriginalReelContentModel;
static IMP OriginalInfiniteReelContentModel;
static IMP OriginalReelShouldDisplay;
static IMP OriginalCompanionAd;
static IMP OriginalHasCompanionAdRenderer;
static IMP OriginalHasAppPromoCompanionAdRenderer;
static IMP OriginalHasShoppingCompanionAdRenderer;
static IMP OriginalElementContentsArray;
static IMP OriginalItemSectionContentsArray;
static IMP OriginalAdCellLayout;
static IMP OriginalAdCellReuse;
static NSMutableDictionary<NSString *, NSValue *> *YTKACEPromotedSizeOriginals;
static IMP OriginalVideoNodeSetEntry;
static IMP OriginalVideoNodeHeight;
static IMP OriginalVideoNodeSize;
static IMP OriginalVideoNodeShrink;
static const void *YTKACEAdNodeAssociation = &YTKACEAdNodeAssociation;
static const void *YTKACEAdMatchAssociation = &YTKACEAdMatchAssociation;
static const void *YTKACEAdEmptyAssociation = &YTKACEAdEmptyAssociation;

static id YTKACECallObjectGetter(IMP implementation, id receiver, SEL selector) {
    return implementation == NULL
        ? nil
        : ((id (*)(id, SEL))implementation)(receiver, selector);
}

static BOOL YTKACECallBooleanGetter(IMP implementation, id receiver, SEL selector) {
    return implementation != NULL &&
        ((BOOL (*)(id, SEL))implementation)(receiver, selector);
}

static BOOL YTKACEShouldBlockUpgradeDialog(id receiver, SEL selector) {
    return YTKACEFeatureEnabled(YTKACENoAdsKey)
        ? YES
        : YTKACECallBooleanGetter(OriginalShouldBlockUpgradeDialog, receiver, selector);
}

static id YTKACEEmptyDictionary(IMP original, id receiver, SEL selector) {
    return YTKACEFeatureEnabled(YTKACENoAdsKey)
        ? @{}
        : YTKACECallObjectGetter(original, receiver, selector);
}

static id YTKACEAdShieldSignals(id receiver, SEL selector) {
    return YTKACEEmptyDictionary(OriginalAdShieldSignals, receiver, selector);
}

static id YTKACEAdShieldSignalsWithoutIDFA(id receiver, SEL selector) {
    return YTKACEEmptyDictionary(OriginalAdShieldSignalsWithoutIDFA, receiver, selector);
}

static id YTKACEDataSignals(id receiver, SEL selector) {
    return YTKACEEmptyDictionary(OriginalDataSignals, receiver, selector);
}

static id YTKACEDataSignalsWithoutIDFA(id receiver, SEL selector) {
    return YTKACEEmptyDictionary(OriginalDataSignalsWithoutIDFA, receiver, selector);
}

static void YTKACEAdsDecorateContext(id receiver, SEL selector, id context) {
    if (!YTKACEFeatureEnabled(YTKACENoAdsKey) && OriginalAdsDecorateContext != NULL) {
        ((void (*)(id, SEL, id))OriginalAdsDecorateContext)(receiver, selector, context);
    }
}

static void YTKACEAccountAdsDecorateContext(id receiver, SEL selector, id context) {
    if (!YTKACEFeatureEnabled(YTKACENoAdsKey) &&
        OriginalAccountAdsDecorateContext != NULL) {
        ((void (*)(id, SEL, id))OriginalAccountAdsDecorateContext)(
            receiver,
            selector,
            context
        );
    }
}

static id YTKACEPlayerAdsArray(id receiver, SEL selector) {
    return YTKACEFeatureEnabled(YTKACENoAdsKey)
        ? [NSMutableArray array]
        : YTKACECallObjectGetter(OriginalPlayerAdsArray, receiver, selector);
}

static id YTKACEAdSlotsArray(id receiver, SEL selector) {
    return YTKACEFeatureEnabled(YTKACENoAdsKey)
        ? [NSMutableArray array]
        : YTKACECallObjectGetter(OriginalAdSlotsArray, receiver, selector);
}

static id YTKACEAdPlacementsArray(id receiver, SEL selector) {
    return YTKACEFeatureEnabled(YTKACENoAdsKey)
        ? [NSMutableArray array]
        : YTKACECallObjectGetter(OriginalAdPlacementsArray, receiver, selector);
}

static id YTKACENilParameter(IMP original, id receiver, SEL selector) {
    return YTKACEFeatureEnabled(YTKACENoAdsKey)
        ? nil
        : YTKACECallObjectGetter(original, receiver, selector);
}

static id YTKACEAdBreakParams(id receiver, SEL selector) {
    return YTKACENilParameter(OriginalAdBreakParams, receiver, selector);
}

static id YTKACEAdNextParams(id receiver, SEL selector) {
    return YTKACENilParameter(OriginalAdNextParams, receiver, selector);
}

static id YTKACEAdParams(id receiver, SEL selector) {
    return YTKACENilParameter(OriginalAdParams, receiver, selector);
}

static BOOL YTKACEEnableSkippableAd(id receiver, SEL selector) {
    return YTKACEFeatureEnabled(YTKACENoAdsKey)
        ? YES
        : YTKACECallBooleanGetter(OriginalEnableSkippableAd, receiver, selector);
}

static void YTKACEMDXSessionImplAdPlaying(id receiver,
                                          SEL selector,
                                          uintptr_t value) {
    if (!YTKACEFeatureEnabled(YTKACENoAdsKey) &&
        OriginalMDXSessionImplAdPlaying != NULL) {
        ((void (*)(id, SEL, uintptr_t))OriginalMDXSessionImplAdPlaying)(
            receiver,
            selector,
            value
        );
    }
}

static void YTKACEMDXSessionAdPlaying(id receiver,
                                      SEL selector,
                                      uintptr_t value) {
    if (!YTKACEFeatureEnabled(YTKACENoAdsKey) && OriginalMDXSessionAdPlaying != NULL) {
        ((void (*)(id, SEL, uintptr_t))OriginalMDXSessionAdPlaying)(
            receiver,
            selector,
            value
        );
    }
}

static BOOL YTKACENotPlayingAd(IMP original, id receiver, SEL selector) {
    return YTKACEFeatureEnabled(YTKACENoAdsKey)
        ? NO
        : YTKACECallBooleanGetter(original, receiver, selector);
}

static BOOL YTKACEIsPlayingAd(id receiver, SEL selector) {
    return YTKACENotPlayingAd(OriginalIsPlayingAd, receiver, selector);
}

static BOOL YTKACEIsPlayingAdSurvey(id receiver, SEL selector) {
    return YTKACENotPlayingAd(OriginalIsPlayingAdSurvey, receiver, selector);
}

static BOOL YTKACEIsPlayingAdIntro(id receiver, SEL selector) {
    return YTKACENotPlayingAd(OriginalIsPlayingAdIntro, receiver, selector);
}

static id YTKACENoAdsPlaybackCoordinator(id receiver, SEL selector) {
    id coordinator = YTKACECallObjectGetter(
        OriginalCreateAdsPlaybackCoordinator,
        receiver,
        selector
    );
    return YTKACEFeatureEnabled(YTKACENoAdsKey) ? nil : coordinator;
}

static id YTKACEFilterReelModel(IMP original,
                                id receiver,
                                SEL selector,
                                id entry) {
    if (original == NULL) {
        return nil;
    }
    id model = ((id (*)(id, SEL, id))original)(receiver, selector, entry);
    if (!YTKACEFeatureEnabled(YTKACENoAdsKey) || model == nil) {
        return model;
    }
    SEL videoTypeSelector = NSSelectorFromString(@"videoType");
    if (![model respondsToSelector:videoTypeSelector]) {
        return model;
    }
    NSInteger videoType = ((NSInteger (*)(id, SEL))objc_msgSend)(
        model,
        videoTypeSelector
    );
    return videoType == 3 ? nil : model;
}

static id YTKACEReelContentModel(id receiver, SEL selector, id entry) {
    return YTKACEFilterReelModel(
        OriginalReelContentModel,
        receiver,
        selector,
        entry
    );
}

static id YTKACEInfiniteReelContentModel(id receiver, SEL selector, id entry) {
    return YTKACEFilterReelModel(
        OriginalInfiniteReelContentModel,
        receiver,
        selector,
        entry
    );
}

static id YTKACEObjectValue(id object, NSString *selectorName) {
    if (object == nil) return nil;
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) return nil;
    @try {
        return ((id (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static BOOL YTKACEObjectBool(id object, NSString *selectorName) {
    if (object == nil) return NO;
    SEL selector = NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) return NO;
    @try {
        return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

static BOOL YTKACEReelObjectLooksLikeAd(id object, NSUInteger depth) {
    if (object == nil || depth > 3) return NO;

    Class cls = object_getClass(object);
    if (cls != Nil) {
        const char *cName = class_getName(cls);
        if (cName != NULL &&
            (strcasestr(cName, "nonvideoad") ||
             strcasestr(cName, "reelad") ||
             strcasestr(cName, "adselection") ||
             strcasestr(cName, "miniappad"))) {
            return YES;
        }
    }

    static SEL s_reelBoolSels[4];
    static dispatch_once_t onceReelBools;
    dispatch_once(&onceReelBools, ^{
        s_reelBoolSels[0] = sel_registerName("isAd");
        s_reelBoolSels[1] = sel_registerName("isAdVideo");
        s_reelBoolSels[2] = sel_registerName("isVideoAd");
        s_reelBoolSels[3] = sel_registerName("hasAdLoggingData");
    });
    for (int i = 0; i < 4; i++) {
        if ([object respondsToSelector:s_reelBoolSels[i]] &&
            ((BOOL (*)(id, SEL))objc_msgSend)(object, s_reelBoolSels[i])) {
            return YES;
        }
    }

    static SEL s_videoTypeSel;
    static dispatch_once_t onceVideoType;
    dispatch_once(&onceVideoType, ^{
        s_videoTypeSel = sel_registerName("videoType");
    });
    if ([object respondsToSelector:s_videoTypeSel]) {
        NSInteger videoType = ((NSInteger (*)(id, SEL))objc_msgSend)(object, s_videoTypeSel);
        if (videoType == 3) return YES;
    }

    static SEL s_reelObjSels[5];
    static dispatch_once_t onceReelObjs;
    dispatch_once(&onceReelObjs, ^{
        s_reelObjSels[0] = sel_registerName("adLoggingData");
        s_reelObjSels[1] = sel_registerName("adSlotRenderer");
        s_reelObjSels[2] = sel_registerName("reelNonVideoAdRenderer");
        s_reelObjSels[3] = sel_registerName("nonVideoAdRenderer");
        s_reelObjSels[4] = sel_registerName("sequenceItemAdSelectionRenderer");
    });
    for (int i = 0; i < 5; i++) {
        if ([object respondsToSelector:s_reelObjSels[i]] &&
            ((id (*)(id, SEL))objc_msgSend)(object, s_reelObjSels[i]) != nil) {
            return YES;
        }
    }

    static SEL s_reelChildSels[4];
    static dispatch_once_t onceReelChildren;
    dispatch_once(&onceReelChildren, ^{
        s_reelChildSels[0] = sel_registerName("reelModel");
        s_reelChildSels[1] = sel_registerName("command");
        s_reelChildSels[2] = sel_registerName("watchModel");
        s_reelChildSels[3] = sel_registerName("parentWatchModel");
    });
    for (int i = 0; i < 4; i++) {
        if ([object respondsToSelector:s_reelChildSels[i]]) {
            id child = ((id (*)(id, SEL))objc_msgSend)(object, s_reelChildSels[i]);
            if (child != nil && child != object && YTKACEReelObjectLooksLikeAd(child, depth + 1)) {
                return YES;
            }
        }
    }
    return NO;
}

static BOOL YTKACEReelShouldDisplay(id receiver, SEL selector) {
    BOOL shouldDisplay = OriginalReelShouldDisplay == NULL ||
        ((BOOL (*)(id, SEL))OriginalReelShouldDisplay)(receiver, selector);
    if (!shouldDisplay || !YTKACEFeatureEnabled(YTKACENoAdsKey)) {
        return shouldDisplay;
    }
    if (YTKACEObjectValue(receiver, @"nonVideoContentModel") != nil) {
        return NO;
    }
    return !YTKACEReelObjectLooksLikeAd(receiver, 0);
}

static BOOL YTKACEIsAdLayoutIdentifier(NSString *identifier) {
    if (identifier.length == 0) return NO;
    NSString *normalized = [[identifier lowercaseString]
        stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    normalized = [normalized stringByReplacingOccurrencesOfString:@"-"
                                                        withString:@"_"];
    return [normalized hasPrefix:@"eml_ad_"];
}

static CFMutableDictionaryRef s_classAdCache = NULL;
static os_unfair_lock s_classAdLock = OS_UNFAIR_LOCK_INIT;

static SEL s_adSelectors[40];
static NSUInteger s_adSelectorCount = 0;
static dispatch_once_t s_adSelectorsOnce;

static void YTKACEInitAdSelectors(void) {
    const char *names[] = {
        "isAdRenderer", "isAd", "hasAdLoggingData",
        "hasAdBadgeRenderer", "hasNativeAdBadgeRenderer",
        "hasSimpleAdBadgeRenderer", "hasAdSlotRenderer",
        "hasCompanionAdRenderer", "hasCompactCompanionAdRenderer",
        "hasMultiItemCompanionAdRenderer", "hasAppPromoCompanionAdRenderer",
        "hasShoppingCompanionAdRenderer", "hasSuggestedVideosCompanionAdRenderer",
        "hasCompactPromotedBannerRenderer", "hasCompactPromotedItemRenderer",
        "hasCompactPromotedVideoRenderer", "hasGridPromotedBannerRenderer",
        "hasGridPromotedVideoRenderer", "hasPromoted15ClickPtTextCtdWatchRenderer",
        "hasPromoted15ClickPtTextWatchRenderer", "hasPromoted15ClickTextCtdWatchRenderer",
        "hasPromoted15ClickTextWatchRenderer", "hasPromotedAppInstallRenderer",
        "hasPromotedDiscoveryAppPromoCompactFormRenderer",
        "hasPromotedSparklesTextCtdHomeCompactFormRenderer",
        "hasPromotedSparklesTextCtdHomeRenderer",
        "hasPromotedSparklesTextCtdWatch15ClickRenderer",
        "hasPromotedSparklesTextCtdWatchGridFormRenderer",
        "hasPromotedSparklesTextCtdWatchWideFormRenderer",
        "hasPromotedSparklesTextHomeRenderer",
        "hasPromotedSparklesTextProductHomeRenderer",
        "hasPromotedSparklesTextProductWatchRenderer",
        "hasPromotedSparklesTextSearchRenderer",
        "hasPromotedSparklesTextWatch15ClickRenderer",
        "hasPromotedSparklesTextWatchGridFormRenderer",
        "hasPromotedSparklesTextWatchWideFormRenderer",
        "hasPromotedTextBannerRenderer",
        "hasPromotedVideoInlineMutedRenderer",
        "hasPromotedVideoRenderer",
        "hasShoppingAdInfoCardContentRenderer"
    };
    for (size_t i = 0; i < sizeof(names)/sizeof(names[0]); i++) {
        s_adSelectors[s_adSelectorCount++] = sel_registerName(names[i]);
    }
}

static BOOL YTKACEObjectLooksLikeAd(id object) {
    if (object == nil) return NO;
    id cachedDecision = objc_getAssociatedObject(object, YTKACEAdMatchAssociation);
    if (cachedDecision != nil) {
        return [cachedDecision boolValue];
    }

    Class cls = object_getClass(object);
    if (cls == Nil) return NO;

    os_unfair_lock_lock(&s_classAdLock);
    if (s_classAdCache == NULL) {
        s_classAdCache = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, NULL, NULL);
    }
    const void *classDecision = CFDictionaryGetValue(s_classAdCache, (__bridge const void *)cls);
    os_unfair_lock_unlock(&s_classAdLock);

    if (classDecision != NULL) {
        BOOL isAd = ((intptr_t)classDecision == 2);
        objc_setAssociatedObject(object, YTKACEAdMatchAssociation,
                                 isAd ? @YES : @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return isAd;
    }

    dispatch_once(&s_adSelectorsOnce, ^{
        YTKACEInitAdSelectors();
    });

    BOOL matched = NO;
    const char *cName = class_getName(cls);
    if (cName != NULL) {
        if (strcasestr(cName, "adrenderer") ||
            (strcasestr(cName, "promoted") && strcasestr(cName, "renderer")) ||
            strcasestr(cName, "promorenderer") ||
            strcasestr(cName, "adslotrenderer") ||
            strcasestr(cName, "companionadrenderer") ||
            strcasestr(cName, "shoppingadinfocardcontentrenderer") ||
            strcasestr(cName, "infeedad") ||
            strcasestr(cName, "displayad")) {
            matched = YES;
        }
    }

    if (!matched) {
        for (NSUInteger i = 0; i < s_adSelectorCount; i++) {
            SEL sel = s_adSelectors[i];
            if ([object respondsToSelector:sel] && ((BOOL (*)(id, SEL))objc_msgSend)(object, sel)) {
                matched = YES;
                break;
            }
        }
    }

    if (!matched) {
        static SEL adLoggingDataSel;
        static dispatch_once_t onceLogging;
        dispatch_once(&onceLogging, ^{
            adLoggingDataSel = sel_registerName("adLoggingData");
        });
        if ([object respondsToSelector:adLoggingDataSel] &&
            ((id (*)(id, SEL))objc_msgSend)(object, adLoggingDataSel) != nil) {
            matched = YES;
        }
    }

    if (!matched) {
        static SEL badgeSelectors[3];
        static dispatch_once_t onceBadges;
        dispatch_once(&onceBadges, ^{
            badgeSelectors[0] = sel_registerName("adBadgeRenderer");
            badgeSelectors[1] = sel_registerName("nativeAdBadgeRenderer");
            badgeSelectors[2] = sel_registerName("simpleAdBadgeRenderer");
        });
        for (int i = 0; i < 3; i++) {
            if ([object respondsToSelector:badgeSelectors[i]] &&
                ((id (*)(id, SEL))objc_msgSend)(object, badgeSelectors[i]) != nil) {
                matched = YES;
                break;
            }
        }
    }

    if (!matched) {
        static SEL idSelectors[5];
        static dispatch_once_t onceIDs;
        dispatch_once(&onceIDs, ^{
            idSelectors[0] = sel_registerName("identifier");
            idSelectors[1] = sel_registerName("layoutIdentifier");
            idSelectors[2] = sel_registerName("elementIdentifier");
            idSelectors[3] = sel_registerName("accessibilityIdentifier");
            idSelectors[4] = sel_registerName("templateIdentifier");
        });
        for (int i = 0; i < 5; i++) {
            if ([object respondsToSelector:idSelectors[i]]) {
                id val = ((id (*)(id, SEL))objc_msgSend)(object, idSelectors[i]);
                if ([val isKindOfClass:NSString.class] && YTKACEIsAdLayoutIdentifier((NSString *)val)) {
                    matched = YES;
                    break;
                }
            }
        }
    }

    if (!matched) {
        static SEL compatSel;
        static SEL hasLoggingSel;
        static dispatch_once_t onceCompat;
        dispatch_once(&onceCompat, ^{
            compatSel = sel_registerName("compatibilityOptions");
            hasLoggingSel = sel_registerName("hasAdLoggingData");
        });
        if ([object respondsToSelector:compatSel]) {
            id options = ((id (*)(id, SEL))objc_msgSend)(object, compatSel);
            if ([options respondsToSelector:hasLoggingSel] &&
                ((BOOL (*)(id, SEL))objc_msgSend)(options, hasLoggingSel)) {
                matched = YES;
            }
        }
    }

    os_unfair_lock_lock(&s_classAdLock);
    CFDictionarySetValue(s_classAdCache, (__bridge const void *)cls, (const void *)(matched ? 2 : 1));
    os_unfair_lock_unlock(&s_classAdLock);

    objc_setAssociatedObject(object, YTKACEAdMatchAssociation,
                             matched ? @YES : @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return matched;
}

static const void *YTKACEAdCellAssociation = &YTKACEAdCellAssociation;

typedef struct {
    NSUInteger unit;
    CGFloat value;
} YTKACEASDimension;

static void YTKACECollapseCellNode(id node) {
    static SEL styleSel;
    static SEL setHeightSel;
    static SEL setMaxHeightSel;
    static SEL invalidateLayoutSel;
    static SEL setNeedsLayoutSel;
    static dispatch_once_t onceNode;
    dispatch_once(&onceNode, ^{
        styleSel = sel_registerName("style");
        setHeightSel = sel_registerName("setHeight:");
        setMaxHeightSel = sel_registerName("setMaxHeight:");
        invalidateLayoutSel = sel_registerName("invalidateCalculatedLayout");
        setNeedsLayoutSel = sel_registerName("setNeedsLayout");
    });
    if ([node respondsToSelector:styleSel]) {
        id style = ((id (*)(id, SEL))objc_msgSend)(node, styleSel);
        YTKACEASDimension zero = {1, 0.0};
        if ([style respondsToSelector:setHeightSel]) {
            ((void (*)(id, SEL, YTKACEASDimension))objc_msgSend)(style, setHeightSel, zero);
        }
        if ([style respondsToSelector:setMaxHeightSel]) {
            ((void (*)(id, SEL, YTKACEASDimension))objc_msgSend)(style, setMaxHeightSel, zero);
        }
    }
    if ([node respondsToSelector:invalidateLayoutSel]) {
        ((void (*)(id, SEL))objc_msgSend)(node, invalidateLayoutSel);
    }
    if ([node respondsToSelector:setNeedsLayoutSel]) {
        ((void (*)(id, SEL))objc_msgSend)(node, setNeedsLayoutSel);
    }
}

static void YTKACECollapseAdCell(UIView *cell) {
    CGRect frame = cell.frame;
    if (frame.size.height == 0.0 && cell.hidden) return;
    frame.size.height = 0.0;
    cell.frame = frame;
    cell.hidden = YES;
    cell.alpha = 0.0;
    cell.userInteractionEnabled = NO;
}

void YTKACEHandleAdCellLayout(UIView *cell) {
    if (![objc_getAssociatedObject(cell, YTKACEAdCellAssociation) boolValue]) return;
    YTKACECollapseAdCell(cell);
}

void YTKACEHandleAdCellReuse(UIView *cell) {
    if (![objc_getAssociatedObject(cell, YTKACEAdCellAssociation) boolValue]) return;
    objc_setAssociatedObject(cell, YTKACEAdCellAssociation, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    cell.hidden = NO;
    cell.alpha = 1.0;
    cell.userInteractionEnabled = YES;
}

void YTKACECollapseHostCell(UIView *view) {
    if (view == nil) return;
    static Class uiCellClass;
    static Class asCellClass;
    static dispatch_once_t onceCell;
    dispatch_once(&onceCell, ^{
        uiCellClass = [UICollectionViewCell class];
        asCellClass = NSClassFromString(@"_ASCollectionViewCell");
    });

    UIView *cell = nil;
    for (UIView *ancestor = view; ancestor != nil; ancestor = ancestor.superview) {
        if ([ancestor isKindOfClass:uiCellClass] ||
            (asCellClass != Nil && [ancestor isKindOfClass:asCellClass])) {
            cell = ancestor;
            break;
        }
    }
    view.hidden = YES;
    if (cell == nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [view removeFromSuperview];
        });
        return;
    }
    objc_setAssociatedObject(cell, YTKACEAdCellAssociation, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    YTKACECollapseAdCell(cell);
    for (UIView *ancestor = cell.superview; ancestor != nil; ancestor = ancestor.superview) {
        if ([ancestor isKindOfClass:UICollectionView.class]) {
            [((UICollectionView *)ancestor).collectionViewLayout invalidateLayout];
            break;
        }
    }
    static SEL nodeSelector;
    static dispatch_once_t onceNodeSel;
    dispatch_once(&onceNodeSel, ^{
        nodeSelector = sel_registerName("node");
    });
    if ([cell respondsToSelector:nodeSelector]) {
        id node = ((id (*)(id, SEL))objc_msgSend)(cell, nodeSelector);
        if (node != nil) {
            objc_setAssociatedObject(node, YTKACEAdNodeAssociation, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            YTKACECollapseCellNode(node);
        }
    }
}

void YTKACEHandleAdDisplayView(UIView *view) {
    if (!YTKACEFeatureEnabled(YTKACENoAdsKey) || view.window == nil) return;
    if (!YTKACEIsAdLayoutIdentifier(view.accessibilityIdentifier)) return;
    YTKACECollapseHostCell(view);
}

static id YTKACEElementRenderer(id object) {
    SEL selector = NSSelectorFromString(@"elementRenderer");
    return [object respondsToSelector:selector]
        ? ((id (*)(id, SEL))objc_msgSend)(object, selector)
        : nil;
}

static NSArray *YTKACEFilterAdContents(NSArray *contents, id owner) {
    if (!YTKACEFeatureEnabled(YTKACENoAdsKey) ||
        ![contents isKindOfClass:NSArray.class] || contents.count == 0) {
        return contents;
    }
    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:contents.count];
    for (id content in contents) {
        id renderer = YTKACEElementRenderer(content);
        BOOL contentAd = YTKACEObjectLooksLikeAd(content);
        BOOL rendererAd = YTKACEObjectLooksLikeAd(renderer);
        if (!contentAd && !rendererAd) {
            [filtered addObject:content];
        }
    }
    NSUInteger removed = contents.count - filtered.count;
    if (removed == 0) return contents;
    if (filtered.count == 0 && owner != nil) {
        objc_setAssociatedObject(owner, YTKACEAdEmptyAssociation, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return filtered;
}

static NSArray *YTKACEElementContentsArray(id receiver, SEL selector) {
    NSArray *contents = OriginalElementContentsArray == NULL ? nil :
        ((id (*)(id, SEL))OriginalElementContentsArray)(receiver, selector);
    return YTKACEFilterAdContents(contents, receiver);
}

static NSArray *YTKACEItemSectionContentsArray(id receiver, SEL selector) {
    NSArray *contents = OriginalItemSectionContentsArray == NULL ? nil :
        ((id (*)(id, SEL))OriginalItemSectionContentsArray)(receiver, selector);
    return YTKACEFilterAdContents(contents, receiver);
}

NSArray *YTKACEFilterAdSections(NSArray *sections) {
    if (!YTKACEFeatureEnabled(YTKACENoAdsKey) ||
        ![sections isKindOfClass:NSArray.class] || sections.count == 0) {
        return sections;
    }
    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:sections.count];
    for (id section in sections) {
        if (YTKACEObjectLooksLikeAd(section) ||
            YTKACEObjectLooksLikeAd(YTKACEElementRenderer(section))) {
            continue;
        }
        NSArray *contents = YTKACEObjectValue(section, @"contentsArray");
        if ([objc_getAssociatedObject(section, YTKACEAdEmptyAssociation) boolValue] ||
            ([contents isKindOfClass:NSArray.class] && contents.count != 0 &&
             YTKACEFilterAdContents(contents, section).count == 0)) {
            continue;
        }
        [filtered addObject:section];
    }
    return filtered.count == sections.count ? sections : filtered;
}

static id YTKACENoCompanionAd(id receiver, SEL selector) {
    return YTKACEFeatureEnabled(YTKACENoAdsKey)
        ? nil
        : YTKACECallObjectGetter(OriginalCompanionAd, receiver, selector);
}

static BOOL YTKACENoCompanionFlag(IMP original, id receiver, SEL selector) {
    return YTKACEFeatureEnabled(YTKACENoAdsKey)
        ? NO
        : YTKACECallBooleanGetter(original, receiver, selector);
}

static BOOL YTKACEHasCompanionAdRenderer(id receiver, SEL selector) {
    return YTKACENoCompanionFlag(
        OriginalHasCompanionAdRenderer,
        receiver,
        selector
    );
}

static BOOL YTKACEHasAppPromoCompanionAdRenderer(id receiver, SEL selector) {
    return YTKACENoCompanionFlag(
        OriginalHasAppPromoCompanionAdRenderer,
        receiver,
        selector
    );
}

static BOOL YTKACEHasShoppingCompanionAdRenderer(id receiver, SEL selector) {
    return YTKACENoCompanionFlag(
        OriginalHasShoppingCompanionAdRenderer,
        receiver,
        selector
    );
}

static void YTKACEInstallObjectHookOrMethod(NSString *className,
                                            NSString *selectorName,
                                            IMP replacement,
                                            IMP *originalStorage) {
    if (!YTKACEInstallInstanceHook(
            className,
            selectorName,
            replacement,
            originalStorage
        )) {
        YTKACEAddInstanceMethod(className, selectorName, replacement, "@@:");
    }
}

static void YTKACEInstallBooleanHookOrMethod(NSString *className,
                                             NSString *selectorName,
                                             IMP replacement,
                                             IMP *originalStorage) {
    if (!YTKACEInstallInstanceHook(
            className,
            selectorName,
            replacement,
            originalStorage
        )) {
        YTKACEAddInstanceMethod(className, selectorName, replacement, "B@:");
    }
}

static void YTKACEAdCellLayoutSubviews(UIView *receiver, SEL selector) {
    if (OriginalAdCellLayout != NULL) {
        ((void (*)(id, SEL))OriginalAdCellLayout)(receiver, selector);
    }
    YTKACEHandleAdCellLayout(receiver);
}

static void YTKACEAdCellPrepareForReuse(UIView *receiver, SEL selector) {
    YTKACEHandleAdCellReuse(receiver);
    if (OriginalAdCellReuse != NULL) {
        ((void (*)(id, SEL))OriginalAdCellReuse)(receiver, selector);
    }
}

static IMP YTKACEPromotedSizeOriginal(id receiver, SEL selector) {
    NSString *key = [NSString stringWithFormat:@"%@|%@",
        NSStringFromClass([receiver class]), NSStringFromSelector(selector)];
    @synchronized (YTKACEPromotedSizeOriginals) {
        return (IMP)[YTKACEPromotedSizeOriginals[key] pointerValue];
    }
}

static CGSize YTKACEPromotedCellSize(id receiver, SEL selector, CGSize size) {
    IMP original = YTKACEPromotedSizeOriginal(receiver, selector);
    CGSize resolved = original == NULL
        ? size
        : ((CGSize (*)(id, SEL, CGSize))original)(receiver, selector, size);
    if (!YTKACEFeatureEnabled(YTKACENoAdsKey)) return resolved;
    return CGSizeMake(resolved.width, 0.0);
}

static CGSize YTKACEPromotedCellSizeInsets(id receiver, SEL selector,
                                           CGSize size, UIEdgeInsets insets) {
    IMP original = YTKACEPromotedSizeOriginal(receiver, selector);
    CGSize resolved = original == NULL
        ? size
        : ((CGSize (*)(id, SEL, CGSize, UIEdgeInsets))original)(
            receiver, selector, size, insets);
    if (!YTKACEFeatureEnabled(YTKACENoAdsKey)) return resolved;
    return CGSizeMake(resolved.width, 0.0);
}

static BOOL YTKACEShouldShowPromotedItems(id receiver, SEL selector) {
    if (YTKACEFeatureEnabled(YTKACENoAdsKey)) return NO;
    IMP original = YTKACEPromotedSizeOriginal(receiver, selector);
    return original != NULL && ((BOOL (*)(id, SEL))original)(receiver, selector);
}

static void YTKACEInstallPromotedCellHooks(void) {
    YTKACEPromotedSizeOriginals = [NSMutableDictionary dictionary];
    NSArray<NSString *> *classes = @[@"YTCompactPromotedItemCellController",
                                     @"YTCompactPromotedVideoCellController",
                                     @"YTPromotedVideoCellController"];
    NSDictionary<NSString *, NSValue *> *replacements = @{
        @"cellSizeWithSize:": [NSValue valueWithPointer:(void *)YTKACEPromotedCellSize],
        @"cellSizeWithSize:safeAreaInsets:":
            [NSValue valueWithPointer:(void *)YTKACEPromotedCellSizeInsets],
        @"shouldShowPromotedItems":
            [NSValue valueWithPointer:(void *)YTKACEShouldShowPromotedItems]
    };
    for (NSString *className in classes) {
        for (NSString *selectorName in replacements) {
            IMP original = NULL;
            if (!YTKACEInstallInstanceHook(className, selectorName,
                    (IMP)replacements[selectorName].pointerValue, &original)) {
                continue;
            }
            NSString *key = [NSString stringWithFormat:@"%@|%@",
                className, selectorName];
            @synchronized (YTKACEPromotedSizeOriginals) {
                YTKACEPromotedSizeOriginals[key] =
                    [NSValue valueWithPointer:(void *)original];
            }
        }
    }
}

static BOOL YTKACEIsAdNode(id node) {
    return [objc_getAssociatedObject(node, YTKACEAdNodeAssociation) boolValue];
}

static void YTKACEVideoNodeSetEntry(id receiver, SEL selector, id entry) {
    if (OriginalVideoNodeSetEntry != NULL) {
        ((void (*)(id, SEL, id))OriginalVideoNodeSetEntry)(receiver, selector, entry);
    }
    if (!YTKACEFeatureEnabled(YTKACENoAdsKey)) return;
    BOOL isAd = YTKACEObjectLooksLikeAd(entry) ||
        YTKACEObjectLooksLikeAd(YTKACEElementRenderer(entry));
    objc_setAssociatedObject(receiver, YTKACEAdNodeAssociation,
                             isAd ? @YES : nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!isAd) return;
    YTKACECollapseCellNode(receiver);
    static SEL overlay;
    static SEL setOverlay;
    static SEL resize;
    static dispatch_once_t onceNodeSelectors;
    dispatch_once(&onceNodeSelectors, ^{
        overlay = sel_registerName("dismissedCellOverlayView");
        setOverlay = sel_registerName("setDismissedCellOverlayView:");
        resize = sel_registerName("resizeDismissedView");
    });
    if ([receiver respondsToSelector:overlay] &&
        [receiver respondsToSelector:setOverlay] &&
        ((id (*)(id, SEL))objc_msgSend)(receiver, overlay) == nil) {
        UIView *placeholder = [[UIView alloc] initWithFrame:CGRectZero];
        placeholder.hidden = YES;
        ((void (*)(id, SEL, id))objc_msgSend)(receiver, setOverlay, placeholder);
    }
    if ([receiver respondsToSelector:resize]) {
        ((void (*)(id, SEL))objc_msgSend)(receiver, resize);
    }
}

static BOOL YTKACEVideoNodeShouldShrink(id receiver, SEL selector) {
    if (YTKACEIsAdNode(receiver)) {
        return YES;
    }
    return OriginalVideoNodeShrink != NULL &&
        ((BOOL (*)(id, SEL))OriginalVideoNodeShrink)(receiver, selector);
}

static double YTKACEVideoNodeHeight(id receiver, SEL selector) {
    double height = OriginalVideoNodeHeight == NULL
        ? 0.0
        : ((double (*)(id, SEL))OriginalVideoNodeHeight)(receiver, selector);
    if (!YTKACEIsAdNode(receiver)) return height;
    return 0.0;
}

static CGSize YTKACEVideoNodeSize(id receiver, SEL selector) {
    CGSize size = OriginalVideoNodeSize == NULL
        ? CGSizeZero
        : ((CGSize (*)(id, SEL))OriginalVideoNodeSize)(receiver, selector);
    if (!YTKACEIsAdNode(receiver)) return size;
    return CGSizeMake(size.width, 0.0);
}

void YTKACEInstallAdsHooks(void) {
    YTKACEInstallInstanceHook(@"YTVideoWithContextNode", @"setEntry:",
                              (IMP)YTKACEVideoNodeSetEntry,
                              &OriginalVideoNodeSetEntry);
    YTKACEInstallInstanceHook(@"YTVideoWithContextNode", @"yt_height",
                              (IMP)YTKACEVideoNodeHeight,
                              &OriginalVideoNodeHeight);
    YTKACEInstallInstanceHook(@"YTVideoWithContextNode", @"yt_size",
                              (IMP)YTKACEVideoNodeSize,
                              &OriginalVideoNodeSize);
    YTKACEInstallInstanceHook(@"YTVideoWithContextNode",
                              @"shouldShrinkDismissalView",
                              (IMP)YTKACEVideoNodeShouldShrink,
                              &OriginalVideoNodeShrink);
    YTKACEInstallPromotedCellHooks();
    YTKACEInstallInstanceHook(@"_ASCollectionViewCell",
                              @"layoutSubviews",
                              (IMP)YTKACEAdCellLayoutSubviews,
                              &OriginalAdCellLayout);
    YTKACEInstallInstanceHook(@"_ASCollectionViewCell",
                              @"prepareForReuse",
                              (IMP)YTKACEAdCellPrepareForReuse,
                              &OriginalAdCellReuse);
    YTKACEInstallInstanceHook(@"YTGlobalConfig",
                              @"shouldBlockUpgradeDialog",
                              (IMP)YTKACEShouldBlockUpgradeDialog,
                              &OriginalShouldBlockUpgradeDialog);
    YTKACEInstallClassHook(@"YTAdShieldUtils",
                           @"spamSignalsDictionary",
                           (IMP)YTKACEAdShieldSignals,
                           &OriginalAdShieldSignals);
    YTKACEInstallClassHook(@"YTAdShieldUtils",
                           @"spamSignalsDictionaryWithoutIDFA",
                           (IMP)YTKACEAdShieldSignalsWithoutIDFA,
                           &OriginalAdShieldSignalsWithoutIDFA);
    YTKACEInstallClassHook(@"YTDataUtils",
                           @"spamSignalsDictionary",
                           (IMP)YTKACEDataSignals,
                           &OriginalDataSignals);
    YTKACEInstallClassHook(@"YTDataUtils",
                           @"spamSignalsDictionaryWithoutIDFA",
                           (IMP)YTKACEDataSignalsWithoutIDFA,
                           &OriginalDataSignalsWithoutIDFA);
    YTKACEInstallInstanceHook(@"YTAdsInnerTubeContextDecorator",
                              @"decorateContext:",
                              (IMP)YTKACEAdsDecorateContext,
                              &OriginalAdsDecorateContext);
    YTKACEInstallInstanceHook(@"YTAccountScopedAdsInnerTubeContextDecorator",
                              @"decorateContext:",
                              (IMP)YTKACEAccountAdsDecorateContext,
                              &OriginalAccountAdsDecorateContext);

    YTKACEInstallObjectHookOrMethod(@"YTIPlayerResponse",
                                    @"playerAdsArray",
                                    (IMP)YTKACEPlayerAdsArray,
                                    &OriginalPlayerAdsArray);
    YTKACEInstallObjectHookOrMethod(@"YTIPlayerResponse",
                                    @"adSlotsArray",
                                    (IMP)YTKACEAdSlotsArray,
                                    &OriginalAdSlotsArray);
    YTKACEInstallObjectHookOrMethod(@"YTIPlayerResponse",
                                    @"adPlacementsArray",
                                    (IMP)YTKACEAdPlacementsArray,
                                    &OriginalAdPlacementsArray);
    YTKACEInstallInstanceHook(@"YTIPlayerResponse",
                              @"adBreakParams",
                              (IMP)YTKACEAdBreakParams,
                              &OriginalAdBreakParams);
    YTKACEInstallInstanceHook(@"YTIPlayerResponse",
                              @"adNextParams",
                              (IMP)YTKACEAdNextParams,
                              &OriginalAdNextParams);
    YTKACEInstallInstanceHook(@"YTIPlayerResponse",
                              @"adParams",
                              (IMP)YTKACEAdParams,
                              &OriginalAdParams);
    YTKACEInstallBooleanHookOrMethod(@"YTIClientMdxGlobalConfig",
                                     @"enableSkippableAd",
                                     (IMP)YTKACEEnableSkippableAd,
                                     &OriginalEnableSkippableAd);

    YTKACEInstallInstanceHook(@"MDXSessionImpl",
                              @"adPlaying:",
                              (IMP)YTKACEMDXSessionImplAdPlaying,
                              &OriginalMDXSessionImplAdPlaying);
    YTKACEInstallInstanceHook(@"MDXSession",
                              @"adPlaying:",
                              (IMP)YTKACEMDXSessionAdPlaying,
                              &OriginalMDXSessionAdPlaying);
    YTKACEInstallInstanceHook(@"YTLocalPlaybackController",
                              @"isPlayingAd",
                              (IMP)YTKACEIsPlayingAd,
                              &OriginalIsPlayingAd);
    YTKACEInstallInstanceHook(@"YTLocalPlaybackController",
                              @"isPlayingAdSurvey",
                              (IMP)YTKACEIsPlayingAdSurvey,
                              &OriginalIsPlayingAdSurvey);
    YTKACEInstallInstanceHook(@"YTLocalPlaybackController",
                              @"isPlayingAdIntro",
                              (IMP)YTKACEIsPlayingAdIntro,
                              &OriginalIsPlayingAdIntro);
    YTKACEInstallInstanceHook(@"YTLocalPlaybackController",
                              @"createAdsPlaybackCoordinator",
                              (IMP)YTKACENoAdsPlaybackCoordinator,
                              &OriginalCreateAdsPlaybackCoordinator);

    YTKACEInstallInstanceHook(@"YTReelDataSource",
                              @"makeContentModelForEntry:",
                              (IMP)YTKACEReelContentModel,
                              &OriginalReelContentModel);
    YTKACEInstallInstanceHook(@"YTReelInfinitePlaybackDataSource",
                              @"makeContentModelForEntry:",
                              (IMP)YTKACEInfiniteReelContentModel,
                              &OriginalInfiniteReelContentModel);
    YTKACEInstallInstanceHook(@"YTReelContentModel",
                              @"shouldDisplay",
                              (IMP)YTKACEReelShouldDisplay,
                              &OriginalReelShouldDisplay);
    YTKACEInstallInstanceHook(@"YTIElementRenderer",
                              @"companionAd",
                              (IMP)YTKACENoCompanionAd,
                              &OriginalCompanionAd);
    YTKACEInstallInstanceHook(@"YTIElementRenderer",
                              @"hasCompanionAdRenderer",
                              (IMP)YTKACEHasCompanionAdRenderer,
                              &OriginalHasCompanionAdRenderer);
    YTKACEInstallInstanceHook(@"YTIElementRenderer",
                              @"hasAppPromoCompanionAdRenderer",
                              (IMP)YTKACEHasAppPromoCompanionAdRenderer,
                              &OriginalHasAppPromoCompanionAdRenderer);
    YTKACEInstallInstanceHook(@"YTIElementRenderer",
                              @"hasShoppingCompanionAdRenderer",
                              (IMP)YTKACEHasShoppingCompanionAdRenderer,
                              &OriginalHasShoppingCompanionAdRenderer);
    YTKACEInstallInstanceHook(@"YTIElementRenderer",
                              @"contentsArray",
                              (IMP)YTKACEElementContentsArray,
                              &OriginalElementContentsArray);
    YTKACEInstallInstanceHook(@"YTIItemSectionRenderer",
                              @"contentsArray",
                              (IMP)YTKACEItemSectionContentsArray,
                              &OriginalItemSectionContentsArray);
}
