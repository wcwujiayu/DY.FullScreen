//
// DYLiveFeedFullscreen.m
// DY.FullScreen
//
// Narrowly ports DYYY's feed-player content-height correction to live-feed
// cards only. Existing DY.FullScreen video/profile/layout hooks are untouched.
//

#import "DYLiveFeedFullscreen.h"
#import <objc/runtime.h>
#import <math.h>
#import <stdlib.h>

static NSString * const DYLiveFeedCellClassName = @"IESLiveInnerFeedLiveRoomCell";
static NSString * const DYLiveFeedPlayerClassA = @"AWEDPlayerFeedPlayerViewController";
static NSString * const DYLiveFeedPlayerClassB = @"AWEDPlayerViewController_Merge";
static NSString * const DYLiveFeedTabBarClassName = @"AWENormalModeTabBar";

static IMP DYLiveFeedOriginalCellLayout = NULL;
static IMP DYLiveFeedOriginalPlayerLayoutA = NULL;
static IMP DYLiveFeedOriginalPlayerLayoutB = NULL;

static BOOL DYLiveFeedCellHookInstalled = NO;
static BOOL DYLiveFeedPlayerHookAInstalled = NO;
static BOOL DYLiveFeedPlayerHookBInstalled = NO;
static BOOL DYLiveFeedInstallScheduled = NO;
static NSUInteger DYLiveFeedInstallAttempts = 0;

static void DYLiveFeedInstallHooks(void);
static void DYLiveFeedScheduleInstall(void);
static void DYLiveFeedCellLayoutSubviews(id self, SEL command);
static void DYLiveFeedPlayerLayoutA(id self, SEL command);
static void DYLiveFeedPlayerLayoutB(id self, SEL command);

static void DYLiveFeedLog(NSString *message) {
    NSLog(@"[DY.FullScreen][LiveFeed] %@", message);
}

static BOOL DYLiveFeedClassNameMatches(NSString *className, NSString *targetName) {
    return className.length > 0 && targetName.length > 0 &&
           ([className isEqualToString:targetName] || [className hasSuffix:targetName]);
}

static UIView *DYLiveFeedContainingCell(UIView *view) {
    for (UIView *cursor = view; cursor; cursor = cursor.superview) {
        NSString *name = NSStringFromClass(cursor.class);
        if (DYLiveFeedClassNameMatches(name, DYLiveFeedCellClassName)) {
            return cursor;
        }
    }
    return nil;
}

static BOOL DYLiveFeedIsSupportedPlayerController(id object) {
    if (![object isKindOfClass:UIViewController.class]) return NO;
    NSString *name = NSStringFromClass([object class]);
    return DYLiveFeedClassNameMatches(name, DYLiveFeedPlayerClassA) ||
           DYLiveFeedClassNameMatches(name, DYLiveFeedPlayerClassB);
}

