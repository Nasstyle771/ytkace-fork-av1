#import "SponsorClient.h"
#import "SponsorPreferences.h"
#import <math.h>

static NSString *YTKACESponsorDiskCacheDirectory(void) {
    static NSString *dir;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *caches = [NSSearchPathForDirectoriesInDomains(
            NSCachesDirectory, NSUserDomainMask, YES) firstObject];
        dir = [caches stringByAppendingPathComponent:@"YTKACESponsorBlock"];
        [NSFileManager.defaultManager createDirectoryAtPath:dir
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:nil];
    });
    return dir;
}

static NSString *YTKACESponsorDiskPathForKey(NSString *key) {
    NSMutableString *safe = [NSMutableString stringWithCapacity:key.length];
    for (NSUInteger i = 0; i < key.length; i++) {
        unichar c = [key characterAtIndex:i];
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') || c == '-' || c == '_') {
            [safe appendFormat:@"%C", c];
        } else {
            [safe appendString:@"_"];
        }
    }
    if (safe.length > 70) {
        safe = [[safe substringToIndex:70] mutableCopy];
    }
    NSString *filename = [NSString stringWithFormat:@"sb_%@_%lx.json", safe, (unsigned long)[key hash]];
    return [YTKACESponsorDiskCacheDirectory() stringByAppendingPathComponent:filename];
}

static dispatch_queue_t YTKACESponsorDiskQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.ytkace.sponsorblock.disk", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static NSArray *YTKACESponsorLoadFromDisk(NSString *key) {
    NSString *path = YTKACESponsorDiskPathForKey(key);
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length == 0) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if ([json isKindOfClass:NSDictionary.class]) {
        id segs = json[@"segments"];
        if ([segs isKindOfClass:NSArray.class]) {
            return segs;
        }
    } else if ([json isKindOfClass:NSArray.class]) {
        return json;
    }
    return nil;
}

static void YTKACESponsorSaveToDisk(NSString *key, NSArray *segments) {
    dispatch_async(YTKACESponsorDiskQueue(), ^{
        NSString *path = YTKACESponsorDiskPathForKey(key);
        NSDictionary *wrapper = @{
            @"v": @1,
            @"t": @(NSDate.date.timeIntervalSince1970),
            @"segments": segments ?: @[]
        };
        NSData *data = [NSJSONSerialization dataWithJSONObject:wrapper options:0 error:nil];
        if (data != nil) {
            [data writeToFile:path atomically:YES];
        }
    });
}

@interface YTKACESponsorClient ()
@property(nonatomic, strong) NSCache<NSString *, NSArray *> *cache;
@property(nonatomic, strong) NSURLSession *session;
@end

@implementation YTKACESponsorClient

+ (instancetype)sharedClient {
    static YTKACESponsorClient *client;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        client = [YTKACESponsorClient new];
    });
    return client;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [NSCache new];
        _cache.countLimit = 256;

        NSURLSessionConfiguration *configuration =
            NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.timeoutIntervalForRequest = 6.0;
        configuration.timeoutIntervalForResource = 10.0;
        configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        _session = [NSURLSession sessionWithConfiguration:configuration];
    }
    return self;
}

- (void)clearCache {
    [self.cache removeAllObjects];
    dispatch_async(YTKACESponsorDiskQueue(), ^{
        NSString *dir = YTKACESponsorDiskCacheDirectory();
        NSArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *file in files) {
            NSString *fullPath = [dir stringByAppendingPathComponent:file];
            [NSFileManager.defaultManager removeItemAtPath:fullPath error:nil];
        }
    });
}

- (void)segmentsForVideoID:(NSString *)videoID
                completion:(YTKACESponsorCompletion)completion {
    if (videoID.length == 0) {
        completion(@[]);
        return;
    }

    NSArray<NSString *> *categories = YTKACESponsorEnabledCategories();
    if (categories.count == 0) {
        completion(@[]);
        return;
    }
    NSString *cacheKey = [NSString stringWithFormat:@"%@|%@", videoID,
                          [categories componentsJoinedByString:@","]];

    // 1. Fast in-memory cache check
    NSArray *cached = [self.cache objectForKey:cacheKey];
    if (cached != nil) {
        completion(cached);
        return;
    }

    // 2. Persistent disk cache check
    NSArray *diskCached = YTKACESponsorLoadFromDisk(cacheKey);
    if (diskCached != nil) {
        [self.cache setObject:diskCached forKey:cacheKey];
        completion(diskCached);
        return;
    }

    NSURLComponents *components =
        [NSURLComponents componentsWithString:@"https://sponsor.ajay.app/api/skipSegments"];
    NSData *categoryData = [NSJSONSerialization dataWithJSONObject:categories
                                                            options:0 error:nil];
    NSString *categoryJSON = categoryData == nil ? @"[]" :
        [[NSString alloc] initWithData:categoryData encoding:NSUTF8StringEncoding];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"videoID" value:videoID],
        [NSURLQueryItem queryItemWithName:@"categories" value:categoryJSON]
    ];
    NSURL *url = components.URL;
    if (url == nil) {
        completion(@[]);
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"GET";
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    __weak YTKACESponsorClient *weakSelf = self;
    NSURLSessionDataTask *task =
        [self.session dataTaskWithRequest:request
                       completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSMutableArray<NSDictionary<NSString *, id> *> *segments =
            [NSMutableArray array];
        NSHTTPURLResponse *http =
            [response isKindOfClass:NSHTTPURLResponse.class]
                ? (NSHTTPURLResponse *)response
                : nil;

        // If offline or network error, fallback to disk cache if available
        if (error != nil) {
            NSArray *fallback = YTKACESponsorLoadFromDisk(cacheKey) ?: @[];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(fallback);
            });
            return;
        }

        // SponsorBlock returns 404 when no segments exist for the video
        if (http.statusCode == 404) {
            [weakSelf.cache setObject:@[] forKey:cacheKey];
            YTKACESponsorSaveToDisk(cacheKey, @[]);
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(@[]);
            });
            return;
        }

        if (http.statusCode == 200 && data.length <= 1024 * 1024) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:NSArray.class]) {
                for (id item in (NSArray *)json) {
                    if (![item isKindOfClass:NSDictionary.class]) {
                        continue;
                    }
                    id category = item[@"category"];
                    id values = item[@"segment"];
                    id actionType = item[@"actionType"];
                    if (![category isKindOfClass:NSString.class] ||
                        ![categories containsObject:category] ||
                        ([actionType isKindOfClass:NSString.class] &&
                         ![actionType isEqualToString:@"skip"]) ||
                        ![values isKindOfClass:NSArray.class] ||
                        [values count] != 2) {
                        continue;
                    }
                    id startValue = values[0];
                    id endValue = values[1];
                    if (![startValue isKindOfClass:NSNumber.class] ||
                        ![endValue isKindOfClass:NSNumber.class]) {
                        continue;
                    }
                    double start = [startValue doubleValue];
                    double end = [endValue doubleValue];
                    if (!isfinite(start) || !isfinite(end) || start < 0.0 || end <= start) {
                        continue;
                    }
                    [segments addObject:@{@"start": @(start), @"end": @(end),
                                          @"category": category}];
                }
            }
        }

        NSArray *result = [segments sortedArrayUsingComparator:
            ^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
                return [left[@"start"] compare:right[@"start"]];
            }];

        [weakSelf.cache setObject:result forKey:cacheKey];
        YTKACESponsorSaveToDisk(cacheKey, result);

        dispatch_async(dispatch_get_main_queue(), ^{
            completion(result);
        });
    }];
    [task resume];
}

@end
