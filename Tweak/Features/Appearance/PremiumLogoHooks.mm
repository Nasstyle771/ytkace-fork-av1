#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <UIKit/UIKit.h>

static IMP OriginalImageNamedBundleTraits;
static IMP OriginalImageNamedBundle;

static NSBundle *YTKACEInnertubeBundle(void) {
    static NSBundle *s_cachedBundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSBundle *main = NSBundle.mainBundle;
        NSString *path1 = [main.resourcePath stringByAppendingPathComponent:@"Innertube_Resources.bundle"];
        s_cachedBundle = [NSBundle bundleWithPath:path1];
        if (s_cachedBundle == nil) {
            NSString *path2 = [main.resourcePath stringByAppendingPathComponent:@"Frameworks/Module_Framework.framework/Innertube_Resources.bundle"];
            s_cachedBundle = [NSBundle bundleWithPath:path2];
        }
    });
    return s_cachedBundle;
}

static inline NSString *YTKACEPremiumName(NSString *name, UITraitCollection *traits) {
    BOOL darkName = [name rangeOfString:@"dark" options:NSCaseInsensitiveSearch].location != NSNotFound;
    BOOL darkMode = NO;
    if (@available(iOS 13.0, *)) {
        darkMode = traits.userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return (darkName || darkMode) ? @"youtube_premium_logo_white" : @"youtube_premium_logo";
}

static inline BOOL YTKACEShouldReplaceLogo(NSString *name) {
    if (name.length == 0 || ![name isKindOfClass:NSString.class]) return NO;
    // Fast path: 99% of images do not contain "youtube_logo"
    if ([name rangeOfString:@"youtube_logo" options:NSCaseInsensitiveSearch].location == NSNotFound) {
        return NO;
    }
    if ([name rangeOfString:@"premium" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return NO;
    }
    return YTKACEFeatureEnabled(@"YTKACE.Preference.Navigation.PremiumLogo");
}

static UIImage *YTKACEImageNamedBundleTraits(id receiver,
                                              SEL selector,
                                              NSString *name,
                                              NSBundle *bundle,
                                              UITraitCollection *traits) {
    if (OriginalImageNamedBundleTraits == NULL) {
        return nil;
    }
    UIImage *(*original)(id, SEL, NSString *, NSBundle *, UITraitCollection *) =
        (UIImage *(*)(id, SEL, NSString *, NSBundle *, UITraitCollection *))
            OriginalImageNamedBundleTraits;
    if (YTKACEShouldReplaceLogo(name)) {
        NSBundle *resources = YTKACEInnertubeBundle() ?: bundle;
        UIImage *premium = original(
            receiver,
            selector,
            YTKACEPremiumName(name, traits),
            resources,
            traits
        );
        if (premium != nil) {
            return premium;
        }
    }
    return original(receiver, selector, name, bundle, traits);
}

static UIImage *YTKACEImageNamedBundle(id receiver,
                                       SEL selector,
                                       NSString *name,
                                       NSBundle *bundle) {
    if (OriginalImageNamedBundle == NULL) {
        return nil;
    }
    UIImage *(*original)(id, SEL, NSString *, NSBundle *) =
        (UIImage *(*)(id, SEL, NSString *, NSBundle *))OriginalImageNamedBundle;
    if (YTKACEShouldReplaceLogo(name)) {
        NSBundle *resources = YTKACEInnertubeBundle() ?: bundle;
        UIImage *premium = original(
            receiver,
            selector,
            YTKACEPremiumName(name, UIScreen.mainScreen.traitCollection),
            resources
        );
        if (premium != nil) {
            return premium;
        }
    }
    return original(receiver, selector, name, bundle);
}

void YTKACEInstallPremiumLogoHooks(void) {
    YTKACEInstallClassHook(@"UIImage",
                           @"imageNamed:inBundle:compatibleWithTraitCollection:",
                           (IMP)YTKACEImageNamedBundleTraits,
                           &OriginalImageNamedBundleTraits);
    YTKACEInstallClassHook(@"UIImage",
                           @"imageNamed:inBundle:",
                           (IMP)YTKACEImageNamedBundle,
                           &OriginalImageNamedBundle);
}
