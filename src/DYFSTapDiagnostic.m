//
//  DYFSTapDiagnostic.m
//  DY.FullScreen
//
//  轻量点击诊断：定位「我-喜欢 / 收藏 / 我-作品」宫格页「点 N 打开 N+1」。
//  点宫格时记录 indexPath + 屏幕坐标；详情页打开时记录实际加载的 awemeId。
//  默认关闭，由诊断页开关启用，不进入任何高频路径，不影响正常布局。
//

#import "DYFSTapDiagnostic.h"
#import "DYFSCommon.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL gTapDiagEnabled = NO;
static UILabel *gTapDiagLabel = nil;
static NSTimeInterval gTapDiagLastShow = 0;

BOOL DYFSTapDiagnosticEnabled(void) { return gTapDiagEnabled; }
void DYFSTapDiagnosticSetEnabled(BOOL enabled) { gTapDiagEnabled = enabled; }

#pragma mark - 通用工具

static BOOL DYFSSwapMethod(Class cls, SEL sel, IMP newImp, IMP *origImp) {
    if (!cls || !sel || !newImp) return NO;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NO;
    if (origImp) *origImp = method_getImplementation(m);
    method_setImplementation(m, newImp);
    return YES;
}

// best-effort 从 aweme 模型里抠出 id（抖音私有字段，多试几个）
static NSString *DYFSAwemeID(id aweme) {
    if (!aweme) return nil;
    NSArray<NSString *> *keys = @[@"awemeID", @"awemeId", @"aweme_id", @"cid",
                                  @"awemeIdStr", @"itemId", @"awemeIDStr"];
    for (NSString *k in keys) {
        id v = DYFSSafeValueForKey(aweme, k);
        if (v && ![v isKindOfClass:NSNull.class]) return [NSString stringWithFormat:@"%@", v];
    }
    id inner = DYFSSafeValueForKey(aweme, @"aweme");
    if (inner && inner != aweme) return DYFSAwemeID(inner);
    return nil;
}

// 从宫格 VC 的数据源里取某 indexPath 对应的 awemeId
static NSString *DYFSGridAwemeID(id self, NSIndexPath *ip) {
    NSArray<NSString *> *srcKeys = @[@"awemes", @"list", @"items", @"dataList", @"awemeList", @"dataArray"];
    NSArray *arr = nil;
    for (id src in @[self, DYFSSafeValueForKey(self, @"viewModel")]) {
        if (!src) continue;
        for (NSString *k in srcKeys) {
            id v = DYFSSafeValueForKey(src, k);
            if ([v isKindOfClass:NSArray.class] && [(NSArray *)v count] > 0) { arr = v; break; }
        }
        if (arr) break;
    }
    if (!arr || arr.count == 0) return nil;
    NSInteger idx = (ip && ip.item < (NSInteger)arr.count) ? ip.item
                  : (ip && ip.row < (NSInteger)arr.count) ? ip.row : NSNotFound;
    if (idx == NSNotFound) return nil;
    return DYFSAwemeID(arr[idx]);
}

// 从详情 VC 抠出当前 awemeId
static NSString *DYFSDetailAwemeID(id self) {
    NSArray<NSString *> *keys = @[@"aweme", @"currentAwemeModel", @"currentAweme",
                                  @"model", @"awemeModel", @"awemeViewModel"];
    for (NSString *k in keys) {
        id v = DYFSSafeValueForKey(self, k);
        if (v) { NSString *idStr = DYFSAwemeID(v); if (idStr) return idStr; }
    }
    return nil;
}

#pragma mark - 屏幕横幅

