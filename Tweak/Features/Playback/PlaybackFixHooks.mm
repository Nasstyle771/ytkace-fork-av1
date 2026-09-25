/*
 * Playback error recovery adapted from YTPlaybackFix by Mark02.
 * https://github.com/Mark02-2012/YTPlaybackFix
 *
 * Copyright (c) 2026 Mark02
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#import "../../YTKACE.h"
#import "../../Runtime/Hooking.h"
#import "../../Runtime/Preferences.h"
#import "../Downloads/DownloadLog.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#include "PlaybackWatchdog.hpp"

static NSString *const YTKACEPlaybackFixKey = @"YTKACE.Preference.Playback.Fix";

static NSString *const YTKACEPlaybackErrorDomain =
    @"com.google.ios.youtube.ErrorDomain.playback";

static ytkace::PlaybackWatchdog gWatchdog;
static dispatch_source_t gWatchdogTimer = nil;
static double gLatestTime = 0.0;
static double gLastObservedProgressTime = 0.0;
static __weak id gActivePlayerController = nil;
static __weak id gActiveOverlayController = nil;

static IMP OriginalCurrentVideoMediaTime;
static IMP OriginalSeekToTime;
static IMP OriginalHandleError;

static BOOL YTKACEPlaybackFixEnabled(void) {
    return YTKACEFeatureEnabled(YTKACEPlaybackFixKey);
}

static id YTKACEParentResponder(id overlay) {
    SEL responderGetter = NSSelectorFromString(@"parentResponder");
    if (![overlay respondsToSelector:responderGetter]) {
        YTKACEDownloadLog(@"fix", @"parentResponder unavailable");
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(overlay, responderGetter);
}

static void YTKACESendRetryEvent(id overlay, NSString *stage) {
    id responder = YTKACEParentResponder(overlay);
    if (responder == nil) {
        YTKACEDownloadLog(@"fix", @"%@ no responder", stage);
        return;
    }
    Class eventClass = NSClassFromString(@"YTPlayerTapToRetryResponderEvent");
    SEL factory = NSSelectorFromString(@"eventWithFirstResponder:");
    if (eventClass == Nil || ![eventClass respondsToSelector:factory]) {
        YTKACEDownloadLog(@"fix", @"%@ event class missing", stage);
        return;
    }
    id event = ((id (*)(Class, SEL, id))objc_msgSend)(eventClass, factory,
                                                      responder);
    SEL send = NSSelectorFromString(@"send");
    if (event == nil || ![event respondsToSelector:send]) {
        YTKACEDownloadLog(@"fix", @"%@ event not created", stage);
        return;
    }
    ((void (*)(id, SEL))objc_msgSend)(event, send);
    YTKACEDownloadLog(@"fix", @"%@ retry event sent to %@", stage,
                      NSStringFromClass([responder class]));
}

static void YTKACESeek(id player, double position, NSString *stage) {
    if (player == nil) return;
    SEL seek = NSSelectorFromString(@"seekToTime:");
    if (![player respondsToSelector:seek]) {
        YTKACEDownloadLog(@"fix", @"%@ seek unavailable", stage);
        return;
    }
    ((void (*)(id, SEL, double))objc_msgSend)(player, seek, position);
    YTKACEDownloadLog(@"fix", @"%@ seek %.2f", stage, position);
}

static void YTKACEReplay(id player, NSString *stage) {
    if (player == nil) return;
    SEL replay = NSSelectorFromString(@"replay");
    if (![player respondsToSelector:replay]) {
        YTKACEDownloadLog(@"fix", @"%@ replay unavailable on %@", stage,
                          NSStringFromClass([player class]));
        return;
    }
    ((void (*)(id, SEL))objc_msgSend)(player, replay);
    YTKACEDownloadLog(@"fix", @"%@ replay sent", stage);
}

static void YTKACEScheduleCaptionRestore(id player) {
    if (player == nil) return;
    __weak id weakPlayer = player;
    const double delays[] = { 0.6, 1.5, 3.0 };
    for (size_t index = 0; index < sizeof(delays) / sizeof(delays[0]); index++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(delays[index] * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            YTKACECaptionsRestore(weakPlayer);
        });
    }
}

static void YTKACECancelWatchdogTimer(void) {
    if (gWatchdogTimer != nil) {
        dispatch_source_cancel(gWatchdogTimer);
        gWatchdogTimer = nil;
    }
}

static void YTKACEWatchdogTimerFired(void);

static void YTKACEArmWatchdogTimer(double seconds) {
    YTKACECancelWatchdogTimer();
    if (seconds <= 0.0) return;
    gWatchdogTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    if (gWatchdogTimer == nil) return;
    dispatch_source_set_timer(gWatchdogTimer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)),
                              DISPATCH_TIME_FOREVER,
                              (int64_t)(0.02 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(gWatchdogTimer, ^{
        YTKACEWatchdogTimerFired();
    });
    dispatch_resume(gWatchdogTimer);
}

static void YTKACEApplyWatchdogOutcome(const ytkace::WatchdogOutcome &outcome) {
    if (outcome.cancelTimers) {
        YTKACECancelWatchdogTimer();
    }
    if (outcome.armTimerIn > 0.0) {
        YTKACEArmWatchdogTimer(outcome.armTimerIn);
    }
    switch (outcome.action) {
        case ytkace::WatchdogAction::None:
            break;
        case ytkace::WatchdogAction::Resume: {
            YTKACEDownloadLog(@"fix", @"watchdog ladder: Resume at %.2f", gLatestTime);
            id player = gActivePlayerController;
            if (player != nil) {
                YTKACECaptionsSnapshot(player);
                SEL playSel = NSSelectorFromString(@"play");
                if ([player respondsToSelector:playSel]) {
                    ((void (*)(id, SEL))objc_msgSend)(player, playSel);
                }
            }
            if (gActiveOverlayController != nil) {
                YTKACESendRetryEvent(gActiveOverlayController, @"watchdog-resume");
            }
            break;
        }
        case ytkace::WatchdogAction::Nudge: {
            YTKACEDownloadLog(@"fix", @"watchdog ladder: Nudge at %.2f", gLatestTime);
            id player = gActivePlayerController;
            if (player != nil) {
                YTKACESeek(player, gLatestTime, @"watchdog-nudge");
                YTKACEReplay(player, @"watchdog-nudge");
                YTKACEScheduleCaptionRestore(player);
            }
            break;
        }
        case ytkace::WatchdogAction::Reload: {
            YTKACEDownloadLog(@"fix", @"watchdog ladder: Reload at %.2f", gLatestTime);
            if (gActiveOverlayController != nil) {
                YTKACESendRetryEvent(gActiveOverlayController, @"watchdog-reload");
            }
            id player = gActivePlayerController;
            if (player != nil) {
                YTKACESeek(player, gLatestTime, @"watchdog-reload");
                YTKACEReplay(player, @"watchdog-reload");
                YTKACEScheduleCaptionRestore(player);
            }
            break;
        }
    }
}

static void YTKACEWatchdogTimerFired(void) {
    YTKACECancelWatchdogTimer();
    const double now = CACurrentMediaTime();
    ytkace::WatchdogOutcome outcome = gWatchdog.handle(ytkace::WatchdogEvent::TimerFired, now, gLatestTime);
    YTKACEApplyWatchdogOutcome(outcome);
}

static double YTKACECurrentVideoMediaTime(id receiver, SEL selector) {
    const double value = OriginalCurrentVideoMediaTime == NULL
        ? 0.0
        : ((double (*)(id, SEL))OriginalCurrentVideoMediaTime)(receiver, selector);
    gLatestTime = value;
    gActivePlayerController = receiver;
    if (YTKACEPlaybackFixEnabled()) {
        const double now = CACurrentMediaTime();
        if (now - gLastObservedProgressTime >= 0.25) {
            gLastObservedProgressTime = now;
            ytkace::WatchdogOutcome outcome = gWatchdog.handle(ytkace::WatchdogEvent::ProgressObserved, now, value);
            YTKACEApplyWatchdogOutcome(outcome);
        }
    }
    return value;
}

static void YTKACESeekToTime(id receiver, SEL selector, double time) {
    gLatestTime = time;
    gActivePlayerController = receiver;
    if (YTKACEPlaybackFixEnabled()) {
        const double now = CACurrentMediaTime();
        ytkace::WatchdogOutcome outcome = gWatchdog.handle(ytkace::WatchdogEvent::UserScrub, now, time);
        YTKACEApplyWatchdogOutcome(outcome);
    }
    if (OriginalSeekToTime != NULL) {
        ((void (*)(id, SEL, double))OriginalSeekToTime)(receiver, selector, time);
    }
}

static void YTKACECallOriginalHandleError(id receiver, SEL selector, id error) {
    if (OriginalHandleError != NULL) {
        ((void (*)(id, SEL, id))OriginalHandleError)(receiver, selector, error);
    }
}

static void YTKACEHandleError(id receiver, SEL selector, id error) {
    if (!YTKACEPlaybackFixEnabled()) {
        YTKACECallOriginalHandleError(receiver, selector, error);
        return;
    }

    gActiveOverlayController = receiver;
    NSError *failure = [error isKindOfClass:NSError.class] ? (NSError *)error : nil;
    BOOL isPlaybackError = NO;
    if (failure != nil) {
        YTKACEDownloadLog(@"fix", @"handleError domain=%@ code=%ld",
                          failure.domain, (long)failure.code);
        if ([failure.domain isEqualToString:YTKACEPlaybackErrorDomain] &&
            (failure.code == 14 || failure.code == 0)) {
            isPlaybackError = YES;
        } else if ([failure.domain isEqualToString:NSURLErrorDomain]) {
            // Network dropout: lost connection, timeout, cannot connect
            isPlaybackError = YES;
        }
    }

    if (isPlaybackError) {
        SEL parentGetter = NSSelectorFromString(@"parentViewController");
        if ([receiver respondsToSelector:parentGetter]) {
            id pvc = ((id (*)(id, SEL))objc_msgSend)(receiver, parentGetter);
            if (pvc != nil) gActivePlayerController = pvc;
        }
        const double now = CACurrentMediaTime();
        ytkace::WatchdogOutcome outcome = gWatchdog.handle(ytkace::WatchdogEvent::ErrorReported, now, gLatestTime);
        YTKACEApplyWatchdogOutcome(outcome);
        return;
    }

    YTKACECallOriginalHandleError(receiver, selector, error);
}

static void YTKACEPlaybackStalledNotification(NSNotification *note) {
    (void)note;
    if (!YTKACEPlaybackFixEnabled()) return;
    const double now = CACurrentMediaTime();
    ytkace::WatchdogOutcome outcome = gWatchdog.handle(ytkace::WatchdogEvent::StalledState, now, gLatestTime);
    YTKACEApplyWatchdogOutcome(outcome);
}

void YTKACEInstallPlaybackFixHooks(void) {
    const BOOL time = YTKACEInstallInstanceHook(
        @"YTPlayerViewController", @"currentVideoMediaTime",
        (IMP)YTKACECurrentVideoMediaTime, &OriginalCurrentVideoMediaTime);
    const BOOL seek = YTKACEInstallInstanceHook(
        @"YTPlayerViewController", @"seekToTime:",
        (IMP)YTKACESeekToTime, &OriginalSeekToTime);
    const BOOL handle = YTKACEInstallInstanceHook(
        @"YTMainAppVideoPlayerOverlayViewController", @"handleError:",
        (IMP)YTKACEHandleError, &OriginalHandleError);

    [NSNotificationCenter.defaultCenter
        addObserverForName:AVPlayerItemPlaybackStalledNotification
                    object:nil
                     queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *note) {
        YTKACEPlaybackStalledNotification(note);
    }];

    YTKACEDownloadLog(@"fix", @"hooks time=%d seek=%d handle=%d enabled=%d",
                      time, seek, handle, YTKACEPlaybackFixEnabled());
}
