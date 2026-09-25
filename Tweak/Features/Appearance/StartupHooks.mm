#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static CFMutableDictionaryRef s_startupOriginals = NULL;

static inline void YTKACERegisterStartupOriginal(Class cls, SEL selector, IMP implementation) {
    if (s_startupOriginals == NULL) {
        s_startupOriginals = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, NULL, NULL);
    }
    NSString *key = [NSString stringWithFormat:@"%@|%@", NSStringFromClass(cls), NSStringFromSelector(selector)];
    CFDictionarySetValue(s_startupOriginals, (__bridge const void *)key, (const void *)implementation);
}

static inline IMP YTKACEStartupOriginal(id receiver, SEL selector) {
    if (s_startupOriginals == NULL || receiver == nil) return NULL;
    for (Class cls = [receiver class]; cls != Nil; cls = class_getSuperclass(cls)) {
        NSString *key = [NSString stringWithFormat:@"%@|%@", NSStringFromClass(cls), NSStringFromSelector(selector)];
        IMP original = (IMP)CFDictionaryGetValue(s_startupOriginals, (__bridge const void *)key);
        if (original != NULL) return original;
    }
    return NULL;
}

static void YTKACEStartupBlacken(UIView *view) {
    if (view == nil || view.hidden) return;
    UIColor *background = view.backgroundColor;
    if (background != nil && CGColorGetAlpha(background.CGColor) > 0.01) {
        view.backgroundColor = UIColor.blackColor;
    }
    for (UIView *child in view.subviews) {
        YTKACEStartupBlacken(child);
    }
}

static void YTKACEStartupViewDidLoad(UIViewController *receiver,
                                     SEL selector) {
    IMP original = YTKACEStartupOriginal(receiver, selector);
    if (original != NULL) {
        ((void (*)(id, SEL))original)(receiver, selector);
    }
    if (YTKACEOLEDActive(receiver.traitCollection)) {
        receiver.view.backgroundColor = UIColor.blackColor;
        YTKACEStartupBlacken(receiver.view);
        receiver.view.window.backgroundColor = UIColor.blackColor;
    }
}

static void YTKACEFinishStartup(UIViewController *receiver) {
    static SEL delegateSelector;
    static SEL completionSelector;
    static SEL forceSelector;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        delegateSelector = NSSelectorFromString(@"delegate");
        completionSelector = NSSelectorFromString(@"startupAnimationDidComplete");
        forceSelector = NSSelectorFromString(@"forceDismissStartupAnimationAnimated:");
    });

    id delegate = [receiver respondsToSelector:delegateSelector]
        ? ((id (*)(id, SEL))objc_msgSend)(receiver, delegateSelector)
        : nil;
    if ([delegate respondsToSelector:completionSelector]) {
        ((void (*)(id, SEL))objc_msgSend)(delegate, completionSelector);
        return;
    }
    if ([delegate respondsToSelector:forceSelector]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(delegate, forceSelector, NO);
        return;
    }
    [receiver dismissViewControllerAnimated:NO completion:nil];
}

static void YTKACEStartupViewDidAppear(UIViewController *receiver,
                                       SEL selector,
                                       BOOL animated) {
    IMP original = YTKACEStartupOriginal(receiver, selector);
    if (original != NULL) {
        ((void (*)(id, SEL, BOOL))original)(receiver, selector, animated);
    }
    if (YTKACEOLEDActive(receiver.traitCollection)) {
        receiver.view.backgroundColor = UIColor.blackColor;
        YTKACEStartupBlacken(receiver.view);
        receiver.view.window.backgroundColor = UIColor.blackColor;
    }
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Appearance.LaunchAnimationDisabled")) {
        dispatch_async(dispatch_get_main_queue(), ^{
            YTKACEFinishStartup(receiver);
        });
    }
}

static void YTKACEInstallStartupHook(NSString *className,
                                     NSString *selectorName,
                                     IMP replacement) {
    Class cls = NSClassFromString(className);
    if (cls == Nil) return;
    SEL selector = NSSelectorFromString(selectorName);
    IMP original = NULL;
    if (!YTKACEInstallInstanceHook(className, selectorName,
                                   replacement, &original) ||
        original == NULL || original == replacement) {
        return;
    }
    YTKACERegisterStartupOriginal(cls, selector, original);
}

void YTKACEInstallStartupHooks(void) {
    for (NSString *className in @[
        @"YTStartupAnimationViewController",
        @"YTRiveStartupAnimationViewController"
    ]) {
        YTKACEInstallStartupHook(className, @"viewDidLoad",
                                 (IMP)YTKACEStartupViewDidLoad);
        YTKACEInstallStartupHook(className, @"viewDidAppear:",
                                 (IMP)YTKACEStartupViewDidAppear);
    }
}
