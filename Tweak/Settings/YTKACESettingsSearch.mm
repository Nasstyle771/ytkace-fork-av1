#import "YTKACESettingsSearch.h"
#import "YTKACESettingsPages.h"
#import "../Runtime/Preferences.h"
#import "../Runtime/Localization.h"
#import "../UI/Assets.h"

#import <objc/message.h>
#import <objc/runtime.h>

#include <os/lock.h>

static UIViewController *YTKACEControllerForPageID(NSString *pageID) {
    static NSDictionary<NSString *, UIViewController *(^)(void)> *builders;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        builders = @{
            @"appearance": ^UIViewController *{ return YTKACEMakeAppearanceOptionsController(); },
            @"display": ^UIViewController *{ return YTKACEMakeDisplayRateOptionsController(); },
            @"sponsorblock": ^UIViewController *{ return YTKACEMakeSponsorBlockController(); },
            @"player": ^UIViewController *{ return YTKACEMakePlayerControlsController(); },
            @"overlay": ^UIViewController *{ return YTKACEMakeOverlayOptionsController(); },
            @"playback": ^UIViewController *{ return YTKACEMakeStreamingOptionsController(); },
            @"navigation": ^UIViewController *{ return YTKACEMakeNavigationOptionsController(); },
            @"shorts": ^UIViewController *{ return YTKACEMakeShortsOptionsController(); },
            @"other": ^UIViewController *{ return YTKACEMakeMiscOptionsController(); },
            @"gestures": ^UIViewController *{ return YTKACEMakeGestureOptionsController(); }
        };
    });
    UIViewController *(^builder)(void) = builders[pageID ?: @""];
    return builder != nil ? builder() : nil;
}

@interface YTKACEIndexedItem : NSObject
@property(nonatomic, strong) NSDictionary *record;
@property(nonatomic, copy) NSString *normalizedTitle;
@property(nonatomic, copy) NSString *normalizedSubtitle;
@property(nonatomic, copy) NSString *normalizedHeader;
@property(nonatomic, copy) NSString *normalizedPageTitle;
@property(nonatomic, copy) NSArray<NSString *> *titleTokens;
@property(nonatomic, copy) NSArray<NSString *> *subtitleTokens;
@property(nonatomic, copy) NSArray<NSString *> *keywords;
@end

@implementation YTKACEIndexedItem
@end

