//
//  DYFSChrome.m
//  DY.FullScreen
//
//  Chrome cleanup: hide the bottom tab bar background and clear the dark bars
//  that Douyin leaves inside the progress containers in full-screen mode.
//

#import "DYFSChrome.h"
#import "DYFSCommon.h"
#import "DYFSContext.h"
#import "DYFSLayout.h"
#import <objc/message.h>

static IMP DYFSOriginalTabBarLayout = NULL;
static IMP DYFSOriginalTabBarHidden = NULL;
static IMP DYFSOriginalTabBarDidMove = NULL;
static IMP DYFSOriginalTabBarDidAddSubview = NULL;
static IMP DYFSOriginalInteractionProgressLayout = NULL;
static IMP DYFSOriginalPlayerProgressLayout = NULL;

// Collapses repeated transparency requests within one main-queue turn.
static BOOL DYFSTabBarTransparencyScheduled = NO;

static IMP DYFSOriginalLiveCellLayout = NULL;
static BOOL DYFSInstalledLiveCard = NO;

// 直播卡片内嵌的 audienceVC 会在自己的 -viewDidLayoutSubviews 里重新排布底部
// 文案/点赞区，从而把 cell 级的上移覆盖掉。这里再挂一个 audienceVC 钩子，在它
// 自己排好之后再次上移，保证账号/文案/点赞区稳定停在底栏上方。
static IMP DYFSOriginalLiveAudienceLayoutIES = NULL;
static IMP DYFSOriginalLiveAudienceLayoutAWE = NULL;
static BOOL DYFSInstalledLiveAudienceIES = NO;
static BOOL DYFSInstalledLiveAudienceAWE = NO;

// 兜底：拦截底栏 -setBackgroundColor:，启用时强制清成透明，避免抖音在布局后
// 又把背景刷成深色（与 DYYY 的 skinContainerView 隐藏互不冲突）。
static IMP DYFSOriginalTabBarSetBackgroundColor = NULL;
static BOOL DYFSInstalledTabBarSetBackgroundColor = NO;


// ---------------------------------------------------------------------------
// 信息流直播卡片：只把账号 / 文案 / 按钮顶到底栏上方，视频层完全不动。
//
// 视频所在的视图是铺满且无文字无控件的，遇到它就继续下钻；
// 只有"下游含文字或控件"的容器才会被上移，且上移量按窗口坐标计算，
// 因此不会把视频推离原位。
// ---------------------------------------------------------------------------
static BOOL DYFSLiveCardSubtreeHasContent(UIView *view, NSUInteger depth) {
    if (!view || depth > 8) return NO;
    if ([view isKindOfClass:UIControl.class] || [view isKindOfClass:UIButton.class] ||
        [view isKindOfClass:UITextField.class]) return YES;
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        if (label.text.length > 0 || label.attributedText.length > 0) return YES;
    }
    for (UIView *sub in view.subviews) {
        if (DYFSLiveCardSubtreeHasContent(sub, depth + 1)) return YES;
    }
    return NO;
}

static void DYFSLiftLiveCardContent(UIView *container, UIView *reference, CGFloat limitY) {
    if (!container || !reference) return;
    CGFloat w = CGRectGetWidth(container.bounds), h = CGRectGetHeight(container.bounds);

    for (UIView *sub in [container.subviews copy]) {
        if (sub.hidden || sub.alpha <= 0.01) continue;

        CGFloat sw = CGRectGetWidth(sub.frame), sh = CGRectGetHeight(sub.frame);
        BOOL fills = w > 0 && h > 0 && sw >= w * 0.95 && sh >= h * 0.90;
        if (fills) {                                   // 视频层 / 背景层：继续下钻
            DYFSLiftLiveCardContent(sub, reference, limitY);
            continue;
        }
        if (!DYFSLiveCardSubtreeHasContent(sub, 0)) continue;   // 纯背景：不动

        CGRect rect = [sub convertRect:sub.bounds toView:reference];
        CGFloat delta = CGRectGetMaxY(rect) - limitY;
        if (delta <= 1.0) continue;

        CGRect frame = sub.frame;
        frame.origin.y -= delta;
        if (CGRectGetMinY(frame) < -1.0) continue;     // 别顶出屏幕
        sub.frame = frame;
        // 诊断日志（每次启动最多几条，确认上移逻辑确实命中卡片内容）。
        static NSUInteger liftLogCount = 0;
        if (liftLogCount < 6) {
            liftLogCount++;
            DYFSLog([NSString stringWithFormat:
                @"live-card lift: %@ moved up %.1f (limitY %.1f)",
                NSStringFromClass(sub.class), delta, limitY]);
        }
    }
}

