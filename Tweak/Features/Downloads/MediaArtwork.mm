#import "MediaArtwork.h"

#import <AVFoundation/AVFoundation.h>

static NSCache<NSURL *, UIImage *> *YTKACEArtworkImageCache(void) {
    static NSCache<NSURL *, UIImage *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSCache new];
        cache.countLimit = 128;
    });
    return cache;
}

static NSCache<NSURL *, NSData *> *YTKACEArtworkDataCache(void) {
    static NSCache<NSURL *, NSData *> *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [NSCache new];
        cache.countLimit = 128;
    });
    return cache;
}

NSData *YTKACEMediaArtworkData(NSURL *URL) {
    if (URL == nil) return nil;
    NSData *cached = [YTKACEArtworkDataCache() objectForKey:URL];
    if (cached != nil) return cached;

    NSURL *base = URL.URLByDeletingPathExtension;
    for (NSString *extension in @[@"jpg", @"png"]) {
        NSData *data = [NSData dataWithContentsOfURL:
            [base URLByAppendingPathExtension:extension]];
        if (data.length != 0) {
            [YTKACEArtworkDataCache() setObject:data forKey:URL];
            return data;
        }
    }
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:URL options:nil];
    NSArray<AVMetadataItem *> *items = [AVMetadataItem
        metadataItemsFromArray:asset.commonMetadata
        filteredByIdentifier:AVMetadataCommonIdentifierArtwork];
    id value = items.firstObject.value;
    NSData *result = nil;
    if ([value isKindOfClass:NSData.class]) result = value;
    else if ([value respondsToSelector:@selector(dataValue)]) result = [value dataValue];
    if (result.length != 0) {
        [YTKACEArtworkDataCache() setObject:result forKey:URL];
    }
    return result;
}

UIImage *YTKACEMediaArtworkImage(NSURL *URL) {
    if (URL == nil) return nil;
    UIImage *cached = [YTKACEArtworkImageCache() objectForKey:URL];
    if (cached != nil) return cached;

    NSData *data = YTKACEMediaArtworkData(URL);
    if (data.length == 0) return nil;
    UIImage *image = [UIImage imageWithData:data];
    if (image != nil) {
        [YTKACEArtworkImageCache() setObject:image forKey:URL];
    }
    return image;
}