static id DYLiveFeedSafeValue(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static CGFloat DYLiveFeedFindTabBarHeight(UIView *root, NSUInteger depth) {
    if (!root || depth > 18) return 0.0;
    if (DYLiveFeedClassNameMatches(NSStringFromClass(root.class), DYLiveFeedTabBarClassName)) {
        CGFloat height = CGRectGetHeight(root.bounds);
        if (isfinite(height) && height >= 30.0) return height;
    }
    for (UIView *subview in [root.subviews copy]) {
        CGFloat height = DYLiveFeedFindTabBarHeight(subview, depth + 1);
        if (height >= 30.0) return height;
    }
    return 0.0;
}

static CGFloat DYLiveFeedTabBarHeightForView(UIView *view) {
    UIWindow *window = view.window;
    if (!window) {
        for (UIWindow *candidate in UIApplication.sharedApplication.windows.reverseObjectEnumerator) {
            if (candidate.isKeyWindow) {
                window = candidate;
                break;
            }
        }
    }

    CGFloat measured = DYLiveFeedFindTabBarHeight(window, 0);
    if (measured >= 30.0) return measured;

    // Same fallback used by DYYY when the native tab-bar view is not yet laid out.
    CGFloat safeBottom = window ? window.safeAreaInsets.bottom : 0.0;
    return 49.0 + MAX(0.0, safeBottom);
}

static void DYLiveFeedApplyDYYYContentHeightRule(id playerController) {
    if (!DYLiveFeedIsSupportedPlayerController(playerController)) return;

    UIViewController *controller = (UIViewController *)playerController;
    UIView *controllerView = controller.view;

    // The feed-cell ancestor is the positive scope. A full live-room controller
    // entered from a card is no longer under this cell and is therefore untouched.
    UIView *cell = DYLiveFeedContainingCell(controllerView);
    if (!cell || !controllerView.window) return;

    id value = DYLiveFeedSafeValue(playerController, @"contentView");
    if (![value isKindOfClass:UIView.class]) return;
    UIView *contentView = (UIView *)value;
    UIView *parent = contentView.superview;
    if (!parent || !contentView.window || !parent.window ||
        !DYLiveFeedContainingCell(contentView)) {
        return;
    }

    CGFloat parentHeight = CGRectGetHeight(parent.bounds);
    CGFloat currentHeight = CGRectGetHeight(contentView.frame);
    CGFloat tabBarHeight = DYLiveFeedTabBarHeightForView(contentView);
    if (!isfinite(parentHeight) || !isfinite(currentHeight) ||
        parentHeight <= 1.0 || currentHeight <= 1.0 ||
        !isfinite(tabBarHeight) || tabBarHeight < 30.0) {
        return;
    }

    // Mirrors DYYY's AWEDPlayerFeedPlayerViewController /
    // AWEDPlayerViewController_Merge contentView rule: only alter the player
    // surface when the height deficit matches one or two native tab-bar heights.
    CGFloat deficit = parentHeight - currentHeight;
    CGFloat tolerance = MAX(1.0, tabBarHeight * 0.03);
    CGFloat targetHeight = currentHeight;

    if (fabs(deficit - tabBarHeight) <= tolerance) {
        targetHeight = parentHeight;
    } else if (fabs(deficit - (tabBarHeight * 2.0)) <= tolerance) {
        targetHeight = parentHeight - tabBarHeight;
    } else {
        return;
    }

    if (!isfinite(targetHeight) || targetHeight <= 1.0 ||
        fabs(currentHeight - targetHeight) <= 0.5) {
        return;
    }

    CGRect frame = contentView.frame;
    frame.size.height = targetHeight;
    contentView.frame = frame;
    [contentView setNeedsLayout];

    DYLiveFeedLog([NSString stringWithFormat:
        @"%@ contentView height %.2f -> %.2f (parent %.2f, tab bar %.2f)",
        NSStringFromClass([playerController class]), currentHeight,
        targetHeight, parentHeight, tabBarHeight]);
}

static void DYLiveFeedScanViewTree(UIView *root, NSUInteger depth) {
    if (!root || depth > 36) return;

    // A controller is normally the next responder of its root view. Avoid
    // walking responder chains for every leaf during a scrolling layout pass.
    UIResponder *next = root.nextResponder;
    if (DYLiveFeedIsSupportedPlayerController(next)) {
        DYLiveFeedApplyDYYYContentHeightRule(next);
    }

    for (UIView *subview in [root.subviews copy]) {
        DYLiveFeedScanViewTree(subview, depth + 1);
    }
}

static Method DYLiveFeedOwnInstanceMethod(Class cls, SEL selector) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    Method found = NULL;
    for (unsigned int index = 0; index < count; index++) {
        if (sel_isEqual(method_getName(methods[index]), selector)) {
            found = methods[index];
            break;
        }
    }
    free(methods);
    return found;
}

static BOOL DYLiveFeedInstallInstanceHook(Class cls, SEL selector,
                                           IMP replacement, IMP *originalOut) {
    if (!cls || !selector || !replacement || !originalOut) return NO;

    Method ownMethod = DYLiveFeedOwnInstanceMethod(cls, selector);
    if (ownMethod) {
        IMP current = method_getImplementation(ownMethod);
        if (current == replacement) return YES;
        *originalOut = method_setImplementation(ownMethod, replacement);
        return *originalOut != NULL;
    }

    Method inheritedMethod = class_getInstanceMethod(cls, selector);
    if (!inheritedMethod) return NO;

    const char *types = method_getTypeEncoding(inheritedMethod);
    IMP inheritedImplementation = method_getImplementation(inheritedMethod);
    if (class_addMethod(cls, selector, replacement, types)) {
        *originalOut = inheritedImplementation;
        return YES;
    }

    ownMethod = DYLiveFeedOwnInstanceMethod(cls, selector);
    if (!ownMethod) return NO;
    IMP current = method_getImplementation(ownMethod);
    if (current == replacement) return YES;
    *originalOut = method_setImplementation(ownMethod, replacement);
    return *originalOut != NULL;
}

static void DYLiveFeedCellLayoutSubviews(id self, SEL command) {
    if (DYLiveFeedOriginalCellLayout) {
        ((void (*)(id, SEL))DYLiveFeedOriginalCellLayout)(self, command);
    }
    if ([self isKindOfClass:UIView.class]) {
        [[DYLiveFeedFullscreen sharedInstance] processLiveFeedView:(UIView *)self];
    }
}

