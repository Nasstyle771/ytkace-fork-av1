#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"

#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

static IMP OriginalOverlayDidMoveToWindow;
static const void *YTKACEEdgePanAssociation = &YTKACEEdgePanAssociation;
static const void *YTKACEGestureSurfaceAssociation =
    &YTKACEGestureSurfaceAssociation;
static const void *YTKACELongPressAssociation = &YTKACELongPressAssociation;
static const void *YTKACEGestureInitialAssociation = &YTKACEGestureInitialAssociation;
static const void *YTKACEGestureSecondaryInitialAssociation =
    &YTKACEGestureSecondaryInitialAssociation;
static const void *YTKACEGestureActionAssociation = &YTKACEGestureActionAssociation;
static const void *YTKACEIndicatorAssociation = &YTKACEIndicatorAssociation;
static const void *YTKACEIndicatorIconAssociation = &YTKACEIndicatorIconAssociation;
static const void *YTKACEIndicatorTrackAssociation = &YTKACEIndicatorTrackAssociation;
static const void *YTKACEIndicatorFillAssociation = &YTKACEIndicatorFillAssociation;
static const void *YTKACEIndicatorLabelAssociation = &YTKACEIndicatorLabelAssociation;
static const void *YTKACEVolumeViewAssociation = &YTKACEVolumeViewAssociation;
static const void *YTKACEVolumeSliderAssociation = &YTKACEVolumeSliderAssociation;
static const void *YTKACESeekIndicatorAssociation = &YTKACESeekIndicatorAssociation;
static const void *YTKACESeekIconAssociation = &YTKACESeekIconAssociation;
static const void *YTKACESeekLabelAssociation = &YTKACESeekLabelAssociation;

@interface YTKACEPriorityPanGestureRecognizer : UIPanGestureRecognizer
@end

@implementation YTKACEPriorityPanGestureRecognizer

- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)preventedGestureRecognizer {
    return YES;
}

- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)preventingGestureRecognizer {
    return NO;
}

@end

@interface YTKACEGestureCoordinator : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)sharedCoordinator;
@property(nonatomic, strong) CADisplayLink *seekDisplayLink;
@property(nonatomic, assign) CFTimeInterval lastSeekTickTime;
@property(nonatomic, weak) UIResponder *seekTarget;
@property(nonatomic, weak) UIView *seekView;
@property(nonatomic, assign) double seekTime;
@property(nonatomic, assign) NSInteger seekDirection;
- (void)handleEdgePan:(UIPanGestureRecognizer *)recognizer;
- (void)handleHold:(UILongPressGestureRecognizer *)recognizer;
- (void)handleSeekTick:(CADisplayLink *)link;
@end

@implementation YTKACEGestureCoordinator

+ (instancetype)sharedCoordinator {
    static YTKACEGestureCoordinator *coordinator;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        coordinator = [YTKACEGestureCoordinator new];
    });
    return coordinator;
}