static NSString *YTKACENormalizeString(NSString *input) {
    if (input.length == 0) return @"";
    NSMutableString *s = [input mutableCopy];
    CFStringTransform((__bridge CFMutableStringRef)s, NULL, kCFStringTransformStripCombiningMarks, NO);
    return [s.lowercaseString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSArray<NSString *> *YTKACETokenizeString(NSString *input) {
    NSString *normalized = YTKACENormalizeString(input);
    if (normalized.length == 0) return @[];
    NSCharacterSet *delimiters = [NSCharacterSet characterSetWithCharactersInString:@" \t\r\n-_/\\()[]{},.:;\"'•›"];
    NSArray *components = [normalized componentsSeparatedByCharactersInSet:delimiters];
    NSMutableArray<NSString *> *tokens = [NSMutableArray arrayWithCapacity:components.count];
    for (NSString *tok in components) {
        if (tok.length > 0) {
            [tokens addObject:tok];
        }
    }
    return tokens;
}

static NSArray<YTKACEIndexedItem *> *s_cachedIndex = nil;
static NSString *s_lastIndexedLanguage = nil;
static os_unfair_lock s_indexLock = OS_UNFAIR_LOCK_INIT;

static NSArray<YTKACEIndexedItem *> *YTKACEGetOrBuildSearchIndex(void) {
    NSString *currentLanguage = YTKACEPreferenceObject(@"YTKACE.Preference.Language") ?: @"system";
    os_unfair_lock_lock(&s_indexLock);
    if (s_cachedIndex != nil && [currentLanguage isEqualToString:s_lastIndexedLanguage]) {
        NSArray<YTKACEIndexedItem *> *result = s_cachedIndex;
        os_unfair_lock_unlock(&s_indexLock);
        return result;
    }

    NSMutableArray<YTKACEIndexedItem *> *items = [NSMutableArray array];
    for (NSDictionary *page in YTKACEAllPageDefinitions()) {
        NSArray *sections = page[@"sections"];
        NSArray *headers = page[@"headers"];
        NSString *rawPageTitle = page[@"title"] ?: @"";
        NSString *pageTitle = YTKACELocalized(rawPageTitle);
        NSString *pageID = page[@"id"] ?: @"";

        for (NSUInteger section = 0; section < sections.count; section++) {
            NSArray *sectionItems = sections[section];
            NSString *rawHeader = section < headers.count ? headers[section] : @"";
            NSString *header = rawHeader.length != 0 ? YTKACELocalized(rawHeader) : @"";

            for (NSUInteger row = 0; row < sectionItems.count; row++) {
                NSDictionary *item = sectionItems[row];
                NSString *title = item[@"title"];
                if (![title isKindOfClass:NSString.class] || title.length == 0) continue;
                if ([item[@"type"] isEqualToString:@"text"]) continue;
                NSString *subtitle = [item[@"subtitle"] isKindOfClass:NSString.class]
                    ? item[@"subtitle"] : @"";

                NSDictionary *record = @{
                    @"item": item,
                    @"pageID": pageID,
                    @"pageTitle": pageTitle,
                    @"header": header,
                    @"title": title,
                    @"subtitle": subtitle,
                    @"section": @(section),
                    @"row": @(row)
                };

                YTKACEIndexedItem *indexed = [YTKACEIndexedItem new];
                indexed.record = record;
                indexed.normalizedTitle = YTKACENormalizeString(title);
                indexed.normalizedSubtitle = YTKACENormalizeString(subtitle);
                indexed.normalizedHeader = YTKACENormalizeString(header);
                indexed.normalizedPageTitle = YTKACENormalizeString(pageTitle);
                indexed.titleTokens = YTKACETokenizeString(title);
                indexed.subtitleTokens = YTKACETokenizeString(subtitle);

                NSMutableArray<NSString *> *kw = [NSMutableArray array];
                if ([pageID isEqualToString:@"display"]) {
                    [kw addObjectsFromArray:@[@"120hz", @"120", @"promotion", @"fps", @"smooth", @"scroll", @"hz", @"hertz", @"cadence", @"adaptive", @"refresh"]];
                } else if ([pageID isEqualToString:@"appearance"]) {
                    [kw addObjectsFromArray:@[@"oled", @"theme", @"preset", @"accent", @"color", @"custom", @"hex", @"navy", @"black", @"surface"]];
                } else if ([pageID isEqualToString:@"playback"]) {
                    [kw addObjectsFromArray:@[@"codec", @"av1", @"vp9", @"h264", @"buffer", @"boost", @"bitrate", @"quality"]];
                }
                indexed.keywords = kw;

                [items addObject:indexed];
            }
        }
    }
    s_cachedIndex = [items copy];
    s_lastIndexedLanguage = [currentLanguage copy];
    os_unfair_lock_unlock(&s_indexLock);
    return s_cachedIndex;
}

static NSInteger YTKACEEvaluateMatchScore(YTKACEIndexedItem *item, NSString *normalizedQuery, NSArray<NSString *> *queryTokens) {
    if (normalizedQuery.length == 0) return NSNotFound;

    // 0: Exact title match
    if ([item.normalizedTitle isEqualToString:normalizedQuery]) {
        return 0;
    }

    // 10: Title prefix match
    if ([item.normalizedTitle hasPrefix:normalizedQuery]) {
        return 10;
    }

    // 20: Any title word starts with query
    for (NSString *tok in item.titleTokens) {
        if ([tok hasPrefix:normalizedQuery]) {
            return 20;
        }
    }

    // 30: Title contains query substring
    if ([item.normalizedTitle rangeOfString:normalizedQuery].location != NSNotFound) {
        return 30;
    }

    // 40: Any keyword starts with query or matches
    for (NSString *kw in item.keywords) {
        if ([kw hasPrefix:normalizedQuery] || [kw isEqualToString:normalizedQuery]) {
            return 40;
        }
    }

    // 50: Any subtitle token starts with query
    for (NSString *tok in item.subtitleTokens) {
        if ([tok hasPrefix:normalizedQuery]) {
            return 50;
        }
    }

    // 60: Subtitle contains query
    if ([item.normalizedSubtitle rangeOfString:normalizedQuery].location != NSNotFound) {
        return 60;
    }

    // 70: Header or Page Title match
    if ([item.normalizedHeader hasPrefix:normalizedQuery] ||
        [item.normalizedPageTitle hasPrefix:normalizedQuery]) {
        return 70;
    }
    if ([item.normalizedHeader rangeOfString:normalizedQuery].location != NSNotFound ||
        [item.normalizedPageTitle rangeOfString:normalizedQuery].location != NSNotFound) {
        return 80;
    }

    // Multi-token query evaluation: all tokens match title, subtitle or keywords
    if (queryTokens.count > 1) {
        BOOL allMatched = YES;
        for (NSString *qTok in queryTokens) {
            BOOL tokenFound = NO;
            for (NSString *tTok in item.titleTokens) {
                if ([tTok hasPrefix:qTok]) { tokenFound = YES; break; }
            }
            if (!tokenFound) {
                for (NSString *sTok in item.subtitleTokens) {
                    if ([sTok hasPrefix:qTok]) { tokenFound = YES; break; }
                }
            }
            if (!tokenFound) {
                for (NSString *kw in item.keywords) {
                    if ([kw hasPrefix:qTok]) { tokenFound = YES; break; }
                }
            }
            if (!tokenFound) {
                allMatched = NO;
                break;
            }
        }
        if (allMatched) {
            return 45;
        }
    }

    return NSNotFound;
}

NSArray<NSDictionary *> *YTKACEFilterSettings(NSString *query) {
    NSString *trimmed = [query stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceCharacterSet];
    if (trimmed.length == 0) return @[];

    NSString *normalizedQuery = YTKACENormalizeString(trimmed);
    NSArray<NSString *> *queryTokens = YTKACETokenizeString(trimmed);
    NSArray<YTKACEIndexedItem *> *index = YTKACEGetOrBuildSearchIndex();

    NSMutableArray<NSDictionary *> *scored = [NSMutableArray arrayWithCapacity:index.count];
    for (YTKACEIndexedItem *indexed in index) {
        NSInteger score = YTKACEEvaluateMatchScore(indexed, normalizedQuery, queryTokens);
        if (score == NSNotFound) continue;
        NSMutableDictionary *entry = [indexed.record mutableCopy];
        entry[@"score"] = @(score);
        [scored addObject:entry];
    }

    [scored sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult order = [a[@"score"] compare:b[@"score"]];
        return order != NSOrderedSame ? order : [a[@"title"] compare:b[@"title"]];
    }];
    return scored;
}

void YTKACEOpenSettingsRecord(NSDictionary *record, UIViewController *presenter) {
    UIViewController *page = YTKACEControllerForPageID(record[@"pageID"]);
    if (page == nil || presenter == nil) return;
    NSIndexPath *target = [NSIndexPath indexPathForRow:[record[@"row"] integerValue]
                                             inSection:[record[@"section"] integerValue]];
    SEL push = NSSelectorFromString(@"pushViewController:");
    if ([presenter respondsToSelector:push]) {
        ((void (*)(id, SEL, id))objc_msgSend)(presenter, push, page);
    } else if (presenter.navigationController != nil) {
        [presenter.navigationController pushViewController:page animated:YES];
    } else {
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (![page isKindOfClass:UITableViewController.class]) return;
        UITableView *table = ((UITableViewController *)page).tableView;
        if (target.section >= [table numberOfSections] ||
            target.row >= [table numberOfRowsInSection:target.section]) return;
        [table scrollToRowAtIndexPath:target
                     atScrollPosition:UITableViewScrollPositionMiddle
                             animated:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UITableViewCell *cell = [table cellForRowAtIndexPath:target];
            if (cell == nil) return;
            UIColor *original = cell.contentView.backgroundColor;
            cell.contentView.backgroundColor =
                [YTKACEAccentColor() colorWithAlphaComponent:0.28];
            [UIView animateWithDuration:0.9 delay:0.4
                                options:UIViewAnimationOptionCurveEaseOut
                             animations:^{ cell.contentView.backgroundColor = original; }
                             completion:nil];
        });
    });
}