static void DYLiveFeedPlayerLayoutA(id self, SEL command) {
    if (DYLiveFeedOriginalPlayerLayoutA) {
        ((void (*)(id, SEL))DYLiveFeedOriginalPlayerLayoutA)(self, command);
    }
    if ([self isKindOfClass:UIViewController.class]) {
        UIView *root = ((UIViewController *)self).view;
        DYLiveFeedApplyDYYYContentHeightRule(self);
        [[DYLiveFeedFullscreen sharedInstance] processLiveFeedView:root];
    }
}

static void DYLiveFeedPlayerLayoutB(id self, SEL command) {
    if (DYLiveFeedOriginalPlayerLayoutB) {
        ((void (*)(id, SEL))DYLiveFeedOriginalPlayerLayoutB)(self, command);
    }
    if ([self isKindOfClass:UIViewController.class]) {
        UIView *root = ((UIViewController *)self).view;
        DYLiveFeedApplyDYYYContentHeightRule(self);
        [[DYLiveFeedFullscreen sharedInstance] processLiveFeedView:root];
    }
}

static void DYLiveFeedInstallHooks(void) {
    DYLiveFeedInstallAttempts++;
    BOOL allInstalled = YES;

    if (!DYLiveFeedCellHookInstalled) {
        Class cls = NSClassFromString(DYLiveFeedCellClassName);
        DYLiveFeedCellHookInstalled = DYLiveFeedInstallInstanceHook(
            cls, @selector(layoutSubviews), (IMP)DYLiveFeedCellLayoutSubviews,
            &DYLiveFeedOriginalCellLayout);
        if (DYLiveFeedCellHookInstalled) DYLiveFeedLog(@"hooked IESLiveInnerFeedLiveRoomCell -layoutSubviews");
        allInstalled &= DYLiveFeedCellHookInstalled;
    }

    if (!DYLiveFeedPlayerHookAInstalled) {
        Class cls = NSClassFromString(DYLiveFeedPlayerClassA);
        DYLiveFeedPlayerHookAInstalled = DYLiveFeedInstallInstanceHook(
            cls, @selector(viewDidLayoutSubviews), (IMP)DYLiveFeedPlayerLayoutA,
            &DYLiveFeedOriginalPlayerLayoutA);
        if (DYLiveFeedPlayerHookAInstalled) DYLiveFeedLog(@"hooked AWEDPlayerFeedPlayerViewController -viewDidLayoutSubviews");
        allInstalled &= DYLiveFeedPlayerHookAInstalled;
    }

    if (!DYLiveFeedPlayerHookBInstalled) {
        Class cls = NSClassFromString(DYLiveFeedPlayerClassB);
        DYLiveFeedPlayerHookBInstalled = DYLiveFeedInstallInstanceHook(
            cls, @selector(viewDidLayoutSubviews), (IMP)DYLiveFeedPlayerLayoutB,
            &DYLiveFeedOriginalPlayerLayoutB);
        if (DYLiveFeedPlayerHookBInstalled) DYLiveFeedLog(@"hooked AWEDPlayerViewController_Merge -viewDidLayoutSubviews");
        allInstalled &= DYLiveFeedPlayerHookBInstalled;
    }

    if (!allInstalled && DYLiveFeedInstallAttempts < 60) {
        DYLiveFeedScheduleInstall();
    } else if (!allInstalled) {
        DYLiveFeedLog(@"some live-feed hooks were unavailable after retrying; no global player hook was added");
    }
}

static void DYLiveFeedScheduleInstall(void) {
    if (DYLiveFeedInstallScheduled) return;
    DYLiveFeedInstallScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        DYLiveFeedInstallScheduled = NO;
        DYLiveFeedInstallHooks();
    });
}

@implementation DYLiveFeedFullscreen

+ (void)load {
    // Defer until the host app has had an opportunity to register its UIKit classes.
    DYLiveFeedScheduleInstall();
}

+ (instancetype)sharedInstance {
    static DYLiveFeedFullscreen *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[DYLiveFeedFullscreen alloc] init];
    });
    return manager;
}

- (BOOL)isLiveFeedView:(UIView *)view {
    return DYLiveFeedContainingCell(view) != nil;
}

- (void)processLiveFeedView:(UIView *)view {
    if (!view) return;

    if (![NSThread isMainThread]) {
        __weak UIView *weakView = view;
        dispatch_async(dispatch_get_main_queue(), ^{
            UIView *strongView = weakView;
            if (strongView) [self processLiveFeedView:strongView];
        });
        return;
    }

    UIView *cell = DYLiveFeedContainingCell(view);
    if (!cell) return;

    // Scan only inside the matched feed cell. This is intentionally not a
    // process-wide UIView/frame/bounds hook and cannot resize ordinary posts.
    DYLiveFeedScanViewTree(cell, 0);
}

@end
