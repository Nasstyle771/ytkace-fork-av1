#import "StreamResolver.h"
#import "DownloadLog.h"
#import "../../Runtime/Localization.h"
#import "../../Runtime/Preferences.h"

#import <UIKit/UIKit.h>
#import <VideoToolbox/VideoToolbox.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <stdlib.h>
#import <string.h>

static BOOL YTKACEDeviceSupportsHardwareAV1(void) {
    static dispatch_once_t onceToken;
    static BOOL supported = NO;
    dispatch_once(&onceToken, ^{
        if (&VTIsHardwareDecodeSupported != NULL) {
            supported = VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1);
        }
    });
    return supported;
}

static BOOL YTKACEDeviceSupportsHardwareVP9(void) {
    static dispatch_once_t onceToken;
    static BOOL supported = NO;
    dispatch_once(&onceToken, ^{
        if (&VTIsHardwareDecodeSupported != NULL) {
            supported = VTIsHardwareDecodeSupported(kCMVideoCodecType_VP9);
        }
    });
    return supported;
}

@implementation YTKACEStreamOption
@synthesize codecLabel = _codecLabel;

- (BOOL)isAV1 {
    NSString *mime = self.mimeType.lowercaseString;
    if ([mime containsString:@"av01"] || [mime containsString:@"av1"]) return YES;
    NSString *tags = self.xtags.lowercaseString;
    if ([tags containsString:@"av01"] || [tags containsString:@"av1"]) return YES;
    if ((self.itag >= 394 && self.itag <= 402) || self.itag == 571 || (self.itag >= 694 && self.itag <= 702)) return YES;
    return NO;
}

- (BOOL)isH264 {
    NSString *mime = self.mimeType.lowercaseString;
    if ([mime containsString:@"avc1"] || [mime containsString:@"h264"] || [mime containsString:@"mp4v"]) return YES;
    NSString *tags = self.xtags.lowercaseString;
    if ([tags containsString:@"avc1"] || [tags containsString:@"h264"]) return YES;
    if ((self.itag >= 133 && self.itag <= 137) || self.itag == 264 || self.itag == 266 || self.itag == 18 || self.itag == 22) return YES;
    return NO;
}

- (BOOL)isVP9 {
    NSString *mime = self.mimeType.lowercaseString;
    if ([mime containsString:@"vp09"] || [mime containsString:@"vp9"]) return YES;
    NSString *tags = self.xtags.lowercaseString;
    if ([tags containsString:@"vp09"] || [tags containsString:@"vp9"]) return YES;
    if ((self.itag >= 242 && self.itag <= 248) || self.itag == 271 || self.itag == 272 || self.itag == 313 || (self.itag >= 330 && self.itag <= 337)) return YES;
    return NO;
}

- (BOOL)isHardwareDecodeSupported {
    if (self.isH264) return YES;
    if (self.isAV1) return YTKACEDeviceSupportsHardwareAV1();
    if (self.isVP9) return YTKACEDeviceSupportsHardwareVP9();
    return YES;
}

- (NSString *)codecLabel {
    if (_codecLabel.length != 0) return _codecLabel;
    if (self.isAV1) return @"AV1";
    if (self.isH264) return @"H.264";
    if (self.isVP9) return @"VP9";
    NSString *mime = self.mimeType.lowercaseString;
    if ([mime containsString:@"hevc"] || [mime containsString:@"hvc1"] || [mime containsString:@"hev1"]) {
        return @"HEVC";
    }
    return @"MP4";
}

@end

static id YTKACEStreamObject(id receiver, NSArray<NSString *> *selectors) {
    for (NSString *name in selectors) {
        SEL selector = NSSelectorFromString(name);
        if ([receiver respondsToSelector:selector]) {
            id value = ((id (*)(id, SEL))objc_msgSend)(receiver, selector);
            if (value != nil) {
                return value;
            }
        }
    }
    return nil;
}

static NSInteger YTKACEStreamInteger(id receiver, NSArray<NSString *> *selectors) {
    for (NSString *name in selectors) {
        SEL selector = NSSelectorFromString(name);
        if ([receiver respondsToSelector:selector]) {
            return ((NSInteger (*)(id, SEL))objc_msgSend)(receiver, selector);
        }
    }
    return 0;
}