- (UISlider *)volumeSliderInView:(UIView *)view {
    MPVolumeView *volumeView =
        objc_getAssociatedObject(view, YTKACEVolumeViewAssociation);
    if (volumeView == nil) {
        volumeView = [[MPVolumeView alloc] initWithFrame:CGRectMake(-100, -100, 1, 1)];
        volumeView.alpha = 0.01;
        [view addSubview:volumeView];
        objc_setAssociatedObject(view,
                                 YTKACEVolumeViewAssociation,
                                 volumeView,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UISlider *cachedSlider = objc_getAssociatedObject(volumeView, YTKACEVolumeSliderAssociation);
    if (cachedSlider != nil) {
        return cachedSlider;
    }
    for (UIView *subview in volumeView.subviews) {
        if ([subview isKindOfClass:UISlider.class]) {
            UISlider *slider = (UISlider *)subview;
            objc_setAssociatedObject(volumeView, YTKACEVolumeSliderAssociation, slider, OBJC_ASSOCIATION_ASSIGN);
            return slider;
        }
    }
    return nil;
}

- (UIView *)indicatorInView:(UIView *)view {
    UIView *indicator = objc_getAssociatedObject(view, YTKACEIndicatorAssociation);
    if (indicator != nil) {
        return indicator;
    }

    indicator = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 200.0, 50.0)];
    indicator.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.65];
    indicator.layer.cornerRadius = 10.0;
    indicator.clipsToBounds = YES;
    indicator.userInteractionEnabled = NO;
    indicator.alpha = 0.0;

    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(15.0, 12.0, 26.0, 26.0)];
    icon.tintColor = UIColor.whiteColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [indicator addSubview:icon];

    UIView *track = [[UIView alloc] initWithFrame:CGRectMake(50.0, 18.0, 130.0, 3.0)];
    track.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.3];
    track.layer.cornerRadius = 1.5;
    [indicator addSubview:track];

    UIView *fill = [[UIView alloc] initWithFrame:CGRectMake(50.0, 18.0, 0.0, 3.0)];
    fill.backgroundColor = UIColor.whiteColor;
    fill.layer.cornerRadius = 1.5;
    [indicator addSubview:fill];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(50.0, 25.0, 130.0, 20.0)];
    label.textColor = UIColor.whiteColor;
    label.alpha = 0.8;
    label.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    label.textAlignment = NSTextAlignmentRight;
    [indicator addSubview:label];

    [view addSubview:indicator];
    objc_setAssociatedObject(view,
                             YTKACEIndicatorAssociation,
                             indicator,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, YTKACEIndicatorIconAssociation, icon,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, YTKACEIndicatorTrackAssociation, track,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, YTKACEIndicatorFillAssociation, fill,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, YTKACEIndicatorLabelAssociation, label,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return indicator;
}

- (UIView *)seekIndicatorInView:(UIView *)view {
    UIView *indicator = objc_getAssociatedObject(view, YTKACESeekIndicatorAssociation);
    if (indicator != nil) return indicator;
    indicator = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 120.0, 120.0)];
    indicator.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.75];
    indicator.layer.cornerRadius = 12.0;
    indicator.clipsToBounds = YES;
    indicator.userInteractionEnabled = NO;
    indicator.alpha = 0.0;
    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(35.0, 25.0, 50.0, 50.0)];
    icon.tintColor = UIColor.whiteColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [indicator addSubview:icon];
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0.0, 80.0, 120.0, 30.0)];
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont boldSystemFontOfSize:18.0];
    label.textAlignment = NSTextAlignmentCenter;
    [indicator addSubview:label];
    [view addSubview:indicator];
    objc_setAssociatedObject(view, YTKACESeekIndicatorAssociation, indicator,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, YTKACESeekIconAssociation, icon,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, YTKACESeekLabelAssociation, label,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return indicator;
}

- (BOOL)isEdgePan:(UIGestureRecognizer *)recognizer {
    return recognizer == objc_getAssociatedObject(recognizer.view,
                                                   YTKACEEdgePanAssociation);
}

- (UIViewController *)playerControllerForView:(UIView *)view {
    static Class playerVCClass;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        playerVCClass = NSClassFromString(@"YTPlayerViewController");
    });
    UIResponder *responder = view;
    while (responder != nil) {
        if (playerVCClass != Nil && [responder isKindOfClass:playerVCClass]) {
            return (UIViewController *)responder;
        }
        responder = responder.nextResponder;
    }
    return nil;
}