static void DYFSLiveCellLayout(id self, SEL cmd) {
    if (DYFSOriginalLiveCellLayout) ((void (*)(id, SEL))DYFSOriginalLiveCellLayout)(self, cmd);
    if (!DYFSIsEnabled()) return;

    UIView *cell = (UIView *)self;
    if (!cell.window) return;
    if (DYFSIsActualLiveRoomContext(cell) || DYFSIsLivePreStreamContext(cell)) return;

    id audience = nil;
    @try {
        SEL selector = NSSelectorFromString(@"audienceVC");
        if ([cell respondsToSelector:selector]) {
            audience = ((id (*)(id, SEL))objc_msgSend)(cell, selector);
        }
        if (!audience) audience = DYFSSafeValueForKey(cell, @"audienceVC");
    } @catch (__unused NSException *exception) {
        return;
    }
    if (![audience isKindOfClass:UIViewController.class]) return;

    UIView *content = ((UIViewController *)audience).view;
    if (!content || !content.window) return;

    CGFloat windowHeight = CGRectGetHeight(cell.window.bounds);
    CGFloat tabBarHeight = DYFSBottomTabBarHeight(cell);
    CGFloat limitY = windowHeight - tabBarHeight;
    if (limitY <= 0) return;

    DYFSLiftLiveCardContent(content, cell.window, limitY);
}

// 供 audienceVC 的 -viewDidLayoutSubviews 钩子复用：只在「直播卡片内嵌」的
// audienceVC 上移内容，真实直播间里不触发（真实的 audienceVC 不在卡片内）。
static void DYFSLiveAudienceLift(id self, SEL cmd) {
    UIViewController *vc = (UIViewController *)self;
    UIView *view = vc.view;
    if (!view || !view.window) return;
    if (!DYFSViewIsInsideLiveFeedCell(view)) return;
    if (DYFSIsLivePreStreamContext(view)) return;

    CGFloat windowHeight = CGRectGetHeight(view.window.bounds);
    CGFloat tabBarHeight = DYFSBottomTabBarHeight(view);
    CGFloat limitY = windowHeight - tabBarHeight;
    if (limitY <= 0) return;

    DYFSLiftLiveCardContent(view, view.window, limitY);
}

static void DYFSLiveAudienceLayoutIES(id self, SEL cmd) {
    if (DYFSOriginalLiveAudienceLayoutIES) {
        ((void (*)(id, SEL))DYFSOriginalLiveAudienceLayoutIES)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;
    DYFSLiveAudienceLift(self, cmd);
}

static void DYFSLiveAudienceLayoutAWE(id self, SEL cmd) {
    if (DYFSOriginalLiveAudienceLayoutAWE) {
        ((void (*)(id, SEL))DYFSOriginalLiveAudienceLayoutAWE)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;
    DYFSLiveAudienceLift(self, cmd);
}

static void DYFSApplyTabBarTransparency(UIView *tabBar) {
    if (!tabBar) return;

    BOOL enabled = DYFSIsEnabled();

    // 与 DYYY（DYYY.xm 15100+）一致的底栏类名集合。
    Class generalButtonClass = NSClassFromString(kDYFSClassTabBarGeneralButton);
    Class plusButtonClass = NSClassFromString(kDYFSClassTabBarGeneralPlusButton);
    Class plusContainerClass = NSClassFromString(kDYFSClassTabBarPlusButton);
    Class plusInnerClass = NSClassFromString(@"AWENormalModeTabBarGeneralPlusInnerButton");
    Class barBackgroundClass = NSClassFromString(kDYFSClassBarBackground);   // _UIBarBackground
    Class tabBarButtonClass = NSClassFromString(@"UITabBarButton");

    id skinContainer = DYFSSafeValueForKey(tabBar, @"skinContainerView");
    if ([skinContainer isKindOfClass:UIView.class]) {
        ((UIView *)skinContainer).hidden = enabled;
    }

    // 部分版本直接把底色刷在底栏自身或它的 layer 上，这里一并清掉。
    if (enabled) {
        tabBar.backgroundColor = UIColor.clearColor;
        if (tabBar.layer) tabBar.layer.backgroundColor = UIColor.clearColor.CGColor;
        tabBar.opaque = NO;
    }

    CGFloat barHeight = CGRectGetHeight(tabBar.bounds);
    if (barHeight <= 0.0 || !isfinite(barHeight)) {
        barHeight = 49.0 + MAX(0.0, tabBar.window.safeAreaInsets.bottom);
    }

    // 单次遍历：隐藏全部背景与分割线，跳过按钮（DYYY 同款判定）。
    for (UIView *subview in [tabBar.subviews copy]) {
        if (generalButtonClass && [subview isKindOfClass:generalButtonClass]) continue;
        if (plusButtonClass && [subview isKindOfClass:plusButtonClass]) continue;
        if (plusContainerClass && [subview isKindOfClass:plusContainerClass]) continue;
        if (plusInnerClass && [subview isKindOfClass:plusInnerClass]) continue;
        if (tabBarButtonClass && [subview isKindOfClass:tabBarButtonClass]) continue;

        NSString *name = NSStringFromClass(subview.class);
        BOOL namedBackground = (barBackgroundClass && [subview isKindOfClass:barBackgroundClass]) ||
            [name containsString:@"Background"] || [name containsString:@"Backdrop"] ||
            [name containsString:@"Blur"] || [subview isKindOfClass:UIVisualEffectView.class];
        BOOL plainFullBarBackground = [subview isMemberOfClass:UIView.class] &&
            fabs(CGRectGetHeight(subview.bounds) - barHeight) < 1.0;

        if (enabled && (namedBackground || plainFullBarBackground)) {
            subview.hidden = YES;
            subview.backgroundColor = UIColor.clearColor;
            if (subview.layer) subview.layer.backgroundColor = UIColor.clearColor.CGColor;
            subview.opaque = NO;
        } else if (!enabled && (namedBackground || plainFullBarBackground)) {
            subview.hidden = NO;
        }

        // 顶部细分割线
        if (CGRectGetHeight(subview.bounds) > 0 && CGRectGetHeight(subview.bounds) < 1.0 &&
            CGRectGetWidth(subview.bounds) > 300.0) {
            subview.hidden = enabled;
        }
    }

    DYFSLastTabBackgroundHidden = enabled;
    DYFSTabBarApplyCount++;
}

static void DYFSScheduleTabBarTransparency(UIView *tabBar) {
    if (!tabBar || DYFSTabBarTransparencyScheduled) return;
    DYFSTabBarTransparencyScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        DYFSTabBarTransparencyScheduled = NO;
        DYFSApplyTabBarTransparency(tabBar);
    });
}