static NSArray *YTKACEArrayValue(id receiver, NSArray<NSString *> *selectors) {
    id value = YTKACEStreamObject(receiver, selectors);
    return [value isKindOfClass:NSArray.class] ? value : @[];
}

static NSURL *YTKACEURLValue(id value) {
    if ([value isKindOfClass:NSURL.class]) {
        return value;
    }
    if ([value isKindOfClass:NSString.class]) {
        return [NSURL URLWithString:value];
    }
    return nil;
}

static id YTKACEFindNestedObject(id object,
                                 NSString *target,
                                 NSHashTable *visited,
                                 NSUInteger depth) {
    if (object == nil || depth > 8 || [visited containsObject:object]) {
        return nil;
    }
    [visited addObject:object];
    id value = YTKACEStreamObject(object, @[target]);
    if (value != nil) {
        return value;
    }
    for (NSString *name in @[@"playerData", @"contentPlayerResponse",
                              @"playerResponse", @"playbackData", @"video",
                              @"response", @"shortsPlayerData"]) {
        id nested = YTKACEStreamObject(object, @[name]);
        id found = YTKACEFindNestedObject(nested, target, visited, depth + 1);
        if (found != nil) {
            return found;
        }
    }
    return nil;
}

static id YTKACENestedObject(id object, NSString *target) {
    NSHashTable *visited = [NSHashTable hashTableWithOptions:
        NSPointerFunctionsObjectPointerPersonality];
    return YTKACEFindNestedObject(object, target, visited, 0);
}

static NSString *YTKACEStringValue(id value) {
    if ([value isKindOfClass:NSString.class]) {
        return value;
    }
    for (NSString *name in @[@"text", @"string", @"simpleText"]) {
        id nested = YTKACEStreamObject(value, @[name]);
        if ([nested isKindOfClass:NSString.class]) {
            return nested;
        }
    }
    return nil;
}

static NSInteger YTKACEQualityHeight(NSString *label) {
    NSScanner *scanner = [NSScanner scannerWithString:label ?: @""];
    NSInteger height = 0;
    return [scanner scanInteger:&height] ? height : 0;
}

static NSInteger YTKACEVideoPreference(YTKACEStreamOption *option) {
    id pref = YTKACEPreferenceObject(YTKACEPreferredCodecKey);
    NSInteger preferred = [pref respondsToSelector:@selector(integerValue)] ? [pref integerValue] : 0;
    if (preferred == 1) { // Prefer AV1
        if (option.isAV1) return 4;
        if (option.isVP9) return 3;
        if (option.isH264) return 2;
    } else if (preferred == 2) { // Prefer VP9
        if (option.isVP9) return 4;
        if (option.isAV1) return 3;
        if (option.isH264) return 2;
    } else if (preferred == 3) { // Prefer H.264
        if (option.isH264) return 4;
        if (option.isAV1) return 3;
        if (option.isVP9) return 2;
    } else { // Auto (Optimal): Use hardware capability to avoid software decode thermal/battery stalls
        BOOL hasHWAV1 = YTKACEDeviceSupportsHardwareAV1();
        BOOL hasHWVP9 = YTKACEDeviceSupportsHardwareVP9();
        if (hasHWAV1) {
            if (option.isAV1) return 4;
            if (option.isVP9) return 3;
            if (option.isH264) return 2;
        } else if (hasHWVP9) {
            if (option.isVP9) return 4;
            if (option.isH264) return 3;
            if (option.isAV1) return 2;
        } else {
            if (option.isH264) return 4;
            if (option.isAV1) return 3;
            if (option.isVP9) return 2;
        }
    }
    return 1;
}

static BOOL YTKACEHighResolutionSupported(YTKACEStreamOption *option) {
    (void)option;
    return YES;
}

static NSString *YTKACEVideoRejectReason(YTKACEStreamOption *option) {
    if (![option.mimeType hasPrefix:@"video/"]) return @"not video";
    if (option.itag <= 0) return @"no itag";
    if (![option.mimeType containsString:@"video/mp4"] &&
        ![option.mimeType containsString:@"video/webm"]) {
        return @"container unsupported";
    }
    if (option.height <= 0) return @"no height";
    return nil;
}

static id YTKACEPlayerData(id playerResponse) {
    return YTKACENestedObject(playerResponse, @"playerData") ?: playerResponse;
}