@interface YTKACESearchOverlayController : UIViewController
    <UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, weak) UIViewController *hostController;
@property(nonatomic, strong) UISearchBar *searchBar;
@property(nonatomic, strong) UITableView *table;
@property(nonatomic, copy) NSArray<NSDictionary *> *results;
@end

@implementation YTKACESearchOverlayController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.results = @[];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.searchBar = [UISearchBar new];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = YTKACELocalized(@"Search");
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.tintColor = YTKACEAccentColor();
    self.searchBar.searchTextField.tintColor = YTKACEAccentColor();
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.searchBar];

    self.table = [[UITableView alloc] initWithFrame:CGRectZero
                                              style:UITableViewStylePlain];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.backgroundColor = UIColor.clearColor;
    self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.table.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.table];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.searchBar.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor],
        [self.table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.table.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.searchBar becomeFirstResponder];
}

- (void)dismissOverlay {
    [self.searchBar resignFirstResponder];
    [self willMoveToParentViewController:nil];
    [self.view removeFromSuperview];
    [self removeFromParentViewController];
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    [searchBar setShowsCancelButton:YES animated:YES];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
    (void)searchBar;
    self.results = YTKACEFilterSettings(text);
    [self.table reloadData];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    [searchBar setShowsCancelButton:NO animated:YES];
    [self dismissOverlay];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return (NSInteger)self.results.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *const identifier = @"YTKACEOverlayRow";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:identifier];
    }
    NSDictionary *record = self.results[(NSUInteger)indexPath.row];
    NSString *header = record[@"header"];
    cell.textLabel.text = record[@"title"];
    cell.detailTextLabel.text = header.length != 0
        ? [NSString stringWithFormat:@"%@ › %@", record[@"pageTitle"], header]
        : record[@"pageTitle"];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.backgroundColor = UIColor.clearColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *record = self.results[(NSUInteger)indexPath.row];
    UIViewController *host = self.hostController;
    [self dismissOverlay];
    YTKACEOpenSettingsRecord(record, host);
}

