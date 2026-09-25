#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT CGFloat YTKACEDownloadProgressRatio(NSURL *URL);

@class AVPlayer;

extern NSNotificationName const YTKACEDownloadPlaybackDidChangeNotification;
extern NSNotificationName const YTKACEDownloadPlaybackDidStopNotification;

@interface YTKACEDownloadPlaybackSession : NSObject

+ (instancetype)sharedSession;

@property(atomic, strong, readonly) AVPlayer *player;
@property(atomic, copy, readonly, nullable) NSURL *currentURL;
@property(atomic, copy, readonly) NSArray<NSURL *> *playlist;
@property(atomic, assign, readonly) NSInteger currentIndex;
@property(atomic, assign) BOOL autoplayEnabled;
@property(atomic, assign) BOOL gesturesEnabled;
@property(atomic, assign) BOOL repeatEnabled;
@property(atomic, assign) BOOL pauseAtEnd;
@property(atomic, assign) float playbackRate;

- (void)loadURL:(NSURL *)URL
       playlist:(NSArray<NSURL *> *)playlist
          index:(NSInteger)index;
- (void)updatePlaylist:(NSArray<NSURL *> *)playlist;
- (void)play;
- (void)pause;
- (void)togglePlayback;
- (void)seekBy:(NSTimeInterval)seconds;
- (void)playNext;
- (void)playPrevious;
- (void)stop;

@end

@interface YTKACEDownloadPlayerController : UIViewController

- (instancetype)initWithSession:(YTKACEDownloadPlaybackSession *)session;
@property(nonatomic, copy, nullable) dispatch_block_t minimizeHandler;

@end

NS_ASSUME_NONNULL_END