void DYFSTabBarLayout(id self, SEL cmd) {
    if (DYFSOriginalTabBarLayout) ((void (*)(id, SEL))DYFSOriginalTabBarLayout)(self, cmd);
    DYFSScheduleTabBarTransparency((UIView *)self);
}

void DYFSTabBarSetHidden(id self, SEL cmd, BOOL hidden) {
    if (DYFSOriginalTabBarHidden) ((void (*)(id, SEL, BOOL))DYFSOriginalTabBarHidden)(self, cmd, hidden);
    DYFSScheduleTabBarTransparency((UIView *)self);
}


void DYFSTabBarDidMoveToWindow(id self, SEL cmd) {
    if (DYFSOriginalTabBarDidMove) ((void (*)(id, SEL))DYFSOriginalTabBarDidMove)(self, cmd);
    DYFSScheduleTabBarTransparency((UIView *)self);
}

void DYFSTabBarDidAddSubview(id self, SEL cmd, UIView *subview) {
    if (DYFSOriginalTabBarDidAddSubview) ((void (*)(id, SEL, UIView *))DYFSOriginalTabBarDidAddSubview)(self, cmd, subview);
    DYFSScheduleTabBarTransparency((UIView *)self);
}

void DYFSInteractionProgressLayout(id self, SEL cmd) {
    if (DYFSOriginalInteractionProgressLayout) {
        ((void (*)(id, SEL))DYFSOriginalInteractionProgressLayout)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;

    UIView *container = (UIView *)self;
    for (UIView *subview in [container.subviews copy]) {
        if ([subview class] == UIView.class) {
            subview.backgroundColor = UIColor.clearColor;
        }
    }
}

void DYFSPlayerProgressLayout(id self, SEL cmd) {
    if (DYFSOriginalPlayerProgressLayout) {
        ((void (*)(id, SEL))DYFSOriginalPlayerProgressLayout)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;

    UIView *container = (UIView *)self;
    for (UIView *subview in [container.subviews copy]) {
        if (![subview isMemberOfClass:UIView.class]) continue;

        UIColor *background = subview.backgroundColor;
        if (!background) continue;
        // getHue:... returns NO for grayscale colors (e.g. colorWithWhite:alpha:),
        // which are exactly the black bars this hook wants to clear. Fall back to
        // getWhite:alpha: so those views are handled instead of silently skipped.
        CGFloat hue = 0.0, saturation = 0.0, brightness = 1.0, alpha = 1.0;
        CGFloat white = 1.0;
        BOOL isDark = NO;
        if ([background getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha]) {
            isDark = brightness < 0.2;
        } else if ([background getWhite:&white alpha:&alpha]) {
            isDark = white < 0.2;
        }
        if (isDark) subview.backgroundColor = UIColor.clearColor;
    }
}


// 兜底拦截底栏 -setBackgroundColor:：启用时强制透明，防止抖音在布局后把背景
// 重新刷成深色。与 DYYY 的 skinContainerView 隐藏互不冲突（DYYY 不会给底栏刷色）。
void DYFSTabBarSetBackgroundColor(id self, SEL cmd, UIColor *color) {
    if (DYFSIsEnabled()) {
        color = UIColor.clearColor;
    }
    if (DYFSOriginalTabBarSetBackgroundColor) {
        ((void (*)(id, SEL, UIColor *))DYFSOriginalTabBarSetBackgroundColor)(self, cmd, color);
    }
}

void DYFSChromeInstallHooks(void) {
    Class cls = NSClassFromString(kDYFSClassInteractionProgress);
    if (cls && !DYFSInstalledInteractionProgress) {
        DYFSInstalledInteractionProgress = DYFSInstallHook(cls, @selector(layoutSubviews),
                    (IMP)DYFSInteractionProgressLayout, &DYFSOriginalInteractionProgressLayout);
    }

    cls = NSClassFromString(kDYFSClassPlayerProgress);
    if (cls && !DYFSInstalledPlayerProgress) {
        DYFSInstalledPlayerProgress = DYFSInstallHook(cls, @selector(layoutSubviews),
                    (IMP)DYFSPlayerProgressLayout, &DYFSOriginalPlayerProgressLayout);
    }

    cls = NSClassFromString(kDYFSClassTabBar);
    if (cls && !DYFSInstalledTabBarLayout) {
        DYFSInstalledTabBarLayout = DYFSInstallHook(cls, @selector(layoutSubviews),
                    (IMP)DYFSTabBarLayout, &DYFSOriginalTabBarLayout);
    }
    if (cls && !DYFSInstalledTabBarHidden) {
        DYFSInstalledTabBarHidden = DYFSInstallHook(cls, @selector(setHidden:),
                    (IMP)DYFSTabBarSetHidden, &DYFSOriginalTabBarHidden);
    }
    if (cls && !DYFSInstalledTabBarDidMove) {
        DYFSInstalledTabBarDidMove = DYFSInstallHook(cls, @selector(didMoveToWindow),
                    (IMP)DYFSTabBarDidMoveToWindow, &DYFSOriginalTabBarDidMove);
    }
    if (cls && !DYFSInstalledTabBarDidAddSubview) {
        DYFSInstalledTabBarDidAddSubview = DYFSInstallHook(cls, @selector(didAddSubview:),
                    (IMP)DYFSTabBarDidAddSubview, &DYFSOriginalTabBarDidAddSubview);
    }
    if (cls && !DYFSInstalledTabBarSetBackgroundColor) {
        DYFSInstalledTabBarSetBackgroundColor = DYFSInstallHook(cls, @selector(setBackgroundColor:),
                    (IMP)DYFSTabBarSetBackgroundColor, &DYFSOriginalTabBarSetBackgroundColor);
    }

    cls = NSClassFromString(kDYFSClassLiveFeedCell);
    if (cls && !DYFSInstalledLiveCard) {
        DYFSInstalledLiveCard = DYFSInstallHook(cls, @selector(layoutSubviews),
                    (IMP)DYFSLiveCellLayout, &DYFSOriginalLiveCellLayout);
    }

    // 直播卡片内嵌的 audienceVC（IES / AWE 两种类名都挂），在其自身排布完之后
    // 再次上移底部内容，避免被它自己的布局覆盖。真实直播间里的同名 VC 不在卡片
    // 内，钩子里会被 DYFSViewIsInsideLiveFeedCell 拦掉，不会误伤。
    cls = NSClassFromString(@"IESLiveAudienceViewController");
    if (cls && !DYFSInstalledLiveAudienceIES) {
        DYFSInstalledLiveAudienceIES = DYFSInstallHook(cls, @selector(viewDidLayoutSubviews),
                    (IMP)DYFSLiveAudienceLayoutIES, &DYFSOriginalLiveAudienceLayoutIES);
    }
    cls = NSClassFromString(@"AWELiveAudienceViewController");
    if (cls && !DYFSInstalledLiveAudienceAWE) {
        DYFSInstalledLiveAudienceAWE = DYFSInstallHook(cls, @selector(viewDidLayoutSubviews),
                    (IMP)DYFSLiveAudienceLayoutAWE, &DYFSOriginalLiveAudienceLayoutAWE);
    }
}
