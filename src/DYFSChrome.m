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

static IMP DYFSOriginalTabBarLayout = NULL;
static IMP DYFSOriginalTabBarHidden = NULL;
static IMP DYFSOriginalTabBarDidMove = NULL;
static IMP DYFSOriginalTabBarDidAddSubview = NULL;
static IMP DYFSOriginalInteractionProgressLayout = NULL;
static IMP DYFSOriginalPlayerProgressLayout = NULL;

// Collapses repeated transparency requests within one main-queue turn.
static BOOL DYFSTabBarTransparencyScheduled = NO;

static BOOL DYFSIsTabBarControl(UIView *view, Class generalButtonClass, Class plusButtonClass) {
    if (!view) return NO;
    NSString *name = NSStringFromClass(view.class);
    return [view isKindOfClass:UIControl.class] ||
           (generalButtonClass && [view isKindOfClass:generalButtonClass]) ||
           (plusButtonClass && [view isKindOfClass:plusButtonClass]) ||
           [name containsString:@"AWENormalModeTabBarGeneralButton"] ||
           [name containsString:@"AWENormalModeTabBarGeneralPlusButton"] ||
           [name containsString:@"AWENormalModeTabBarPlusButton"];
}

static BOOL DYFSContainsTabBarControl(UIView *view, Class generalButtonClass, Class plusButtonClass, NSUInteger depth) {
    if (!view || depth > 8) return NO;
    if (DYFSIsTabBarControl(view, generalButtonClass, plusButtonClass)) return YES;
    for (UIView *subview in view.subviews) {
        if (DYFSContainsTabBarControl(subview, generalButtonClass, plusButtonClass, depth + 1)) return YES;
    }
    return NO;
}

static void DYFSApplyTabBarBackgroundsRecursively(UIView *container, UIView *tabBar,
                                                  BOOL enabled, Class generalButtonClass,
                                                  Class plusButtonClass, Class barBackgroundClass,
                                                  NSUInteger depth) {
    if (!container || depth > 10) return;
    CGFloat barWidth = CGRectGetWidth(tabBar.bounds);
    CGFloat barHeight = CGRectGetHeight(tabBar.bounds);

    for (UIView *subview in [container.subviews copy]) {
        if (DYFSIsTabBarControl(subview, generalButtonClass, plusButtonClass)) continue;

        NSString *name = NSStringFromClass(subview.class);
        CGRect rect = [subview convertRect:subview.bounds toView:tabBar];
        CGFloat width = CGRectGetWidth(rect);
        CGFloat height = CGRectGetHeight(rect);
        CGFloat minX = CGRectGetMinX(rect);
        CGFloat minY = CGRectGetMinY(rect);

        BOOL namedBackground = (barBackgroundClass && [subview isKindOfClass:barBackgroundClass]) ||
            [name containsString:@"Background"] || [name containsString:@"Backdrop"] ||
            [name containsString:@"Blur"] || [subview isKindOfClass:UIVisualEffectView.class];
        BOOL fillsBar = barWidth > 0.0 && barHeight > 0.0 &&
            width >= barWidth * 0.88 && minX <= barWidth * 0.06 &&
            height >= MAX(24.0, barHeight * 0.40) && height <= barHeight * 1.35 &&
            minY <= barHeight * 0.38 && CGRectGetMaxY(rect) >= barHeight * 0.50;
        BOOL plainFullBarBackground = [subview isMemberOfClass:UIView.class] &&
            fillsBar && !DYFSContainsTabBarControl(subview, generalButtonClass, plusButtonClass, 0);
        BOOL divider = height > 0.0 && height < 1.2 && width >= barWidth * 0.75;

        if (namedBackground || plainFullBarBackground || divider) {
            subview.hidden = enabled;
            if (namedBackground || plainFullBarBackground) subview.backgroundColor = UIColor.clearColor;
        }
        if (!subview.hidden) {
            DYFSApplyTabBarBackgroundsRecursively(subview, tabBar, enabled, generalButtonClass,
                                                   plusButtonClass, barBackgroundClass, depth + 1);
        }
    }
}

static void DYFSApplyTabBarTransparency(UIView *tabBar) {
    if (!tabBar) return;

    BOOL enabled = DYFSIsEnabled();
    Class generalButtonClass = NSClassFromString(@"AWENormalModeTabBarGeneralButton");
    Class plusButtonClass = NSClassFromString(@"AWENormalModeTabBarGeneralPlusButton");
    Class barBackgroundClass = NSClassFromString(@"_UIBarBackground");

    BOOL isHomeSelected = NO;
    for (UIView *subview in [tabBar.subviews copy]) {
        if (!generalButtonClass || ![subview isKindOfClass:generalButtonClass]) continue;
        NSString *label = subview.accessibilityLabel ?: @"";
        id status = DYFSSafeValueForKey(subview, @"status");
        BOOL selected = [status respondsToSelector:@selector(integerValue)] && [status integerValue] == 2;
        if (selected && [label isEqualToString:@"首页"]) {
            isHomeSelected = YES;
        }
    }

    // Hide only the tab bar's background layers on every tab. Buttons remain
    // visible/tappable; the selected tab does not change transparency behavior.
    id skinContainer = DYFSSafeValueForKey(tabBar, @"skinContainerView");
    if ([skinContainer isKindOfClass:UIView.class]) {
        ((UIView *)skinContainer).hidden = enabled;
    }

    BOOL shouldHideBackgrounds = enabled;
    CGFloat barHeight = CGRectGetHeight(tabBar.bounds);
    if (barHeight <= 0.0 || !isfinite(barHeight)) {
        barHeight = 49.0 + MAX(0.0, tabBar.window.safeAreaInsets.bottom);
    }

    DYFSApplyTabBarBackgroundsRecursively(tabBar, tabBar, shouldHideBackgrounds,
                                          generalButtonClass, plusButtonClass,
                                          barBackgroundClass, 0);

    DYFSLastHomeTabSelected = isHomeSelected;
    DYFSLastTabBackgroundHidden = shouldHideBackgrounds;
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


void DYFSChromeInstallHooks(void) {
    Class cls = NSClassFromString(@"AWEPlayInteractionProgressContainerView");
    if (cls && !DYFSInstalledInteractionProgress) {
        DYFSInstalledInteractionProgress = DYFSInstallHook(cls, @selector(layoutSubviews),
                    (IMP)DYFSInteractionProgressLayout, &DYFSOriginalInteractionProgressLayout);
    }

    cls = NSClassFromString(@"AWEDPlayerProgressContainerView");
    if (cls && !DYFSInstalledPlayerProgress) {
        DYFSInstalledPlayerProgress = DYFSInstallHook(cls, @selector(layoutSubviews),
                    (IMP)DYFSPlayerProgressLayout, &DYFSOriginalPlayerProgressLayout);
    }

    cls = NSClassFromString(@"AWENormalModeTabBar");
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
}