static id YTKACEVideoDetails(id playerResponse) {
    return YTKACENestedObject(playerResponse, @"videoDetails") ?:
        YTKACEPlayerData(playerResponse);
}

static id YTKACEStreamingData(id playerResponse) {
    id direct = YTKACEStreamObject(playerResponse, @[@"streamingData"]);
    return direct ?: YTKACEStreamObject(YTKACEPlayerData(playerResponse),
                                         @[@"streamingData"]);
}


static YTKACEStreamOption *YTKACEOptionFromFormat(id format, BOOL adaptive) {
    NSURL *url = YTKACEURLValue(YTKACEStreamObject(format, @[@"URL", @"url"]));
    if (url != nil && ![url.scheme.lowercaseString hasPrefix:@"http"]) {
        url = nil;
    }

    NSString *mime = YTKACEStreamObject(format, @[@"mimeType"]);
    if (![mime isKindOfClass:NSString.class]) {
        mime = @"application/octet-stream";
    }

    YTKACEStreamOption *option = [YTKACEStreamOption new];
    option.URL = url;
    option.mimeType = mime;
    option.qualityLabel = YTKACEStreamObject(format, @[@"qualityLabel", @"audioQuality"]) ?: @"";
    option.xtags = YTKACEStreamObject(format, @[@"xtags"]) ?: @"";
    option.bitrate = YTKACEStreamInteger(format, @[@"bitrate"]);
    option.itag = YTKACEStreamInteger(format, @[@"itag"]);
    option.contentLength = YTKACEStreamInteger(format, @[@"contentLength"]);
    option.lastModified = YTKACEStreamInteger(format, @[@"lastModified"]);
    option.width = YTKACEStreamInteger(format, @[@"width"]);
    option.height = YTKACEStreamInteger(format, @[@"height"]);
    option.audioOnly = [mime hasPrefix:@"audio/"] ||
        (adaptive && ![mime hasPrefix:@"video/"]);
    option.adaptive = adaptive;
    option.rawFormat = format;
    id audioTrack = YTKACEStreamObject(format, @[@"audioTrack"]);
    NSString *language = YTKACEStringValue(YTKACEStreamObject(
        audioTrack, @[@"displayName", @"display_name", @"name"]));
    if (language.length == 0) {
        NSString *description = [audioTrack description];
        NSRange marker = [description rangeOfString:@"display_name: \""];
        if (marker.location != NSNotFound) {
            NSUInteger start = NSMaxRange(marker);
            NSRange rest = NSMakeRange(start, description.length - start);
            NSRange end = [description rangeOfString:@"\"" options:0 range:rest];
            if (end.location != NSNotFound) {
                language = [description substringWithRange:
                    NSMakeRange(start, end.location - start)];
            }
        }
    }
    option.languageLabel = language.length != 0 ? language : YTKACELocalized(@"Original audio");
    NSString *trackID = YTKACEStringValue(YTKACEStreamObject(
        audioTrack, @[@"id_p", @"audioTrackId", @"audioTrackID"]));
    if (trackID.length == 0) {
        NSString *description = [audioTrack description];
        NSRange marker = [description rangeOfString:@"id: \""];
        if (marker.location != NSNotFound) {
            NSUInteger start = NSMaxRange(marker);
            NSRange rest = NSMakeRange(start, description.length - start);
            NSRange end = [description rangeOfString:@"\"" options:0 range:rest];
            if (end.location != NSNotFound) {
                trackID = [description substringWithRange:
                    NSMakeRange(start, end.location - start)];
            }
        }
    }
    option.audioTrackID = trackID ?: @"";
    option.defaultAudio = YTKACEStreamInteger(
        audioTrack, @[@"audioIsDefault", @"isDefault", @"defaultAudio"]) != 0;
    return option;
}

@implementation YTKACEStreamResolver

+ (NSArray<YTKACEStreamOption *> *)optionsFromPlayerResponse:(id)playerResponse {
    id streamingData = YTKACEStreamingData(playerResponse);
    if (streamingData == nil) {
        return @[];
    }
    NSMutableArray<YTKACEStreamOption *> *result = [NSMutableArray array];
    for (id format in YTKACEArrayValue(streamingData, @[@"formatsArray", @"formats"])) {
        YTKACEStreamOption *option = YTKACEOptionFromFormat(format, NO);
        if (option != nil) {
            [result addObject:option];
        }
    }
    for (id format in YTKACEArrayValue(
             streamingData,
             @[@"adaptiveFormatsArray", @"adaptiveFormats"])) {
        YTKACEStreamOption *option = YTKACEOptionFromFormat(format, YES);
        if (option != nil) {
            [result addObject:option];
        }
    }
    return result;
}