- (BOOL)isFullscreenPlayerSurface:(UIView *)view {
    UIViewController *controller = [self playerControllerForView:view];
    for (NSString *name in @[
        @"isFullscreen",
        @"isFullScreen",
        @"isFullscreenPlayer",
        @"isFullScreenPresented",
        @"isFullScreenMode",
        @"fullscreenMode",
        @"fullScreenMode"
    ]) {
        SEL selector = NSSelectorFromString(name);
        if (controller != nil && [controller respondsToSelector:selector] &&
            ((BOOL (*)(id, SEL))objc_msgSend)(controller, selector)) {
            return YES;
        }
    }

    UIWindow *window = view.window;
    if (window == nil || CGRectIsEmpty(view.bounds)) return NO;
    CGRect frame = [view convertRect:view.bounds toView:window];
    CGRect bounds = window.bounds;
    if (CGRectIsEmpty(bounds)) return NO;
    CGFloat widthRatio = CGRectGetWidth(frame) / CGRectGetWidth(bounds);
    CGFloat heightRatio = CGRectGetHeight(frame) / CGRectGetHeight(bounds);
    return widthRatio >= 0.82 && heightRatio >= 0.82;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    if (gestureRecognizer == objc_getAssociatedObject(gestureRecognizer.view,
                                                       YTKACELongPressAssociation)) {
        return NO;
    }
    UIGestureRecognizer *edgePan = nil;
    if ([self isEdgePan:gestureRecognizer]) {
        edgePan = gestureRecognizer;
    } else if ([self isEdgePan:other]) {
        edgePan = other;
    }
    if (edgePan != nil) return NO;
    return YES;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (YTKACEFeatureEnabled(@"YTKACE.Preference.Gestures.LandscapeOnly")) {
        const CGSize screen = gestureRecognizer.view.window.bounds.size;
        if (screen.height > 0.0 && screen.width <= screen.height) return NO;
    }
    if ([self isEdgePan:gestureRecognizer]) {
        if (!YTKACEMasterEnabled()) return NO;
        UIView *view = gestureRecognizer.view;
        NSInteger surface = [objc_getAssociatedObject(
            gestureRecognizer, YTKACEGestureSurfaceAssociation) integerValue];
        CGPoint location = [gestureRecognizer locationInView:view];
        CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer
            velocityInView:view];
        if (surface != 1) return NO;
        CGRect activeBounds = view.bounds;
        if (CGRectIsEmpty(activeBounds) || CGRectIsNull(activeBounds)) return NO;
        if (fabs(velocity.y) <= fabs(velocity.x)) return NO;

        // Two-finger swipe support: allowed anywhere across player surface!
        if (gestureRecognizer.numberOfTouches == 2) {
            BOOL left = location.x < CGRectGetMidX(activeBounds);
            NSString *key = left
                ? @"YTKACE.Preference.Gestures.LeftAction"
                : @"YTKACE.Preference.Gestures.RightAction";
            NSInteger action = [YTKACEPreferenceObject(key) integerValue];
            if (action == 0) {
                // Default fallback: left = brightness (1), right = volume (2)
                action = left ? 1 : 2;
            }
            objc_setAssociatedObject(gestureRecognizer,
                                     YTKACEGestureActionAssociation,
                                     @(action),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return YES;
        }

        // Single-finger edge swipe
        double storedArea = [YTKACEPreferenceObject(
            @"YTKACE.Preference.Gestures.ActivationArea") doubleValue];
        double areaPercent = storedArea > 0.0 ? storedArea : 20.0;
        CGFloat edge = CGRectGetWidth(activeBounds) *
            MIN(0.5, MAX(0.1, areaPercent / 100.0));
        BOOL left = location.x >= CGRectGetMinX(activeBounds) &&
            location.x <= CGRectGetMinX(activeBounds) + edge;
        BOOL right = location.x <= CGRectGetMaxX(activeBounds) &&
            location.x >= CGRectGetMaxX(activeBounds) - edge;
        if (!left && !right) return NO;
        NSString *key = left
            ? @"YTKACE.Preference.Gestures.LeftAction"
            : @"YTKACE.Preference.Gestures.RightAction";
        NSInteger action = [YTKACEPreferenceObject(key) integerValue];
        objc_setAssociatedObject(gestureRecognizer,
                                 YTKACEGestureActionAssociation,
                                 @(action),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return action >= 1 && action <= 3;
    }
    if (![gestureRecognizer isKindOfClass:UILongPressGestureRecognizer.class]) {
        return YES;
    }
    if (!YTKACEFeatureEnabled(@"YTKACE.Preference.Gestures.HoldToSeek")) {
        return NO;
    }
    UIView *view = gestureRecognizer.view;
    CGPoint location = [gestureRecognizer locationInView:view];
    CGRect bounds = view.bounds;
    return location.x > CGRectGetWidth(bounds) * 0.2 &&
        location.x < CGRectGetWidth(bounds) * 0.8 &&
        location.y > CGRectGetHeight(bounds) * 0.15 &&
        location.y < CGRectGetHeight(bounds) * 0.85;
}

- (void)layoutIndicator:(UIView *)indicator inView:(UIView *)view {
    NSInteger size = [YTKACEPreferenceObject(
        @"YTKACE.Preference.Gestures.HUDSize") integerValue];
    CGSize dimensions = CGSizeMake(200.0, 50.0);
    if (size == 0) dimensions = CGSizeMake(164.0, 44.0);
    if (size == 2) dimensions = CGSizeMake(236.0, 58.0);
    indicator.bounds = (CGRect){CGPointZero, dimensions};

    UIEdgeInsets safe = view.safeAreaInsets;
    NSInteger position = [YTKACEPreferenceObject(
        @"YTKACE.Preference.Gestures.HUDPosition") integerValue];
    CGFloat centerY = safe.top + dimensions.height * 0.5 + 18.0;
    if (position == 1) {
        centerY = CGRectGetMidY(view.bounds);
    } else if (position == 2) {
        centerY = CGRectGetHeight(view.bounds) - safe.bottom -
            dimensions.height * 0.5 - 24.0;
    }
    centerY = MIN(CGRectGetHeight(view.bounds) - dimensions.height * 0.5,
                  MAX(dimensions.height * 0.5, centerY));
    indicator.center = CGPointMake(CGRectGetMidX(view.bounds), centerY);

    UIImageView *icon = objc_getAssociatedObject(view, YTKACEIndicatorIconAssociation);
    UIView *track = objc_getAssociatedObject(view, YTKACEIndicatorTrackAssociation);
    UIView *fill = objc_getAssociatedObject(view, YTKACEIndicatorFillAssociation);
    UILabel *label = objc_getAssociatedObject(view, YTKACEIndicatorLabelAssociation);
    CGFloat scale = dimensions.height / 50.0;
    icon.frame = CGRectMake(15.0 * scale, 12.0 * scale,
                            26.0 * scale, 26.0 * scale);
    CGFloat trackX = 50.0 * scale;
    CGFloat trackWidth = dimensions.width - trackX - 20.0 * scale;
    track.frame = CGRectMake(trackX, 18.0 * scale, trackWidth, 3.0);
    CGRect fillFrame = fill.frame;
    fillFrame.origin = CGPointMake(trackX, 18.0 * scale);
    fillFrame.size.height = 3.0;
    fill.frame = fillFrame;
    label.frame = CGRectMake(trackX, 25.0 * scale, trackWidth, 20.0 * scale);
    label.font = [UIFont systemFontOfSize:12.0 * scale weight:UIFontWeightMedium];
}

- (void)updateIndicatorInView:(UIView *)view value:(double)value volume:(BOOL)volume isInitial:(BOOL)isInitial {
    if (!YTKACEFeatureEnabled(@"YTKACE.Preference.Gestures.HUDEnabled")) return;
    UIView *indicator = [self indicatorInView:view];
    UIImageView *icon = objc_getAssociatedObject(view, YTKACEIndicatorIconAssociation);
    UIView *fill = objc_getAssociatedObject(view, YTKACEIndicatorFillAssociation);
    UILabel *label = objc_getAssociatedObject(view, YTKACEIndicatorLabelAssociation);

    if (isInitial) {
        [self layoutIndicator:indicator inView:view];
    }

    NSString *symbol = nil;
    if (volume) {
        if (value <= 0.01) symbol = @"speaker.slash.fill";
        else if (value <= 0.33) symbol = @"speaker.1.fill";
        else if (value <= 0.66) symbol = @"speaker.2.fill";
        else symbol = @"speaker.3.fill";
    } else {
        symbol = value <= 0.4 ? @"sun.min.fill" : @"sun.max.fill";
    }
    icon.image = [[UIImage systemImageNamed:symbol]
        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];

    CGFloat trackX = fill.frame.origin.x;
    CGFloat availableWidth = indicator.bounds.size.width - trackX - 20.0 * (indicator.bounds.size.height / 50.0);
    CGRect frame = fill.frame;
    frame.size.width = availableWidth * value;
    fill.frame = frame;
    label.text = [NSString stringWithFormat:@"%d%%", (int)lround(value * 100.0)];
    [view bringSubviewToFront:indicator];
}

- (void)handleEdgePan:(UIPanGestureRecognizer *)recognizer {
    UIView *view = recognizer.view;
    NSInteger action = [objc_getAssociatedObject(
        recognizer, YTKACEGestureActionAssociation) integerValue];
    BOOL volume = action == 2;
    BOOL both = action == 3;

    if (recognizer.state == UIGestureRecognizerStateBegan) {
        double start = volume
            ? AVAudioSession.sharedInstance.outputVolume
            : UIScreen.mainScreen.brightness;
        objc_setAssociatedObject(recognizer,
                                 YTKACEGestureInitialAssociation,
                                 @(start),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (both) {
            objc_setAssociatedObject(
                recognizer, YTKACEGestureSecondaryInitialAssociation,
                @(AVAudioSession.sharedInstance.outputVolume),
                OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (YTKACEFeatureEnabled(@"YTKACE.Preference.Gestures.HUDEnabled")) {
            [self updateIndicatorInView:view value:start volume:volume isInitial:YES];
            UIView *indicator = [self indicatorInView:view];
            [UIView animateWithDuration:0.12
                                  delay:0.0
                                options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                             animations:^{ indicator.alpha = 1.0; }
                             completion:nil];
        }
    }
    if (recognizer.state == UIGestureRecognizerStateChanged) {
        double start = [objc_getAssociatedObject(recognizer,
            YTKACEGestureInitialAssociation) doubleValue];
        CGFloat height = MAX(180.0, CGRectGetHeight(view.bounds) * 0.72);
        CGFloat translation = [recognizer translationInView:view].y;
        double value = MIN(1.0, MAX(0.0, start - translation / height));
        if (volume) {
            UISlider *slider = [self volumeSliderInView:view];
            [slider setValue:(float)value animated:NO];
            [slider sendActionsForControlEvents:UIControlEventValueChanged];
        } else {
            UIScreen.mainScreen.brightness = value;
            if (both) {
                double volumeStart = [objc_getAssociatedObject(
                    recognizer, YTKACEGestureSecondaryInitialAssociation)
                    doubleValue];
                double volumeValue = MIN(1.0, MAX(
                    0.0, volumeStart - translation / height));
                UISlider *slider = [self volumeSliderInView:view];
                [slider setValue:(float)volumeValue animated:NO];
                [slider sendActionsForControlEvents:UIControlEventValueChanged];
            }
        }
        if (YTKACEFeatureEnabled(@"YTKACE.Preference.Gestures.HUDEnabled")) {
            [self updateIndicatorInView:view value:value volume:volume isInitial:NO];
        }
    }
    if (recognizer.state == UIGestureRecognizerStateEnded ||
        recognizer.state == UIGestureRecognizerStateCancelled) {
        if (YTKACEFeatureEnabled(@"YTKACE.Preference.Gestures.HUDEnabled")) {
            UIView *indicator = [self indicatorInView:view];
            [UIView animateWithDuration:0.22
                                  delay:0.45
                                options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState
                             animations:^{ indicator.alpha = 0.0; }
                             completion:nil];
        }
        objc_setAssociatedObject(recognizer, YTKACEGestureActionAssociation,
                                 nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(
            recognizer, YTKACEGestureSecondaryInitialAssociation,
            nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (double)seekStep {
    double value = [NSUserDefaults.standardUserDefaults
        doubleForKey:@"YTKACE.Preference.Gestures.HoldSeekSeconds"];
    return MIN(60.0, MAX(1.0, value > 0.0 ? value : 10.0));
}

- (UIResponder *)seekResponderForView:(UIView *)view {
    static SEL currentMediaTimeSel;
    static SEL mediaTimeSel;
    static SEL seekToTimeSel;
    static SEL didSeekToTimeSel;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        currentMediaTimeSel = NSSelectorFromString(@"currentVideoMediaTime");
        mediaTimeSel = NSSelectorFromString(@"mediaTime");
        seekToTimeSel = NSSelectorFromString(@"seekToTime:");
        didSeekToTimeSel = NSSelectorFromString(@"didSeekToTime:toleranceBefore:toleranceAfter:");
    });

    UIResponder *responder = view;
    while (responder != nil) {
        BOOL hasTime = [responder respondsToSelector:currentMediaTimeSel] ||
                       [responder respondsToSelector:mediaTimeSel];
        BOOL canSeek = [responder respondsToSelector:seekToTimeSel] ||
                       [responder respondsToSelector:didSeekToTimeSel];
        if (hasTime && canSeek) {
            return responder;
        }
        responder = responder.nextResponder;
    }
    return nil;
}

- (double)doubleFromResponder:(id)responder selectors:(NSArray<NSString *> *)names {
    for (NSString *name in names) {
        SEL selector = NSSelectorFromString(name);
        if ([responder respondsToSelector:selector]) {
            return ((double (*)(id, SEL))objc_msgSend)(responder, selector);
        }
    }
    return 0.0;
}

- (void)performSeek {
    id target = self.seekTarget;
    if (target == nil) {
        [self.seekDisplayLink invalidate];
        self.seekDisplayLink = nil;
        return;
    }

    self.seekTime += self.seekStep * self.seekDirection;
    double minimum = [self doubleFromResponder:target
                                     selectors:@[@"minimumSeekableTime"]];
    double maximum = [self doubleFromResponder:target
                                     selectors:@[
                                         @"maximumSeekableTime",
                                         @"currentVideoTotalTime",
                                         @"currentVideoDuration"
                                     ]];
    self.seekTime = MAX(minimum, self.seekTime);
    if (maximum > minimum) {
        self.seekTime = MIN(maximum, self.seekTime);
    }

    static SEL detailedSel;
    static SEL simpleSel;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        detailedSel = NSSelectorFromString(@"didSeekToTime:toleranceBefore:toleranceAfter:");
        simpleSel = NSSelectorFromString(@"seekToTime:");
    });

    if ([target respondsToSelector:detailedSel]) {
        ((void (*)(id, SEL, double, double, double))objc_msgSend)(
            target, detailedSel, self.seekTime, 0.0, 0.0
        );
    } else if ([target respondsToSelector:simpleSel]) {
        ((void (*)(id, SEL, double))objc_msgSend)(
            target, simpleSel, self.seekTime
        );
    }

    UIView *indicator = [self seekIndicatorInView:self.seekView];
    UIImageView *icon = objc_getAssociatedObject(self.seekView, YTKACESeekIconAssociation);
    UILabel *label = objc_getAssociatedObject(self.seekView, YTKACESeekLabelAssociation);
    NSString *symbol = self.seekDirection < 0 ? @"gobackward" : @"goforward";
    icon.image = [[UIImage systemImageNamed:symbol]
        imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    NSInteger seconds = MAX(0, (NSInteger)llround(self.seekTime));
    label.text = [NSString stringWithFormat:@"%ld:%02ld",
                  (long)(seconds / 60), (long)(seconds % 60)];
    indicator.center = CGPointMake(CGRectGetMidX(self.seekView.bounds),
                                   CGRectGetMidY(self.seekView.bounds));
    [self.seekView bringSubviewToFront:indicator];
    [UIView animateWithDuration:0.15
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ indicator.alpha = 1.0; }
                     completion:nil];
}

- (void)handleSeekTick:(CADisplayLink *)link {
    CFTimeInterval now = CACurrentMediaTime();
    if (self.lastSeekTickTime == 0.0 || (now - self.lastSeekTickTime) >= 0.1) {
        self.lastSeekTickTime = now;
        [self performSeek];
    }
}

- (void)handleHold:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        UIView *view = recognizer.view;
        self.seekTarget = [self seekResponderForView:view];
        if (self.seekTarget == nil) {
            return;
        }
        self.seekView = view;
        CGPoint location = [recognizer locationInView:view];
        self.seekDirection =
            location.x < CGRectGetMidX(view.bounds) ? -1 : 1;
        self.seekTime = [self doubleFromResponder:self.seekTarget
                                       selectors:@[
                                           @"currentVideoMediaTime",
                                           @"mediaTime"
                                       ]];
        [self performSeek];
        [self.seekDisplayLink invalidate];
        self.lastSeekTickTime = CACurrentMediaTime();
        CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(handleSeekTick:)];
        if (@available(iOS 15.0, *)) {
            link.preferredFrameRateRange = CAFrameRateRangeMake(30.0f, 60.0f, 120.0f);
        }
        [link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        self.seekDisplayLink = link;
    } else if (recognizer.state == UIGestureRecognizerStateEnded ||
               recognizer.state == UIGestureRecognizerStateCancelled ||
               recognizer.state == UIGestureRecognizerStateFailed) {
        [self.seekDisplayLink invalidate];
        self.seekDisplayLink = nil;
        UIView *indicator = [self seekIndicatorInView:self.seekView];
        [UIView animateWithDuration:0.25
                              delay:0.4
                            options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
            indicator.alpha = 0.0;
        } completion:nil];
        self.seekTarget = nil;
        self.seekView = nil;
    }
}

@end

static void YTKACEAttachPlayerGestures(UIView *playerView,
                                       NSInteger surface) {
    if (![playerView isKindOfClass:UIView.class]) return;
    UIGestureRecognizer *existing = objc_getAssociatedObject(
        playerView, YTKACEEdgePanAssociation);
    if (existing != nil) return;

    UIPanGestureRecognizer *edgePan =
        [[YTKACEPriorityPanGestureRecognizer alloc]
            initWithTarget:YTKACEGestureCoordinator.sharedCoordinator
                    action:@selector(handleEdgePan:)];
    edgePan.minimumNumberOfTouches = 1;
    edgePan.maximumNumberOfTouches = 2;
    edgePan.cancelsTouchesInView = YES;
    edgePan.delaysTouchesBegan = NO;
    edgePan.delaysTouchesEnded = NO;
    edgePan.delegate = YTKACEGestureCoordinator.sharedCoordinator;
    objc_setAssociatedObject(edgePan,
                             YTKACEGestureSurfaceAssociation,
                             @(surface),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    [playerView addGestureRecognizer:edgePan];
    objc_setAssociatedObject(playerView,
                             YTKACEEdgePanAssociation,
                             edgePan,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (UIGestureRecognizer *native in [playerView.gestureRecognizers copy]) {
        if (native != edgePan &&
            [native isKindOfClass:UIPanGestureRecognizer.class]) {
            [native requireGestureRecognizerToFail:edgePan];
        }
    }

    UILongPressGestureRecognizer *hold =
        [[UILongPressGestureRecognizer alloc]
            initWithTarget:YTKACEGestureCoordinator.sharedCoordinator
                    action:@selector(handleHold:)];
    hold.minimumPressDuration = 0.5;
    hold.cancelsTouchesInView = YES;
    hold.delegate = YTKACEGestureCoordinator.sharedCoordinator;
    [playerView addGestureRecognizer:hold];
    objc_setAssociatedObject(playerView,
                             YTKACELongPressAssociation,
                             hold,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void YTKACEOverlayDidMoveToWindow(UIView *receiver, SEL selector) {
    if (OriginalOverlayDidMoveToWindow != NULL) {
        ((void (*)(id, SEL))OriginalOverlayDidMoveToWindow)(receiver, selector);
    }
    YTKACEAttachPlayerGestures(receiver, 1);
}

void YTKACEInstallPlayerGestureHooks(void) {
    YTKACEInstallInstanceHook(
        @"YTMainAppVideoPlayerOverlayView",
        @"didMoveToWindow",
        (IMP)YTKACEOverlayDidMoveToWindow,
        &OriginalOverlayDidMoveToWindow
    );
}
