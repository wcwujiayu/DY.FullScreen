//
//  DYFSLayout.m
//  DY.FullScreen
//
//  Sizing corrections: expand the feed canvas and player content while keeping
//  the interaction layer inside the usable area above the bottom tab bar.
//

#import "DYFSLayout.h"
#import "DYFSCommon.h"
#import "DYFSContext.h"
#import "DYFSTransparency.h"
#import <objc/message.h>
#import <math.h>

static IMP DYFSOriginalFeedLayout = NULL;
static IMP DYFSOriginalStoryLayout = NULL;
static IMP DYFSOriginalInteractionControllerLayout = NULL;
static IMP DYFSOriginalPlayerContentA = NULL;
static IMP DYFSOriginalPlayerContentB = NULL;
static IMP DYFSOriginalPlayerContentC = NULL;
static IMP DYFSOriginalSetFrame = NULL;
static IMP DYFSOriginalDetailTableLayout = NULL;
static IMP DYFSOriginalDetailCellLayout = NULL;
static IMP DYFSOriginalMixPanelLayout = NULL;
static BOOL DYFSDetailTransparencyScheduled = NO;

// Associated-object keys used to settle player geometry without looping.
// 等父容器尺寸稳定后再匹配高度，避免与原生布局互相触发
static const NSTimeInterval kDYFSPlayerSettleDelay = 0.18;

static char kDYFSPlayerLayoutPendingKey;
static char kDYFSPlayerParentHeightKey;
static char kDYFSPlayerSettledGeometryKey;

CGFloat DYFSBottomTabBarHeight(UIView *view) {
    UIWindow *window = view.window;
    if (window) {
        UIView *tabBar = DYFSFindSubviewOfClass(window, @"AWENormalModeTabBar", 0);
        CGFloat measured = CGRectGetHeight(tabBar.bounds);
        if (tabBar && isfinite(measured) && measured >= 30.0 && measured < CGRectGetHeight(window.bounds)) {
            return measured;
        }
        return 49.0 + MAX(0.0, window.safeAreaInsets.bottom);
    }
    return 49.0;
}

void DYFSFeedTableLayout(id self, SEL cmd) {
    if (DYFSOriginalFeedLayout) ((void (*)(id, SEL))DYFSOriginalFeedLayout)(self, cmd);
    if (!DYFSIsEnabled()) return;

    UIView *view = (UIView *)self;
    // 个人主页（我-作品 / 我-喜欢）也走这张表；透明化不受尺寸守卫影响。
    DYFSTransparencyApplyInView(view);
    UIView *parent = view.superview;
    if (!parent || DYFSInProfileContext(view) || DYFSIsActualLiveRoomContext(view) || DYFSIsLivePreStreamContext(view)) return;
    CGRect frame = view.frame;
    CGFloat targetHeight = CGRectGetHeight(parent.bounds);
    if (!isfinite(targetHeight) || targetHeight <= 1.0) return;
    if (fabs(CGRectGetHeight(frame) - targetHeight) <= 0.5 &&
        fabs(CGRectGetMinY(frame)) <= 0.5) return;

    CGFloat oldHeight = CGRectGetHeight(frame);
    CGFloat oldY = CGRectGetMinY(frame);
    frame.origin.y = 0.0;
    frame.size.height = targetHeight;
    view.frame = frame;
    DYFSLayoutFixCount++;
    DYFSLog([NSString stringWithFormat:@"AWEFeedTableView frame y %.2f -> %.2f, height %.2f -> %.2f",
             oldY, CGRectGetMinY(frame), oldHeight, targetHeight]);
}

