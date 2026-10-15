//
//  DYFSTapDiagnostic.m
//  DY.FullScreen
//
//  轻量点击诊断：定位「我-喜欢 / 收藏 / 我-作品」宫格页「点 N 打开 N+1」。
//  点宫格时记录 indexPath + 屏幕坐标 + 列表 awemeId；详情页打开时记录实际加载的
//  awemeId，并与上一次宫格点对比，给出「一致 / 不一致」判定。
//  默认关闭，由诊断页开关启用，不进入任何高频路径，不影响正常布局。
//
//  0.5.17 重写：
//   · 去掉原来脆弱的「可见 cell 必须叫 AWEUserWorkCollectionViewComponentCell」闸门
//     （40.7.0 宫格 cell 类名未必命中 → 整段静默跳过，横幅从不出现）。
//     本 hook 只挂在 AWEDCFeedListViewController 上，它本身就是 profile/喜欢/收藏
//     宫格，直接显示即可。
//   · 原来「宫格点」与「详情打开」用同一个 label、各 4s 隐藏 → 详情横幅瞬间覆盖
//     宫格横幅，且 keyWindow 切换时可能不渲染。改为：单个持久 label，每次事件更新
//     文本并统一 8s 隐藏，挂到最上层窗口并置顶。详情横幅会合并显示上一次宫格点的信息。
//

#import "DYFSTapDiagnostic.h"
#import "DYFSCommon.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static BOOL gTapDiagEnabled = NO;
static UILabel *gTapDiagLabel = nil;
static NSTimeInterval gTapDiagLastShow = 0;

// 上一次宫格点击记录（用于与详情对比）
static NSString *gLastGridItem = nil;     // @"sec,item"
static NSString *gLastGridListAid = nil;  // 列表 awemeId
static NSTimeInterval gLastGridTime = 0;

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

#pragma mark - 屏幕横幅（单个持久 label）

// 选最上层、可见的窗口（优先 keyWindow，否则取最高 windowLevel）
static UIWindow *DYFSTopWindow(void) {
    UIWindow *key = nil;
    UIWindow *best = nil;
    UIWindowLevel bestLevel = -CGFLOAT_MAX;
    for (UIWindow *w in UIApplication.sharedApplication.windows) {
        if (w.isKeyWindow) key = w;
        if (w.hidden || w.alpha <= 0.01) continue;
        if (w.windowLevel >= bestLevel) { bestLevel = w.windowLevel; best = w; }
    }
    return key ?: best;
}

static void DYFSShowTapDiag(NSString *text) {
    if (!text.length) return;
    UIWindow *win = DYFSTopWindow();
    if (!win) return;

    if (!gTapDiagLabel) {
        gTapDiagLabel = [[UILabel alloc] init];
        gTapDiagLabel.numberOfLines = 0;
        gTapDiagLabel.font = [UIFont boldSystemFontOfSize:13];
        gTapDiagLabel.textColor = UIColor.whiteColor;
        gTapDiagLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.85];
        gTapDiagLabel.textAlignment = NSTextAlignmentLeft;
        gTapDiagLabel.layer.cornerRadius = 8;
        gTapDiagLabel.clipsToBounds = YES;
        gTapDiagLabel.adjustsFontSizeToFitWidth = NO;
        gTapDiagLabel.userInteractionEnabled = NO;
    }
    // 始终挂到当前最上层窗口并置顶，避免跨窗口/层级被盖住
    if (gTapDiagLabel.superview != win) [win addSubview:gTapDiagLabel];
    [win bringSubviewToFront:gTapDiagLabel];

    gTapDiagLabel.text = text;
    CGSize maxSize = CGSizeMake(win.bounds.size.width - 24, 240);
    CGSize sz = [gTapDiagLabel sizeThatFits:maxSize];
    CGFloat x = 12, y = 64;
    gTapDiagLabel.frame = CGRectMake(x, y, MIN(sz.width + 16, maxSize.width), sz.height + 12);
    gTapDiagLabel.alpha = 1.0;
    gTapDiagLabel.hidden = NO;

    gTapDiagLastShow = CACurrentMediaTime();
    [NSObject cancelPreviousPerformRequestsWithTarget:gTapDiagLabel];
    [gTapDiagLabel performSelector:@selector(setHidden:) withObject:@YES afterDelay:8.0];
}

#pragma mark - hook：宫格点击（AWEDCFeedListViewController）

static IMP gOrigGridSelect = NULL;
static void DYFSTapDiagGridSelect(id self, SEL cmd, UICollectionView *cv, NSIndexPath *ip) {
    if (gOrigGridSelect) ((void (*)(id, SEL, UICollectionView *, NSIndexPath *))gOrigGridSelect)(self, cmd, cv, ip);

    if (!gTapDiagEnabled) return;

    // 本 hook 只挂在 AWEDCFeedListViewController（profile/喜欢/收藏宫格），直接收集信息。
    CGRect wr = CGRectZero;
    UICollectionViewCell *cell = [cv cellForItemAtIndexPath:ip];
    if (cell) wr = [cell convertRect:cell.bounds toView:nil];
    NSString *aid = DYFSGridAwemeID(self, ip);

    gLastGridItem = [NSString stringWithFormat:@"%ld,%ld", (long)ip.section, (long)ip.item];
    gLastGridListAid = aid;
    gLastGridTime = CACurrentMediaTime();

    NSString *msg = [NSString stringWithFormat:
        @"[宫格点] item=(%@) 屏(x=%.0f,y=%.0f)\n列表aweme=%@\n（点开后看详情是否一致）",
        gLastGridItem, CGRectGetMidX(wr), CGRectGetMidY(wr), aid ?: @"n/a"];
    DYFSShowTapDiag(msg);
}

#pragma mark - hook：详情打开（AWEAwemeDetailTableViewController）

static IMP gOrigDetailAppear = NULL;
static void DYFSTapDiagDetailAppear(id self, SEL cmd, BOOL animated) {
    if (gOrigDetailAppear) ((void (*)(id, SEL, BOOL))gOrigDetailAppear)(self, cmd, animated);
    if (!gTapDiagEnabled) return;

    NSString *aid = DYFSDetailAwemeID(self);
    if (!aid) return;

    // 与「上一次宫格点」对比（4s 内视为同一次点击流程）
    NSTimeInterval dt = CACurrentMediaTime() - gLastGridTime;
    NSString *verdict = @"";
    if (gLastGridListAid && gLastGridTime > 0 && dt < 4.0) {
        if (gLastGridListAid.length && [gLastGridListAid isEqualToString:aid]) {
            verdict = @"  ✅一致";
        } else {
            verdict = [NSString stringWithFormat:@"  ❌不一致(宫格=%@)", gLastGridListAid ?: @"n/a"];
        }
    }

    NSString *msg = [NSString stringWithFormat:
        @"[详情] aweme=%@%@\n[上一次宫格点] item=%@ 列表=%@",
        aid, verdict, gLastGridItem ?: @"?", gLastGridListAid ?: @"n/a"];
    DYFSShowTapDiag(msg);
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
