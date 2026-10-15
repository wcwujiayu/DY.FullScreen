//
//  DYFSLayout.m
//  DY.FullScreen
//
//  全屏尺寸修正：以 0.3.15 的逻辑为准（0.4.x 把它改坏了）。
//  去灰底统一走 0.4.x 的 DYFSTransparencyApplyInView。
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
static IMP DYFSOriginalElementStackLayout = NULL;
static IMP DYFSOriginalDetailTableLayout = NULL;
static IMP DYFSOriginalDetailCellLayout = NULL;
static IMP DYFSOriginalMixPanelDetailLayout = NULL;
static IMP DYFSOriginalLivePreStreamLayout = NULL;

// 等父容器尺寸稳定后再匹配高度，避免与原生布局互相触发。
// 0.05s：原来的 0.18s 会让"关掉评论区后画面先黑底、再拉伸"的过程肉眼可见。
static const NSTimeInterval kDYFSPlayerSettleDelay = 0.05;
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

void DYFSDetailTableLayout(id self, SEL cmd) {
    if (DYFSOriginalDetailTableLayout) {
        ((void (*)(id, SEL))DYFSOriginalDetailTableLayout)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;
    UIView *root = [self isKindOfClass:UIViewController.class] ? ((UIViewController *)self).view : nil;
    DYFSTransparencyApplyInView(root);
}

void DYFSDetailCellLayout(id self, SEL cmd) {
    if (DYFSOriginalDetailCellLayout) {
        ((void (*)(id, SEL))DYFSOriginalDetailCellLayout)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;
    UIView *root = [self isKindOfClass:UIViewController.class] ? ((UIViewController *)self).view : nil;
    DYFSTransparencyApplyInView(root);
}

void DYFSMixPanelDetailLayout(id self, SEL cmd) {
    if (DYFSOriginalMixPanelDetailLayout) {
        ((void (*)(id, SEL))DYFSOriginalMixPanelDetailLayout)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;
    UIView *root = [self isKindOfClass:UIViewController.class] ? ((UIViewController *)self).view : nil;
    DYFSTransparencyApplyInView(root);
}

void DYFSInteractionControllerLayout(id self, SEL cmd) {
    if (DYFSOriginalInteractionControllerLayout) {
        ((void (*)(id, SEL))DYFSOriginalInteractionControllerLayout)(self, cmd);
    }
    UIViewController *controller = (UIViewController *)self;
    UIView *view = controller.view;
    if (!DYFSIsEnabled()) return;
    DYFSTransparencyApplyInView(view);
    if (view.superview) DYFSTransparencyApplyInView(view.superview);
    if (!view || !view.superview || DYFSInProfileContext(view)) return;
    if (!DYFSIsFeedCellInteractionController(controller)) return;

    UIView *parent = view.superview;
    CGFloat parentHeight = CGRectGetHeight(parent.bounds);
    CGFloat tabBarHeight = DYFSBottomTabBarHeight(view);
    CGFloat targetHeight = parentHeight - tabBarHeight;
    CGRect frame = view.frame;
    CGFloat screenWidth = CGRectGetWidth(UIScreen.mainScreen.bounds);

    if (!isfinite(targetHeight) || targetHeight <= 1.0 ||
        (fabs(CGRectGetWidth(frame) - screenWidth) > 1.0 && CGRectGetHeight(frame) < parentHeight)) {
        return;
    }
    if (fabs(CGRectGetHeight(frame) - targetHeight) <= 0.5) return;

    CGFloat oldHeight = CGRectGetHeight(frame);
    frame.size.height = targetHeight;
    view.frame = frame;
    DYFSInteractionContainerAdjustCount++;
    DYFSLog([NSString stringWithFormat:
        @"interaction controller height %.2f -> %.2f (parent %.2f, tab bar %.2f)",
        oldHeight, targetHeight, parentHeight, tabBarHeight]);
}

static void DYFSApplyPlayerContentHeightNow(id playerController) {
    if (!DYFSIsEnabled()) return;

    UIView *controllerView = [playerController isKindOfClass:UIViewController.class]
        ? ((UIViewController *)playerController).view : nil;
    UIView *contentView = DYFSSafeValueForKey(playerController, @"contentView");
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
    DYFSLog([NSString stringWithFormat:
        @"%@ contentView height %.2f -> %.2f (parent %.2f, diff %.2f, tab bar %.2f)",
        NSStringFromClass([playerController class]), currentHeight, targetHeight, parentHeight, diff, tabBarHeight]);
}

static void DYFSSchedulePlayerContentHeight(id playerController) {
    if (!playerController || !DYFSIsEnabled()) return;
    UIViewController *controllerViewController = [playerController isKindOfClass:UIViewController.class]
        ? (UIViewController *)playerController : nil;
    UIView *controllerView = controllerViewController.view;
    if (DYFSInProfileContext(controllerView) || DYFSIsDetailVideoContext(controllerView)) {
        return;
    }

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

        UIViewController *vc = [strongController isKindOfClass:UIViewController.class]
            ? (UIViewController *)strongController : nil;
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

        if (vc) {
            DYFSTransparencyApplyInView(vc.view);
            if (vc.view.superview) DYFSTransparencyApplyInView(vc.view.superview);
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

// 详情页（我-喜欢/我-作品/收藏/推荐/聊天分享）：视频撑满整屏。
// 承载视频的 AWEAwemeDetailTableView 只有 843 高且 clipsToBounds=YES，会裁掉拉满的
// 视频，底部 83pt 露出背后纯黑板 —— 这才是「底栏不透明」的根源。故把整宽且「正好
// 差一个底栏高度」的容器链（cell / 表格 / 播放器）拉到整屏，并清掉纯黑底。
static void DYFSApplyDetailFullscreen(UIView *root) {
    if (!root || !DYFSIsEnabled()) return;
    UIWindow *window = root.window;
    if (!window) return;
    CGFloat screenH = CGRectGetHeight(window.bounds);
    CGFloat screenW = CGRectGetWidth(window.bounds);
    if (screenH <= 1.0 || screenW <= 1.0) return;
    CGFloat tabH = DYFSBottomTabBarHeight(root);
    CGFloat tol = MAX(2.0, tabH * 0.5);

    // 向上：cell / 表格等祖先拉到整屏，并清掉纯黑不透明底
    for (UIView *cursor = root; cursor; cursor = cursor.superview) {
        if (CGRectGetWidth(cursor.bounds) < screenW * 0.9) continue;
        if (fabs(screenH - CGRectGetHeight(cursor.bounds) - tabH) > tol) continue;
        UIColor *bg = cursor.backgroundColor;
        CGFloat r = 0, g = 0, b = 0, a = 0, white = 0;
        BOOL ok = [bg getRed:&r green:&g blue:&b alpha:&a];
        if (!ok && [bg getWhite:&white alpha:&a]) { r = g = b = white; ok = YES; }
        if (ok && a > 0.9 && (0.299 * r + 0.587 * g + 0.114 * b) < 0.1) {
            DYFSBackupAppearance(cursor);
            cursor.backgroundColor = UIColor.clearColor;
            cursor.layer.backgroundColor = UIColor.clearColor.CGColor;
            cursor.opaque = NO;
        }
        CGRect frame = cursor.frame;
        frame.size.height = screenH;
        cursor.frame = frame;
        DYFSLayoutFixCount++;
    }

    // 向下：播放器一侧同样补齐
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:root];
    for (NSUInteger visited = 0; pending.count > 0 && visited < 200; visited++) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        [pending addObjectsFromArray:view.subviews];
        if (view.hidden || view.alpha <= 0.01) continue;
        if (CGRectGetWidth(view.bounds) < screenW * 0.9) continue;
        if (fabs(screenH - CGRectGetHeight(view.bounds) - tabH) > tol) continue;
        CGRect frame = view.frame;
        frame.size.height = screenH;
        view.frame = frame;
        DYFSLayoutFixCount++;
    }
}

void DYFSPlayerContentLayoutA(id self, SEL cmd) {
    if (DYFSOriginalPlayerContentA) ((void (*)(id, SEL))DYFSOriginalPlayerContentA)(self, cmd);
    UIView *root = [self isKindOfClass:UIViewController.class] ? ((UIViewController *)self).view : nil;
    DYFSTransparencyApplyInView(root);
    if (root.superview) DYFSTransparencyApplyInView(root.superview);
    DYFSSchedulePlayerContentHeight(self);
    DYFSApplyDetailFullscreen(root);
}

void DYFSPlayerContentLayoutB(id self, SEL cmd) {
    if (DYFSOriginalPlayerContentB) ((void (*)(id, SEL))DYFSOriginalPlayerContentB)(self, cmd);
    UIView *root = [self isKindOfClass:UIViewController.class] ? ((UIViewController *)self).view : nil;
    DYFSTransparencyApplyInView(root);
    if (root.superview) DYFSTransparencyApplyInView(root.superview);
    DYFSSchedulePlayerContentHeight(self);
    DYFSApplyDetailFullscreen(root);
}

void DYFSPlayerContentLayoutC(id self, SEL cmd) {
    if (DYFSOriginalPlayerContentC) ((void (*)(id, SEL))DYFSOriginalPlayerContentC)(self, cmd);
    UIView *root = [self isKindOfClass:UIViewController.class] ? ((UIViewController *)self).view : nil;
    DYFSTransparencyApplyInView(root);
    if (root.superview) DYFSTransparencyApplyInView(root.superview);
    DYFSSchedulePlayerContentHeight(self);
    DYFSApplyDetailFullscreen(root);
}

void DYFSElementStackLayout(id self, SEL cmd) {
    if (DYFSOriginalElementStackLayout) {
        ((void (*)(id, SEL))DYFSOriginalElementStackLayout)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;
    DYFSTransparencyApplyInView((UIView *)self);
    if (((UIView *)self).superview) {
        DYFSTransparencyApplyInView(((UIView *)self).superview);
    }
}

void DYFSStoryContainerLayout(id self, SEL cmd) {
    if (DYFSOriginalStoryLayout) {
        ((void (*)(id, SEL))DYFSOriginalStoryLayout)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;

    UIView *container = (UIView *)self;
    if (DYFSInProfileContext(container)) return;

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

// 直播预览卡片（AWELivePreStream4LayerContainerView）底部信息面板当前会延伸到
// 屏幕最底部，与 tab 底栏重叠，导致左下角文案被遮挡。这里把它整体上移，
// 使面板底部停在 tab 栏上方。
static void DYFSAdjustLivePreStreamBottomPanel(UIView *container) {
    if (!container || !DYFSIsLivePreStreamContext(container)) return;
    CGFloat containerH = CGRectGetHeight(container.bounds);
    if (containerH < 200.0) return;
    CGFloat tabH = DYFSBottomTabBarHeight(container);
    CGFloat targetBottom = containerH - tabH;

    UIView *panel = nil;
    CGFloat bestBottom = -CGFLOAT_MAX;
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:container];
    while (pending.count > 0) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        [pending addObjectsFromArray:view.subviews];
        NSString *name = NSStringFromClass(view.class);
        if (![name containsString:@"IESLiveLayoutContainerView"]) continue;
        CGFloat h = CGRectGetHeight(view.bounds);
        if (h < 80.0 || h > 250.0) continue;
        // 用 center + bounds 算底边：不掺入已应用的 transform，
        // 多次调用排名稳定，不会因为上移过就选错面板。
        CGPoint bottomPoint = CGPointMake(view.center.x, view.center.y + h * 0.5);
        CGFloat bottom = [view.superview convertPoint:bottomPoint toView:container].y;
        if (bottom > bestBottom) { bestBottom = bottom; panel = view; }
    }
    if (!panel) return;

    // 用 transform 而不是改 frame：Auto Layout 重排只会改写 center / bounds，
    // 不会清掉 transform。之前改 frame 会被抖音后续布局压回底栏，表现为时好时坏。
    CGPoint bottomPoint = CGPointMake(panel.center.x,
                                      panel.center.y + CGRectGetHeight(panel.bounds) * 0.5);
    CGFloat layoutBottom = [panel.superview convertPoint:bottomPoint toView:container].y;
    CGFloat visualBottom = layoutBottom + panel.transform.ty;   // 叠上已应用的位移
    CGFloat shift = visualBottom - targetBottom;
    if (fabs(shift) > 1.0) {
        panel.transform = CGAffineTransformTranslate(panel.transform, 0.0, -shift);
        DYFSLog([NSString stringWithFormat:
                 @"live pre-stream bottom panel shifted %.2f (bottom %.2f -> %.2f)",
                 -shift, visualBottom, targetBottom]);
    }
}

void DYFSLivePreStreamLayout(id self, SEL cmd) {
    if (DYFSOriginalLivePreStreamLayout) {
        ((void (*)(id, SEL))DYFSOriginalLivePreStreamLayout)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;
    UIView *container = (UIView *)self;
    DYFSAdjustLivePreStreamBottomPanel(container);
    // 面板可能此刻还没布局完（高度还是 0），下一帧与稍后各补一次，
    // 等它真正有尺寸后再上移。transform 会一直保留，不会互相打架。
    dispatch_async(dispatch_get_main_queue(), ^{
        DYFSAdjustLivePreStreamBottomPanel(container);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        DYFSAdjustLivePreStreamBottomPanel(container);
    });
}

void DYFSFeedTableLayout(id self, SEL cmd) {
    if (DYFSOriginalFeedLayout) ((void (*)(id, SEL))DYFSOriginalFeedLayout)(self, cmd);
    if (!DYFSIsEnabled()) return;

    UIView *view = (UIView *)self;
    UIView *parent = view.superview;
    if (!parent || DYFSInProfileContext(view)) return;
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

    // 0.4.x 曾给这个 hook 加「只在直播卡片内生效」的守卫，导致普通视频
    // 互动层高度不再调整 —— 全屏就是这么被改坏的。这里恢复对普通视频生效。
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

    // AWEElementStackView 是「相关搜索」/「合集」胶囊的直接宿主，
    // 不是直播间类 —— 别被旧命名里的 "Live" 误导而删掉。
    cls = NSClassFromString(kDYFSClassElementStack);
    if (!DYFSInstalledElementStack && cls) {
        DYFSInstalledElementStack = DYFSInstallHook(cls, @selector(layoutSubviews),
                    (IMP)DYFSElementStackLayout, &DYFSOriginalElementStackLayout);
    }

    // 详情页 / 合集页：触发透明化与底部黑条清理。
    cls = NSClassFromString(kDYFSClassDetailTable);
    if (cls && !DYFSInstalledDetailTable) {
        DYFSInstalledDetailTable = DYFSInstallHook(cls, @selector(viewDidLayoutSubviews),
                    (IMP)DYFSDetailTableLayout, &DYFSOriginalDetailTableLayout);
    }
    cls = NSClassFromString(kDYFSClassDetailCell);
    if (cls && !DYFSInstalledDetailCell) {
        DYFSInstalledDetailCell = DYFSInstallHook(cls, @selector(viewDidLayoutSubviews),
                    (IMP)DYFSDetailCellLayout, &DYFSOriginalDetailCellLayout);
    }
    cls = NSClassFromString(kDYFSClassMixPanel);
    if (cls && !DYFSInstalledMixPanelDetail) {
        DYFSInstalledMixPanelDetail = DYFSInstallHook(cls, @selector(viewDidLayoutSubviews),
                    (IMP)DYFSMixPanelDetailLayout, &DYFSOriginalMixPanelDetailLayout);
    }

    // 直播预览卡片：底部信息面板不能压到 tab 底栏上。
    static BOOL livePreStreamHookInstalled = NO;
    cls = NSClassFromString(@"AWELivePreStream4LayerContainerView");
    if (cls && !livePreStreamHookInstalled) {
        livePreStreamHookInstalled = DYFSInstallHook(cls, @selector(layoutSubviews),
                    (IMP)DYFSLivePreStreamLayout, &DYFSOriginalLivePreStreamLayout);
    }
}