void DYFSStoryContainerLayout(id self, SEL cmd) {
    if (DYFSOriginalStoryLayout) {
        ((void (*)(id, SEL))DYFSOriginalStoryLayout)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;

    UIView *container = (UIView *)self;
    DYFSTransparencyApplyInView(container);
    if (DYFSInProfileContext(container) || DYFSIsActualLiveRoomContext(container) || DYFSIsLivePreStreamContext(container)) return;

    id homeValue = DYFSSafeValueForKey(container, @"enableEnterProfile");
    BOOL isHome = [homeValue respondsToSelector:@selector(boolValue)] && [homeValue boolValue];
    if (!isHome) return;

    for (UIView *subview in [container.subviews copy]) {
        UIResponder *responder = subview.nextResponder;
        NSString *responderName = responder ? NSStringFromClass(responder.class) : @"";
        if (![responderName containsString:@"AWEPlayInteractionViewController"]) continue;

        id baseViewController = DYFSSafeValueForKey(responder, @"awemeBaseViewController");
        NSString *baseName = baseViewController ? NSStringFromClass([baseViewController class]) : @"";
        if (![baseName containsString:@"AWEFeedCellViewController"]) continue;

        UIView *parent = subview.superview;
        if (!parent) continue;

        CGFloat parentHeight = CGRectGetHeight(parent.bounds);
        CGFloat tabBarHeight = DYFSBottomTabBarHeight(subview);
        CGFloat targetHeight = parentHeight - tabBarHeight;
        if (!isfinite(targetHeight) || targetHeight <= 1.0) continue;

        CGRect frame = subview.frame;
        CGFloat oldHeight = CGRectGetHeight(frame);
        if (fabs(oldHeight - targetHeight) <= 0.5) continue;

        frame.size.height = targetHeight;
        subview.frame = frame;
        DYFSInteractionContainerAdjustCount++;
        DYFSLog([NSString stringWithFormat:
            @"home interaction layer height %.2f -> %.2f (parent %.2f, tab bar %.2f)",
            oldHeight, targetHeight, parentHeight, tabBarHeight]);
    }
}

// 复刻 DYYY 的核心逻辑：在 AWEPlayInteractionViewController 的 -viewDidLayoutSubviews
// 里直接把互动层高度限制为「父高 − 底栏高」（普通场景），让账号/文案/点赞区停在
// 透明底栏上方。DYYY 不在这里做任何「是不是 feed 卡片」之类的自定义判定，只保留
// 极少量保护分支，因此我们之前那套 DYFSIsFeedCellInteractionController 之类的判断
// 在 40.7.0 上全失败、导致整段高度修正被 return 掉——这正是「依然无效果」的根因。
void DYFSInteractionControllerLayout(id self, SEL cmd) {
    if (DYFSOriginalInteractionControllerLayout) {
        ((void (*)(id, SEL))DYFSOriginalInteractionControllerLayout)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;

    UIViewController *controller = (UIViewController *)self;
    UIView *view = controller.view;
    DYFSTransparencyApplyInView(view);
    if (view && view.superview) DYFSTransparencyApplyInView(view.superview);
    if (!view || !view.superview || !view.window) return;

    UIWindow *keyWindow = view.window;
    if (keyWindow && keyWindow.safeAreaInsets.bottom == 0) return;

    // 远程投屏这类场景不处理（与 DYYY 一致）。
    UIViewController *parentVC = controller.parentViewController;
    int count = 0;
    while (parentVC && count < 3) {
        if ([NSStringFromClass(parentVC.class) containsString:@"AFDPlayRemoteFeedTableViewController"]) {
            return;
        }
        parentVC = parentVC.parentViewController;
        count++;
    }

    CGRect frame = view.frame;
    CGFloat screenWidth = CGRectGetWidth(UIScreen.mainScreen.bounds);
    CGFloat superviewHeight = CGRectGetHeight(view.superview.bounds);
    if (frame.size.width != screenWidth && CGRectGetHeight(frame) < superviewHeight) {
        return;
    }

    // 部分 refer 场景（搜索、挑战、朋友动态等）需要互动层也铺满全高；
    // 普通信息流则只给「屏高 − 底栏高」，把文案压到底栏上方。
    NSString *referString = DYFSSafeValueForKey(controller, @"referString");
    BOOL useFullHeight = (referString == nil);
    NSArray<NSString *> *fullHeightRefers = @[
        @"general_search", @"search_result", @"search_ecommerce",
        @"close_friends_moment", @"offline_mode", @"challenge",
        @"general_search_scan"
    ];
    if (!useFullHeight) {
        for (NSString *r in fullHeightRefers) {
            if ([referString isEqualToString:r]) { useFullHeight = YES; break; }
        }
    }

    CGFloat tabBarHeight = DYFSBottomTabBarHeight(view);
    CGFloat targetHeight = useFullHeight ? superviewHeight : (superviewHeight - tabBarHeight);
    if (!isfinite(targetHeight) || targetHeight <= 1.0) return;

    if (fabs(targetHeight - CGRectGetHeight(frame)) > 0.5) {
        CGFloat oldHeight = CGRectGetHeight(frame);
        frame.size.height = targetHeight;
        view.frame = frame;
        DYFSInteractionContainerAdjustCount++;
        DYFSLog([NSString stringWithFormat:
            @"interaction controller height %.2f -> %.2f (parent %.2f, tab bar %.2f, full=%d)",
            oldHeight, targetHeight, superviewHeight, tabBarHeight, useFullHeight]);
    }
}

static void DYFSApplyPlayerContentHeightNow(id playerController) {
    if (!DYFSIsEnabled()) return;

    UIView *controllerView = [playerController isKindOfClass:UIViewController.class]
        ? ((UIViewController *)playerController).view : nil;
    // Unlike an active live room, the pre-stream preview is a screen that the
    // user explicitly wants adjusted. Some builds host its player in a sibling
    // controller, so use the active pre-stream context as a positive match too.
    if (DYFSIsActualLiveRoomContext(controllerView)) return;
    BOOL isLivePreStream = DYFSIsLivePreStreamPlayer(playerController) ||
        DYFSIsLivePreStreamContext(controllerView);

    UIView *contentView = DYFSSafeValueForKey(playerController, @"contentView");
    if (DYFSIsActualLiveRoomContext(contentView)) return;
    if (DYFSIsLivePreStreamContext(contentView)) isLivePreStream = YES;
    if (DYFSInProfileContext(controllerView) || DYFSInProfileContext(contentView) ||
        DYFSIsDetailVideoContext(controllerView) || DYFSIsDetailVideoContext(contentView)) {
        return;
    }
    if (![contentView isKindOfClass:UIView.class] || !contentView.superview ||
        !contentView.window || !contentView.superview.window) return;

    UIView *parent = contentView.superview;
    CGFloat parentHeight = CGRectGetHeight(parent.bounds);
    CGFloat currentHeight = CGRectGetHeight(contentView.frame);
    CGFloat diff = parentHeight - currentHeight;
    CGFloat tabBarHeight = DYFSBottomTabBarHeight(contentView);
    CGFloat tolerance = MAX(1.0, tabBarHeight * 0.03);
    CGFloat targetHeight = currentHeight;

    // Match the two common wrapper cases seen in DYYY: one tab-bar height short,
    // or two tab-bar heights short. This targets contentView only, never controls.
    if (fabs(diff - tabBarHeight) <= tolerance) {
        targetHeight = parentHeight;
    } else if (fabs(diff - (tabBarHeight * 2.0)) <= tolerance) {
        targetHeight = parentHeight - tabBarHeight;
    } else {
        return;
    }

    if (!isfinite(targetHeight) || targetHeight <= 1.0 ||
        fabs(currentHeight - targetHeight) <= 0.5) return;

    CGRect frame = contentView.frame;
    frame.size.height = targetHeight;
    contentView.frame = frame;
    DYFSPlayerContentAdjustCount++;
    if (isLivePreStream) DYFSLivePreviewPlayerAdjustCount++;
    DYFSLog([NSString stringWithFormat:
        @"%@%@ contentView height %.2f -> %.2f (parent %.2f, diff %.2f, tab bar %.2f)",
        isLivePreStream ? @"pre-stream " : @"",
        NSStringFromClass([playerController class]), currentHeight, targetHeight, parentHeight, diff, tabBarHeight]);
}

static void DYFSSchedulePlayerContentHeight(id playerController) {
    if (!playerController || !DYFSIsEnabled()) return;
    UIViewController *controllerViewController = [playerController isKindOfClass:UIViewController.class]
        ? (UIViewController *)playerController : nil;
    UIView *controllerView = controllerViewController.view;
    if (DYFSInProfileContext(controllerView) || DYFSIsDetailVideoContext(controllerView)) return;

    UIView *currentContent = DYFSSafeValueForKey(playerController, @"contentView");
    UIView *currentParent = [currentContent isKindOfClass:UIView.class] ? currentContent.superview : nil;
    if ([currentContent isKindOfClass:UIView.class] && currentParent && currentContent.window && currentParent.window) {
        NSArray *settled = objc_getAssociatedObject(playerController, &kDYFSPlayerSettledGeometryKey);
        if ([settled isKindOfClass:NSArray.class] && settled.count == 3) {
            CGFloat parentWidth = CGRectGetWidth(currentParent.bounds);
            CGFloat parentHeight = CGRectGetHeight(currentParent.bounds);
            CGFloat contentHeight = CGRectGetHeight(currentContent.bounds);
            if (fabs([settled[0] doubleValue] - parentWidth) <= 1.0 &&
                fabs([settled[1] doubleValue] - parentHeight) <= 1.0 &&
                fabs([settled[2] doubleValue] - contentHeight) <= 1.0) return;
        }
    }
    if ([objc_getAssociatedObject(playerController, &kDYFSPlayerLayoutPendingKey) boolValue]) return;

    objc_setAssociatedObject(playerController, &kDYFSPlayerLayoutPendingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak id weakController = playerController;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDYFSPlayerSettleDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        id strongController = weakController;
        if (!strongController) return;
        objc_setAssociatedObject(strongController, &kDYFSPlayerLayoutPendingKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        UIView *content = DYFSSafeValueForKey(strongController, @"contentView");
        UIView *parent = [content isKindOfClass:UIView.class] ? content.superview : nil;
        if (!content.window || !parent.window) return;

        CGFloat parentHeight = CGRectGetHeight(parent.bounds);
        NSNumber *previousHeight = objc_getAssociatedObject(content, &kDYFSPlayerParentHeightKey);
        if (!previousHeight || fabs(previousHeight.doubleValue - parentHeight) > 1.0) {
            objc_setAssociatedObject(content, &kDYFSPlayerParentHeightKey, @(parentHeight), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            DYFSSchedulePlayerContentHeight(strongController);
            return;
        }

        DYFSApplyPlayerContentHeightNow(strongController);

        CGFloat settledParentWidth = CGRectGetWidth(parent.bounds);
        CGFloat settledParentHeight = CGRectGetHeight(parent.bounds);
        CGFloat settledContentHeight = CGRectGetHeight(content.bounds);
        objc_setAssociatedObject(strongController, &kDYFSPlayerSettledGeometryKey,
            @[@(settledParentWidth), @(settledParentHeight), @(settledContentHeight)],
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

static void DYFSPlayerContentLayoutCommon(id self, SEL cmd, IMP original) {
    if (original) ((void (*)(id, SEL))original)(self, cmd);
    // 透明化不依赖尺寸匹配：个人主页（我-作品 / 我-喜欢）不参与高度修正，
    // 但底栏与「相关搜索」/「合集」卡片仍需要透明。
    UIView *root = [self isKindOfClass:UIViewController.class] ? ((UIViewController *)self).view : nil;
    DYFSTransparencyApplyInView(root);
    if (root.superview) DYFSTransparencyApplyInView(root.superview);
    DYFSSchedulePlayerContentHeight(self);
}

// ---------------------------------------------------------------------------
// 详情页（我-作品 / 我-喜欢 / 收藏 里点开的视频）透明化。
//
// 这类页面不走首页 feed 的那几个类，之前 DYFSTransparencyApplyInView 根本没被
// 调用，所以它自己那条贴底黑条一直是黑的。这里只补「触发」，不做任何高度修正，
// 避免与 DYYY 的详情页相关功能冲突。
// ---------------------------------------------------------------------------
static void DYFSScheduleDetailTransparency(UIView *view) {
    if (!view || DYFSDetailTransparencyScheduled) return;
    DYFSDetailTransparencyScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        DYFSDetailTransparencyScheduled = NO;
        if (!DYFSIsEnabled()) return;
        DYFSTransparencyApplyInView(view);
        if (view.superview) DYFSTransparencyApplyInView(view.superview);
    });
}

static void DYFSDetailLayoutCommon(id self, SEL cmd, IMP original) {
    if (original) ((void (*)(id, SEL))original)(self, cmd);
    if (!DYFSIsEnabled()) return;
    UIViewController *controller = (UIViewController *)self;
    DYFSScheduleDetailTransparency(controller.view);
}

static void DYFSDetailTableLayout(id self, SEL cmd) {
    DYFSDetailLayoutCommon(self, cmd, DYFSOriginalDetailTableLayout);
}

static void DYFSDetailCellLayout(id self, SEL cmd) {
    DYFSDetailLayoutCommon(self, cmd, DYFSOriginalDetailCellLayout);
}

static void DYFSMixPanelLayout(id self, SEL cmd) {
    DYFSDetailLayoutCommon(self, cmd, DYFSOriginalMixPanelLayout);
}

void DYFSPlayerContentLayoutA(id self, SEL cmd) {
    DYFSPlayerContentLayoutCommon(self, cmd, DYFSOriginalPlayerContentA);
}

void DYFSPlayerContentLayoutB(id self, SEL cmd) {
    DYFSPlayerContentLayoutCommon(self, cmd, DYFSOriginalPlayerContentB);
}

void DYFSPlayerContentLayoutC(id self, SEL cmd) {
    DYFSPlayerContentLayoutCommon(self, cmd, DYFSOriginalPlayerContentC);
}



// ---------------------------------------------------------------------------
// 复刻 DYYY 的兜底机制：全局拦截 -setFrame:。
//
// 信息流里的直播卡片并不走 AWE 的播放器控制器层级，靠 hook cell 去搬动视图
// 只会把视频推离原位。DYYY 的做法是在 -setFrame: 上统一兜底：凡是属于播放器
// 控制器的视图，只要新高度比父视图"恰好差一个底栏"，就把高度补齐到父视图，
// 且完全不动 origin —— 视频与文案都停在原位，只是下方不再留黑边。
// ---------------------------------------------------------------------------
static BOOL DYFSIsPlayerViewController(UIViewController *vc) {
    if (!vc) return NO;
    static Class playClassA, playClassB, playClassC;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        playClassA = NSClassFromString(kDYFSClassPlayVideoA);
        playClassB = NSClassFromString(kDYFSClassPlayVideoB);
        playClassC = NSClassFromString(kDYFSClassPlayVideoC);
    });
    return (playClassA && [vc isKindOfClass:playClassA]) ||
           (playClassB && [vc isKindOfClass:playClassB]) ||
           (playClassC && [vc isKindOfClass:playClassC]);
}

static void DYFSUIViewSetFrame(id self, SEL cmd, CGRect frame) {
    if (!DYFSOriginalSetFrame) return;

    if (DYFSIsEnabled() && [self isKindOfClass:UIView.class]) {
        UIView *view = (UIView *)self;
        UIView *superview = view.superview;
        CGFloat superH = CGRectGetHeight(superview.frame);
        CGFloat height = CGRectGetHeight(frame);

        // 与 DYYY 完全一致：只处理没有位移、且高度差刚好一个底栏的播放器 view。
        // 注意：播放器根 view 内部本来就含 UILabel（时长/标题等），因此
        // 「子树有文字就不补」的判断必须去掉——否则补高永远被拦掉。
        if (superview && superH > 0 && height > 0 && height < superH &&
            frame.origin.x == 0 && frame.origin.y == 0) {
            CGFloat diff = superH - height;
            CGFloat tabBarHeight = DYFSBottomTabBarHeight(view);
            if (tabBarHeight > 0 && fabs(diff - tabBarHeight) < 1.0) {
                UIViewController *vc = DYFSFindViewController(view);
                if (DYFSIsPlayerViewController(vc)) {
                    frame.size.height = superH;   // 只补高度，origin 不动
                    DYFSSetFrameLiftCount++;
                }
            }
        }
    }

    ((void (*)(id, SEL, CGRect))DYFSOriginalSetFrame)(self, cmd, frame);
}

void DYFSLayoutInstallHooks(void) {
    Class cls = NSClassFromString(kDYFSClassFeedTableView);
    if (!DYFSInstalledFeed && cls) {
        DYFSInstalledFeed = DYFSInstallHook(cls, @selector(layoutSubviews),
                                            (IMP)DYFSFeedTableLayout, &DYFSOriginalFeedLayout);
    }

    cls = NSClassFromString(kDYFSClassStoryContainer);
    if (!DYFSInstalledStory && cls) {
        DYFSInstalledStory = DYFSInstallHook(cls, @selector(layoutSubviews),
                    (IMP)DYFSStoryContainerLayout, &DYFSOriginalStoryLayout);
    }

    cls = NSClassFromString(kDYFSClassPlayInteraction);
    if (!DYFSInstalledInteractionController && cls) {
        DYFSInstalledInteractionController = DYFSInstallHook(cls, @selector(viewDidLayoutSubviews),
                    (IMP)DYFSInteractionControllerLayout, &DYFSOriginalInteractionControllerLayout);
    }

    cls = NSClassFromString(kDYFSClassPlayVideoA);
    if (!DYFSInstalledPlayerContentA && cls) {
        DYFSInstalledPlayerContentA = DYFSInstallHook(cls, @selector(viewDidLayoutSubviews),
                    (IMP)DYFSPlayerContentLayoutA, &DYFSOriginalPlayerContentA);
    }

    cls = NSClassFromString(kDYFSClassPlayVideoB);
    if (!DYFSInstalledPlayerContentB && cls) {
        DYFSInstalledPlayerContentB = DYFSInstallHook(cls, @selector(viewDidLayoutSubviews),
                    (IMP)DYFSPlayerContentLayoutB, &DYFSOriginalPlayerContentB);
    }

    cls = NSClassFromString(kDYFSClassPlayVideoC);
    if (!DYFSInstalledPlayerContentC && cls) {
        DYFSInstalledPlayerContentC = DYFSInstallHook(cls, @selector(viewDidLayoutSubviews),
                    (IMP)DYFSPlayerContentLayoutC, &DYFSOriginalPlayerContentC);
    }

    // 详情页 / 个人主页视频页：只触发透明化，不改高度。
    cls = NSClassFromString(kDYFSClassDetailTable);
    if (cls && !DYFSOriginalDetailTableLayout) {
        DYFSInstallHook(cls, @selector(viewDidLayoutSubviews),
                        (IMP)DYFSDetailTableLayout, &DYFSOriginalDetailTableLayout);
    }
    cls = NSClassFromString(kDYFSClassDetailCell);
    if (cls && !DYFSOriginalDetailCellLayout) {
        DYFSInstallHook(cls, @selector(viewDidLayoutSubviews),
                        (IMP)DYFSDetailCellLayout, &DYFSOriginalDetailCellLayout);
    }
    cls = NSClassFromString(kDYFSClassMixPanel);
    if (cls && !DYFSOriginalMixPanelLayout) {
        DYFSInstallHook(cls, @selector(viewDidLayoutSubviews),
                        (IMP)DYFSMixPanelLayout, &DYFSOriginalMixPanelLayout);
    }

    // 全局兜底：装在 UIView 上，覆盖信息流直播卡片这类不走播放器层级的内容。
    static BOOL installedSetFrame = NO;
    if (!installedSetFrame) {
        installedSetFrame = DYFSInstallHook(UIView.class, @selector(setFrame:),
                                            (IMP)DYFSUIViewSetFrame, &DYFSOriginalSetFrame);
    }
}