static void DYFSShowTapDiag(NSString *text) {
    if (!text.length) return;
    UIWindow *win = nil;
    for (UIWindow *w in UIApplication.sharedApplication.windows) {
        if (w.isKeyWindow) { win = w; break; }
    }
    if (!win) win = UIApplication.sharedApplication.windows.firstObject;
    if (!win) return;

    if (!gTapDiagLabel) {
        gTapDiagLabel = [[UILabel alloc] init];
        gTapDiagLabel.numberOfLines = 0;
        gTapDiagLabel.font = [UIFont boldSystemFontOfSize:13];
        gTapDiagLabel.textColor = UIColor.whiteColor;
        gTapDiagLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.82];
        gTapDiagLabel.textAlignment = NSTextAlignmentLeft;
        gTapDiagLabel.layer.cornerRadius = 8;
        gTapDiagLabel.clipsToBounds = YES;
        gTapDiagLabel.adjustsFontSizeToFitWidth = NO;
    }
    [win addSubview:gTapDiagLabel];
    gTapDiagLabel.text = text;
    CGSize maxSize = CGSizeMake(win.bounds.size.width - 24, 200);
    CGSize sz = [gTapDiagLabel sizeThatFits:maxSize];
    CGFloat x = 12, y = 60;
    gTapDiagLabel.frame = CGRectMake(x, y, MIN(sz.width + 16, maxSize.width), sz.height + 12);

    gTapDiagLabel.alpha = 1.0;
    gTapDiagLabel.hidden = NO;
    gTapDiagLastShow = CACurrentMediaTime();
    [NSObject cancelPreviousPerformRequestsWithTarget:gTapDiagLabel];
    [gTapDiagLabel performSelector:@selector(setHidden:) withObject:@YES afterDelay:4.0];
}

#pragma mark - hook：宫格点击

static IMP gOrigGridSelect = NULL;
static void DYFSTapDiagGridSelect(id self, SEL cmd, UICollectionView *cv, NSIndexPath *ip) {
    if (gTapDiagEnabled) {
        // 仅对 profile 宫格（AWEUserWorkCollectionViewComponentCell）生效
        BOOL isProfileGrid = NO;
        for (UICollectionViewCell *c in cv.visibleCells) {
            if ([NSStringFromClass(c.class) containsString:@"AWEUserWorkCollectionViewComponentCell"]) {
                isProfileGrid = YES; break;
            }
        }
        if (isProfileGrid) {
            CGRect wr = CGRectZero;
            UICollectionViewCell *cell = [cv cellForItemAtIndexPath:ip];
            if (cell) wr = [cell convertRect:cell.bounds toView:nil];
            NSString *aid = DYFSGridAwemeID(self, ip);
            NSString *msg = [NSString stringWithFormat:
                @"[宫格点] item=(%ld,%ld) 屏(x=%.0f,y=%.0f) 列表aweme=%@\n点开后看详情是否一致",
                (long)ip.section, (long)ip.item, CGRectGetMidX(wr), CGRectGetMidY(wr),
                aid ?: @"n/a"];
            DYFSShowTapDiag(msg);
        }
    }
    if (gOrigGridSelect) ((void (*)(id, SEL, UICollectionView *, NSIndexPath *))gOrigGridSelect)(self, cmd, cv, ip);
}

#pragma mark - hook：详情打开

static IMP gOrigDetailAppear = NULL;
static void DYFSTapDiagDetailAppear(id self, SEL cmd, BOOL animated) {
    if (gOrigDetailAppear) ((void (*)(id, SEL, BOOL))gOrigDetailAppear)(self, cmd, animated);
    if (gTapDiagEnabled) {
        NSString *aid = DYFSDetailAwemeID(self);
        if (aid) {
            NSString *msg = [NSString stringWithFormat:@"[详情打开] aweme=%@\n对比上面的「列表aweme」", aid];
            DYFSShowTapDiag(msg);
        }
    }
}

#pragma mark - 安装

void DYFSTapDiagnosticInstallHooks(void) {
    Class gridCls = NSClassFromString(@"AWEDCFeedListViewController");
    if (gridCls) {
        DYFSSwapMethod(gridCls, @selector(collectionView:didSelectItemAtIndexPath:),
                       (IMP)DYFSTapDiagGridSelect, &gOrigGridSelect);
    }
    Class detailCls = NSClassFromString(@"AWEAwemeDetailTableViewController");
    if (detailCls) {
        DYFSSwapMethod(detailCls, @selector(viewWillAppear:),
                       (IMP)DYFSTapDiagDetailAppear, &gOrigDetailAppear);
    }
}
