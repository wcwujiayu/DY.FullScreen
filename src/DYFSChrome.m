//
//  DYFSChrome.m
//  DY.FullScreen
//
//  Chrome cleanup: hide the bottom tab bar background and clear the dark bars
//  that Douyin leaves inside the progress containers in full-screen mode.
//
//  信息流直播卡片的上移逻辑已整体移除：本文件只负责底栏与进度条背景的透明，
//  不再挂任何直播间 / audienceVC 相关钩子。
//

#import "DYFSChrome.h"
#import "DYFSCommon.h"
#import <objc/message.h>

static IMP DYFSOriginalTabBarLayout = NULL;
static IMP DYFSOriginalTabBarHidden = NULL;
static IMP DYFSOriginalTabBarDidMove = NULL;
static IMP DYFSOriginalTabBarDidAddSubview = NULL;
static IMP DYFSOriginalInteractionProgressLayout = NULL;
static IMP DYFSOriginalPlayerProgressLayout = NULL;

// Collapses repeated transparency requests within one main-queue turn.
static BOOL DYFSTabBarTransparencyScheduled = NO;

// 兜底：拦截底栏 -setBackgroundColor:，启用时强制清成透明，避免抖音在布局后
// 又把背景刷成深色（与 DYYY 的 skinContainerView 隐藏互不冲突）。
static IMP DYFSOriginalTabBarSetBackgroundColor = NULL;
static BOOL DYFSInstalledTabBarSetBackgroundColor = NO;

// 复刻 DYYY（DYYY.xm 15100+）的判定：递归遍历底栏全部子视图，跳过按钮，
// 把「_UIBarBackground / 纯 UIView 且高度匹配底栏」的背景与细分割线一并隐藏。
// 递归是因为真正的黑底 AWETabBarSkinView 常藏在 skinContainerView 内部，
// 只遍历一层 subviews 会漏掉它。
static void DYFSApplyTabBarTransparencyRecursively(UIView *container, UIView *tabBar, BOOL enabled,
                                                   Class generalButtonClass, Class plusButtonClass,
                                                   Class plusContainerClass, Class plusInnerClass,
                                                   Class barBackgroundClass, Class tabBarButtonClass,
                                                   NSUInteger depth) {
    if (!container || depth > 12) return;

    CGFloat barHeight = CGRectGetHeight(tabBar.bounds);
    if (barHeight <= 0.0 || !isfinite(barHeight)) {
        barHeight = 49.0 + MAX(0.0, tabBar.window.safeAreaInsets.bottom);
    }

    for (UIView *subview in [container.subviews copy]) {
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

        DYFSBackupAppearance(subview);
        if (enabled && (namedBackground || plainFullBarBackground)) {
            subview.hidden = YES;
            subview.backgroundColor = UIColor.clearColor;
            if (subview.layer) subview.layer.backgroundColor = UIColor.clearColor.CGColor;
            subview.opaque = NO;
        } else if (!enabled && (namedBackground || plainFullBarBackground)) {
            subview.hidden = NO;
        }

        if (CGRectGetHeight(subview.bounds) > 0 && CGRectGetHeight(subview.bounds) < 1.0 &&
            CGRectGetWidth(subview.bounds) > 300.0) {
            DYFSBackupAppearance(subview);
            subview.hidden = enabled;
        }

        DYFSApplyTabBarTransparencyRecursively(subview, tabBar, enabled,
                                               generalButtonClass, plusButtonClass, plusContainerClass,
                                               plusInnerClass, barBackgroundClass, tabBarButtonClass,
                                               depth + 1);
    }
}

// 判断当前选中的是不是最左边那个 tab（首页）。
static void DYFSUpdateHomeTabState(UIView *tabBar) {
    UIControl *selected = nil, *leftmost = nil;
    CGFloat selectedX = CGFLOAT_MAX, leftmostX = CGFLOAT_MAX;
    for (UIView *subview in tabBar.subviews) {
        if (![subview isKindOfClass:UIControl.class]) continue;
        UIControl *control = (UIControl *)subview;
        CGFloat x = CGRectGetMinX(control.frame);
        if (x < leftmostX) { leftmostX = x; leftmost = control; }
        if (control.selected && x < selectedX) { selectedX = x; selected = control; }
    }
    DYFSLastHomeTabSelected = (selected != nil && selected == leftmost);
}

static void DYFSApplyTabBarTransparency(UIView *tabBar) {
    if (!tabBar) return;

    static BOOL lastEnabled = YES;
    BOOL enabled = DYFSIsEnabled();
    // 关掉开关：把改过的视图一并还原（与去灰底共用同一份备份表）。
    if (!enabled) {
        if (lastEnabled) {
            DYFSRestoreAllAppearance();
            lastEnabled = NO;
        }
    } else {
        lastEnabled = YES;
        DYFSUpdateHomeTabState(tabBar);
    }

    Class generalButtonClass = NSClassFromString(kDYFSClassTabBarGeneralButton);
    Class plusButtonClass = NSClassFromString(kDYFSClassTabBarGeneralPlusButton);
    Class plusContainerClass = NSClassFromString(kDYFSClassTabBarPlusButton);
    Class plusInnerClass = NSClassFromString(@"AWENormalModeTabBarGeneralPlusInnerButton");
    Class barBackgroundClass = NSClassFromString(kDYFSClassBarBackground);   // _UIBarBackground
    Class tabBarButtonClass = NSClassFromString(@"UITabBarButton");

    // 隐藏整块皮肤容器（DYYY 同款）。
    id skinContainer = DYFSSafeValueForKey(tabBar, @"skinContainerView");
    if ([skinContainer isKindOfClass:UIView.class]) {
        ((UIView *)skinContainer).hidden = enabled;
    }

    // 部分版本把底色直接刷在底栏自身或 layer 上，一并清掉。
    DYFSBackupAppearance(tabBar);
    if (enabled) {
        tabBar.backgroundColor = UIColor.clearColor;
        if (tabBar.layer) tabBar.layer.backgroundColor = UIColor.clearColor.CGColor;
        tabBar.opaque = NO;
    }

    DYFSApplyTabBarTransparencyRecursively(tabBar, tabBar, enabled,
                                           generalButtonClass, plusButtonClass, plusContainerClass,
                                           plusInnerClass, barBackgroundClass, tabBarButtonClass, 0);

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
}