+ (NSArray<YTKACEStreamOption *> *)videoOptionsFromPlayerResponse:(id)playerResponse {
    NSArray *options = [self optionsFromPlayerResponse:playerResponse];
    NSMutableDictionary<NSString *, YTKACEStreamOption *> *byQualityAndCodec =
        [NSMutableDictionary dictionary];
    YTKACEDownloadLog(@"quality", @"formats=%lu video=%@",
        (unsigned long)options.count,
        [self videoIDFromPlayerResponse:playerResponse] ?: @"?");
    for (YTKACEStreamOption *option in options) {
        if (option.height <= 0) {
            option.height = YTKACEQualityHeight(option.qualityLabel);
        }
        NSString *reason = YTKACEVideoRejectReason(option);
        if (reason != nil) {
            continue;
        }
        NSString *codec = option.codecLabel ?: @"Video";
        NSString *key = [NSString stringWithFormat:@"%ldp-%@", (long)option.height, codec];
        YTKACEStreamOption *current = byQualityAndCodec[key];
        if (current == nil || option.bitrate > current.bitrate) {
            byQualityAndCodec[key] = option;
        }
    }
    for (YTKACEStreamOption *option in byQualityAndCodec.allValues) {
        if (option.qualityLabel.length != 0 && option.codecLabel.length != 0 &&
            ![option.qualityLabel containsString:@"("]) {
            option.qualityLabel = [NSString stringWithFormat:@"%@ (%@)", option.qualityLabel, option.codecLabel];
        }
    }
    return [byQualityAndCodec.allValues sortedArrayUsingComparator:
        ^NSComparisonResult(YTKACEStreamOption *left, YTKACEStreamOption *right) {
            if (left.height != right.height) {
                return left.height > right.height ? NSOrderedAscending : NSOrderedDescending;
            }
            NSInteger leftPref = YTKACEVideoPreference(left);
            NSInteger rightPref = YTKACEVideoPreference(right);
            if (leftPref != rightPref) {
                return leftPref > rightPref ? NSOrderedAscending : NSOrderedDescending;
            }
            return left.bitrate > right.bitrate ? NSOrderedAscending : NSOrderedDescending;
        }];
}

+ (NSArray<YTKACEStreamOption *> *)audioOptionsFromPlayerResponse:(id)playerResponse {
    NSArray *options = [self optionsFromPlayerResponse:playerResponse];
    NSMutableDictionary<NSString *, YTKACEStreamOption *> *byLanguage =
        [NSMutableDictionary dictionary];
    for (YTKACEStreamOption *option in options) {
        if (!option.isAudioOnly && ![option.mimeType hasPrefix:@"audio/"]) {
            continue;
        }
        NSString *key = option.languageLabel.length != 0
            ? option.languageLabel : YTKACELocalized(@"Original audio");
        YTKACEStreamOption *current = byLanguage[key];
        if (current == nil || option.isDefaultAudio || option.bitrate > current.bitrate) {
            byLanguage[key] = option;
        }
    }
    return [byLanguage.allValues sortedArrayUsingComparator:
        ^NSComparisonResult(YTKACEStreamOption *left, YTKACEStreamOption *right) {
            if (left.isDefaultAudio != right.isDefaultAudio) {
                return left.isDefaultAudio ? NSOrderedAscending : NSOrderedDescending;
            }
            return [left.languageLabel localizedCaseInsensitiveCompare:right.languageLabel];
        }];
}

+ (YTKACEStreamOption *)bestPiPVideoFromPlayerResponse:(id)playerResponse {
    id streamingData = YTKACEStreamingData(playerResponse);
    NSURL *hls = YTKACEURLValue(YTKACEStreamObject(
        streamingData,
        @[@"hlsManifestURL", @"hlsManifestUrl"]
    ));
    if (hls != nil) {
        YTKACEStreamOption *option = [YTKACEStreamOption new];
        option.URL = hls;
        option.mimeType = @"application/x-mpegURL";
        option.qualityLabel = @"HLS";
        return option;
    }
    return [self bestVideoFromPlayerResponse:playerResponse];
}