@end

void YTKACEPresentSettingsSearchOverlay(UIViewController *host) {
    if (host == nil || !host.isViewLoaded) return;
    for (UIViewController *child in host.childViewControllers) {
        if ([child isKindOfClass:YTKACESearchOverlayController.class]) return;
    }
    YTKACESearchOverlayController *overlay = [YTKACESearchOverlayController new];
    overlay.hostController = host;
    [host addChildViewController:overlay];
    overlay.view.frame = host.view.bounds;
    overlay.view.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [host.view addSubview:overlay.view];
    [overlay didMoveToParentViewController:host];
}

NSArray<NSArray<NSDictionary *> *> *YTKACESearchResultSections(
        NSString *query, NSArray<NSString *> **sectionTitles) {
    NSArray<NSDictionary *> *matches = YTKACEFilterSettings(query);
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    NSMutableArray<NSMutableArray<NSDictionary *> *> *sections =
        [NSMutableArray array];
    for (NSDictionary *record in matches) {
        NSDictionary *item = record[@"item"];
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSString *page = record[@"pageTitle"] ?: @"";
        NSString *area = record[@"header"] ?: @"";
        NSString *group = area.length != 0
            ? [NSString stringWithFormat:@"%@ › %@", page, area] : page;
        NSUInteger index = [titles indexOfObject:group];
        if (index == NSNotFound) {
            [titles addObject:group];
            [sections addObject:[NSMutableArray array]];
            index = titles.count - 1;
        }
        [sections[index] addObject:item];
    }
    if (sectionTitles != NULL) *sectionTitles = [titles copy];
    return [sections copy];
}
