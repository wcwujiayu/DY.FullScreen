//
//  DYFSTapDiagnostic.m
//  DY.FullScreen
//
//  轻量点击诊断：定位「我-喜欢 / 收藏 / 我-作品」宫格页「点 N 打开 N+1」。
//  点宫格时记录 indexPath + 屏幕坐标 + 列表 awemeId；详情页打开时记录实际加载的
//  awemeId，并与上一次宫格点对比，给出「一致 / 不一致」判定。
//  默认关闭，由诊断页开关启用，不进入任何高频路径，不影响正常布局。
//
//  0.5.18 改进：
//   · 宫格数据源支持多 section（section 0 个人信息，section 1 视频网格），按 section
//     取子数组后再按 item/row 取元素。
//   · 增加 cell 递归扫描与更全数据源 key 作为 fallback。
//   · 列表 aweme 取不到时显示调试信息（命中 key / 数组长度 / section），帮助继续定位。
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
static NSString *gLastGridSearchDebug = nil;

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
    if ([aweme isKindOfClass:NSString.class]) return (NSString *)aweme;
    if ([aweme isKindOfClass:NSNumber.class]) return [aweme stringValue];
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

// 递归扫描对象，寻找看起来像 awemeId 的字符串（>=15 位纯数字）。
static NSString *DYFSScanAwemeIdDeep(id obj, NSUInteger depth) {
    if (!obj || depth > 6) return nil;
    if ([obj isKindOfClass:NSString.class]) {
        NSString *s = (NSString *)obj;
        if (s.length >= 15 && [s rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound) return s;
        return nil;
    }
    if ([obj isKindOfClass:NSNumber.class]) {
        NSString *s = [obj stringValue];
        if (s.length >= 15) return s;
        return nil;
    }
    if ([obj isKindOfClass:NSArray.class]) {
        for (id item in (NSArray *)obj) {
            NSString *found = DYFSScanAwemeIdDeep(item, depth + 1);
            if (found) return found;
        }
        return nil;
    }
    if ([obj isKindOfClass:NSSet.class]) {
        for (id item in (NSSet *)obj) {
            NSString *found = DYFSScanAwemeIdDeep(item, depth + 1);
            if (found) return found;
        }
        return nil;
    }
    if ([obj isKindOfClass:NSDictionary.class]) {
        NSDictionary *d = (NSDictionary *)obj;
        for (NSString *k in @[@"awemeId", @"awemeID", @"aweme_id", @"itemId", @"cid"]) {
            id v = [d objectForKey:k];
            NSString *found = DYFSScanAwemeIdDeep(v, depth + 1);
            if (found) return found;
        }
        for (id v in d.allValues) {
            NSString *found = DYFSScanAwemeIdDeep(v, depth + 1);
            if (found) return found;
        }
        return nil;
    }
    Class cls = [obj class];
    if (!cls) return nil;
    unsigned int count = 0;
    Ivar *ivars = class_copyIvarList(cls, &count);
    if (ivars) {
        for (unsigned int i = 0; i < count; i++) {
            id v = object_getIvar(obj, ivars[i]);
            NSString *found = DYFSScanAwemeIdDeep(v, depth + 1);
            if (found) { free(ivars); return found; }
        }
        free(ivars);
    }
    objc_property_t *props = class_copyPropertyList(cls, &count);
    if (props) {
        for (unsigned int i = 0; i < count; i++) {
            NSString *name = [NSString stringWithUTF8String:property_getName(props[i])];
            id v = DYFSSafeValueForKey(obj, name);
            NSString *found = DYFSScanAwemeIdDeep(v, depth + 1);
            if (found) { free(props); return found; }
        }
        free(props);
    }
    return nil;
}

// 从宫格 VC 的数据源里取某 indexPath 对应的 awemeId。
static NSString *DYFSGridAwemeID(id self, NSIndexPath *ip, UICollectionViewCell *cell) {
    gLastGridSearchDebug = @"no_src";
    NSArray<NSString *> *srcKeys = @[@"awemes", @"list", @"items", @"dataList", @"awemeList",
                                     @"dataArray", @"awemeModels", @"itemModels", @"cellModels",
                                     @"itemsArray", @"data", @"feeds", @"videos", @"models",
                                     @"dataSource", @"feedList", @"cellData"];
    NSArray *rootArr = nil;
    id rootSrc = nil;
    NSString *hitKey = nil;
    for (id src in @[self, DYFSSafeValueForKey(self, @"viewModel"),
                     DYFSSafeValueForKey(self, @"dataViewModel"),
                     DYFSSafeValueForKey(self, @"listViewModel")]) {
        if (!src) continue;
        for (NSString *k in srcKeys) {
            id v = DYFSSafeValueForKey(src, k);
            if ([v isKindOfClass:NSArray.class] && [(NSArray *)v count] > 0) {
                rootArr = v; rootSrc = src; hitKey = k; break;
            }
        }
        if (rootArr) break;
    }

    NSInteger section = ip ? ip.section : 0;
    NSInteger item    = ip ? ip.item : (ip ? ip.row : 0);

    if (rootArr) {
        gLastGridSearchDebug = [NSString stringWithFormat:@"key=%@ len=%lu sec=%ld",
                                hitKey ?: @"?", (unsigned long)rootArr.count, (long)section];
        if ((NSInteger)rootArr.count > section) {
            id secObj = rootArr[section];
            // 多 section：每个 section 是一个 NSArray
            if ([secObj isKindOfClass:NSArray.class] && (NSInteger)[(NSArray *)secObj count] > item) {
                NSString *aid = DYFSAwemeID(secObj[item]);
                if (aid) return aid;
                gLastGridSearchDebug = [NSString stringWithFormat:@"key=%@ sec_len=%lu item=%ld no_id",
                                        hitKey ?: @"?", (unsigned long)[(NSArray *)secObj count], (long)item];
            }
            // 单 section 退化：直接用 item 取
            if (item < (NSInteger)rootArr.count) {
                NSString *aid = DYFSAwemeID(rootArr[item]);
                if (aid) return aid;
            }
            // 用 row 再试
            NSInteger row = ip ? ip.row : item;
            if (row != item && row < (NSInteger)rootArr.count) {
                NSString *aid = DYFSAwemeID(rootArr[row]);
                if (aid) return aid;
            }
        }
    }

    // fallback：从 cell 本身递归扫描 awemeId
    if (cell) {
        NSString *fromCell = DYFSScanAwemeIdDeep(cell, 0);
        if (fromCell) return fromCell;
    }

    return nil;
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
    if (gTapDiagLabel.superview != win) [win addSubview:gTapDiagLabel];
    [win bringSubviewToFront:gTapDiagLabel];

    gTapDiagLabel.text = text;
    CGSize maxSize = CGSizeMake(win.bounds.size.width - 24, 240);
    CGSize sz = [gTapDiagLabel sizeThatFits:maxSize];
    gTapDiagLabel.frame = CGRectMake(12, 64, MIN(sz.width + 16, maxSize.width), sz.height + 12);
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

    CGRect wr = CGRectZero;
    UICollectionViewCell *cell = [cv cellForItemAtIndexPath:ip];
    if (cell) wr = [cell convertRect:cell.bounds toView:nil];
    NSString *aid = DYFSGridAwemeID(self, ip, cell);

    gLastGridItem = [NSString stringWithFormat:@"%ld,%ld", (long)ip.section, (long)ip.item];
    gLastGridListAid = aid;
    gLastGridTime = CACurrentMediaTime();

    NSString *display = aid ?: [NSString stringWithFormat:@"n/a(%@)", gLastGridSearchDebug ?: @"no_src"];
    NSString *msg = [NSString stringWithFormat:
        @"[宫格点] item=(%@) 屏(x=%.0f,y=%.0f)\n列表aweme=%@",
        gLastGridItem, CGRectGetMidX(wr), CGRectGetMidY(wr), display];
    DYFSShowTapDiag(msg);
}

#pragma mark - hook：详情打开（AWEAwemeDetailTableViewController）

static IMP gOrigDetailAppear = NULL;
static void DYFSTapDiagDetailAppear(id self, SEL cmd, BOOL animated) {
    if (gOrigDetailAppear) ((void (*)(id, SEL, BOOL))gOrigDetailAppear)(self, cmd, animated);
    if (!gTapDiagEnabled) return;

    NSString *aid = DYFSDetailAwemeID(self);
    if (!aid) return;

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