+ (YTKACEStreamOption *)bestVideoFromPlayerResponse:(id)playerResponse {
    NSArray<YTKACEStreamOption *> *options = [self optionsFromPlayerResponse:playerResponse];
    NSPredicate *video = [NSPredicate predicateWithBlock:
        ^BOOL(YTKACEStreamOption *option, NSDictionary *bindings) {
            (void)bindings;
            return !option.isAdaptive &&
                !option.isAudioOnly &&
                [option.mimeType hasPrefix:@"video/"];
        }];
    YTKACEStreamOption *best = [[options filteredArrayUsingPredicate:video]
        sortedArrayUsingComparator:^NSComparisonResult(YTKACEStreamOption *left,
                                                        YTKACEStreamOption *right) {
            if (left.bitrate == right.bitrate) {
                return NSOrderedSame;
            }
            return left.bitrate > right.bitrate ? NSOrderedAscending : NSOrderedDescending;
        }].firstObject;
    if (best != nil) return best;
    // Fallback: pick best adaptive video stream if non-adaptive formats are not present
    return [self videoOptionsFromPlayerResponse:playerResponse].firstObject;
}

+ (YTKACEStreamOption *)bestAudioFromPlayerResponse:(id)playerResponse {
    NSArray<YTKACEStreamOption *> *options = [self optionsFromPlayerResponse:playerResponse];
    NSPredicate *audio = [NSPredicate predicateWithBlock:
        ^BOOL(YTKACEStreamOption *option, NSDictionary *bindings) {
            (void)bindings;
            return option.isAudioOnly || [option.mimeType hasPrefix:@"audio/"];
        }];
    return [[options filteredArrayUsingPredicate:audio]
        sortedArrayUsingComparator:^NSComparisonResult(YTKACEStreamOption *left,
                                                        YTKACEStreamOption *right) {
            if (left.bitrate == right.bitrate) {
                return NSOrderedSame;
            }
            return left.bitrate > right.bitrate ? NSOrderedAscending : NSOrderedDescending;
        }].firstObject;
}

+ (NSString *)titleFromPlayerResponse:(id)playerResponse {
    id details = YTKACEVideoDetails(playerResponse);
    NSString *title = YTKACEStringValue(YTKACEStreamObject(
        details, @[@"title", @"videoTitle", @"headline"]));
    return title.length != 0
        ? title
        : @"YouTube Video";
}

+ (NSString *)authorFromPlayerResponse:(id)playerResponse {
    id details = YTKACEVideoDetails(playerResponse);
    NSString *author = YTKACEStringValue(YTKACEStreamObject(
        details, @[@"author", @"channelTitle", @"ownerChannelName"]));
    return author.length != 0
        ? author : @"YouTube";
}

+ (NSString *)descriptionFromPlayerResponse:(id)playerResponse {
    id details = YTKACEVideoDetails(playerResponse);
    id description = YTKACEStreamObject(details,
        @[@"shortDescription", @"videoDescription", @"descriptionText"]);
    return [description isKindOfClass:NSString.class]
        ? description : @"";
}

+ (NSString *)videoIDFromPlayerResponse:(id)playerResponse {
    id details = YTKACEVideoDetails(playerResponse);
    id videoID = YTKACEStreamObject(details, @[@"videoId", @"videoID"]);
    if (![videoID isKindOfClass:NSString.class] || [videoID length] == 0) {
        videoID = YTKACEStreamObject(playerResponse, @[@"videoId", @"videoID"]);
    }
    return [videoID isKindOfClass:NSString.class] ? videoID : nil;
}

+ (NSURL *)thumbnailURLFromPlayerResponse:(id)playerResponse {
    id details = YTKACEVideoDetails(playerResponse);
    id thumbnail = YTKACEStreamObject(details, @[@"thumbnail"]);
    NSArray *items = YTKACEArrayValue(thumbnail, @[@"thumbnailsArray", @"thumbnails"]);
    id candidate = items.lastObject;
    return YTKACEURLValue(YTKACEStreamObject(candidate, @[@"URL", @"url"]));
}

@end
