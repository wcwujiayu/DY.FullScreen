//
// DYLiveFeedFullscreen.m
// DY.FullScreen
//
// Scoped port of DYYY's feed interaction-container layout for live cards.
// This module does NOT resize the video player/contentView or hook UIView
// setFrame:. It only adjusts AWEPlayInteractionViewController's view height
// when the live-feed context is positively identified.
//

#import "DYLiveFeedFullscreen.h"
#import <objc/runtime.h>
#import <math.h>
#import <stdlib.h>

static NSString * const DYLiveFeedCellClassName = @"IESLiveInnerFeedLiveRoomCell";
static NSString * const DYLiveFeedInteractionClassName = @"AWEPlayInteractionViewController";
static NSString * const DYLiveFeedTabBarClassName = @"AWENormalModeTabBar";

static IMP DYLiveFeedOriginalInteractionLayout = NULL;
static BOOL DYLiveFeedInteractionHookInstalled = NO;
static BOOL DYLiveFeedInstallScheduled = NO;
static NSUInteger DYLiveFeedInstallAttempts = 0;

static void DYLiveFeedInstallHooks(void);
static void DYLiveFeedScheduleInstall(void);
static void DYLiveFeedInteractionLayout(id self, SEL command);
static void DYLiveFeedApplyInteractionLayout(UIViewController *controller);

static void DYLiveFeedLog(NSString *message) {
    NSLog(@"[DY.FullScreen][LiveFeedInteraction] %@", message);
}

static BOOL DYLiveFeedClassMatches(NSString *name, NSString *target) {
    return name.length > 0 && target.length > 0 &&
           ([name isEqualToString:target] || [name hasSuffix:target]);
}

static id DYLiveFeedSafeValue(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static UIView *DYLiveFeedContainingCell(UIView *view) {
    for (UIView *cursor = view; cursor; cursor = cursor.superview) {
        if (DYLiveFeedClassMatches(NSStringFromClass(cursor.class), DYLiveFeedCellClassName)) {
            return cursor;
        }
    }
    return nil;
}

static BOOL DYLiveFeedModelHasLiveSignal(id model) {
    if (!model) return NO;

    id liveValue = DYLiveFeedSafeValue(model, @"isLive");
    if ([liveValue respondsToSelector:@selector(boolValue)] && [liveValue boolValue]) return YES;

    id roomValue = DYLiveFeedSafeValue(model, @"cellRoom");
    if (roomValue && roomValue != NSNull.null) return YES;

    id tagValue = DYLiveFeedSafeValue(model, @"videoFeedTag");
    return [tagValue isKindOfClass:NSString.class] && [tagValue isEqualToString:@"直播中"];
}

static BOOL DYLiveFeedControllerHasLiveSignal(UIViewController *controller) {
    if (!controller) return NO;

    // DYYY uses isLive, cellRoom, and videoFeedTag == "直播中" as live signals.
    NSArray<NSString *> *keys = @[@"model", @"awemeModel", @"itemModel", @"aweme", @"item"];
    for (NSString *key in keys) {
        if (DYLiveFeedModelHasLiveSignal(DYLiveFeedSafeValue(controller, key))) return YES;
    }
    return NO;
}

static BOOL DYLiveFeedIsActualLiveRoom(UIView *view, UIViewController *controller) {
    NSArray<NSString *> *roomMarkers = @[
        @"IESLiveAudienceViewController",
        @"AWELiveAudienceViewController",
        @"LiveRoomViewController",
        @"LiveRoomContainerViewController"
    ];

    for (UIView *cursor = view; cursor; cursor = cursor.superview) {
        NSString *name = NSStringFromClass(cursor.class);
        for (NSString *marker in roomMarkers) {
            if ([name containsString:marker]) return YES;
        }
    }

    UIResponder *responder = view;
    for (NSUInteger depth = 0; responder && depth < 64; depth++, responder = responder.nextResponder) {
        NSString *name = NSStringFromClass(responder.class);
        for (NSString *marker in roomMarkers) {
            if ([name containsString:marker]) return YES;
        }
    }

    UIViewController *cursor = controller;
    for (NSUInteger depth = 0; cursor && depth < 24; depth++, cursor = cursor.parentViewController) {
        NSString *name = NSStringFromClass(cursor.class);
        for (NSString *marker in roomMarkers) {
            if ([name containsString:marker]) return YES;
        }
    }
    return NO;
}

static BOOL DYLiveFeedIsLiveCardInteraction(UIViewController *controller) {
    if (!controller || ![controller isKindOfClass:UIViewController.class]) return NO;
    UIView *view = controller.view;

    // Prefer structural identification; model flags cover builds where the
    // interaction controller sits beside rather than inside the live feed cell.
    if (DYLiveFeedContainingCell(view)) return YES;
    return DYLiveFeedControllerHasLiveSignal(controller);
}

static CGFloat DYLiveFeedFindTabBarHeight(UIView *root, NSUInteger depth) {
    if (!root || depth > 24) return 0.0;
    if (DYLiveFeedClassMatches(NSStringFromClass(root.class), DYLiveFeedTabBarClassName)) {
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
            if (candidate.isKeyWindow) { window = candidate; break; }
        }
    }

    CGFloat measured = DYLiveFeedFindTabBarHeight(window, 0);
    if (measured >= 30.0 && window &&
        measured < CGRectGetHeight(window.bounds)) {
        return measured;
    }
    return 49.0 + MAX(0.0, window ? window.safeAreaInsets.bottom : 0.0);
}

static BOOL DYLiveFeedReferNeedsFullHeight(NSString *referString) {
    // Port of DYYY's AWEPlayInteractionViewController.viewDidLayoutSubviews.
    // DYYY treats a nil referString as full-height, and these routes explicitly
    // require full-height; normal feed routes remain above the bottom tab bar.
    if (!referString) return YES;
    NSArray<NSString *> *fullHeightReferStrings = @[
        @"general_search",
        @"search_result",
        @"search_ecommerce",
        @"close_friends_moment",
        @"offline_mode",
        @"challenge",
        @"general_search_scan"
    ];
    return [fullHeightReferStrings containsObject:referString];
}

static void DYLiveFeedApplyInteractionLayout(UIViewController *controller) {
    if (!controller || ![NSThread isMainThread]) return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:@"com.dy.fullscreen.enabled"] != nil &&
        ![defaults boolForKey:@"com.dy.fullscreen.enabled"]) {
        return;
    }

    UIView *view = controller.view;
    if (!view || !view.window || !view.superview) return;
    if (DYLiveFeedIsActualLiveRoom(view, controller)) return;
    if (!DYLiveFeedIsLiveCardInteraction(controller)) return;

    UIView *parent = view.superview;
    CGFloat parentHeight = CGRectGetHeight(parent.bounds);
    CGFloat tabBarHeight = DYLiveFeedTabBarHeightForView(view);
    if (!isfinite(parentHeight) || parentHeight <= 1.0 ||
        !isfinite(tabBarHeight) || tabBarHeight < 30.0) {
        return;
    }

    NSString *referString = DYLiveFeedSafeValue(controller, @"referString");
    BOOL useFullHeight = DYLiveFeedReferNeedsFullHeight(referString);

    // Same special handling as DYYY: live items in the chat route keep the
    // regular interaction area rather than being extended behind the tab bar.
    if (!useFullHeight && [referString isEqualToString:@"chat"] &&
        DYLiveFeedControllerHasLiveSignal(controller)) {
        useFullHeight = NO;
    }

    CGFloat targetHeight = useFullHeight ? parentHeight : parentHeight - tabBarHeight;
    if (!isfinite(targetHeight) || targetHeight <= 1.0) return;

    CGRect frame = view.frame;
    CGFloat oldHeight = CGRectGetHeight(frame);
    if (fabs(oldHeight - targetHeight) <= 0.5) return;

    // Only the interaction container changes. Do not resize the live video,
    // player contentView, caption subviews, or individual buttons.
    frame.size.height = targetHeight;
    view.frame = frame;

    DYLiveFeedLog([NSString stringWithFormat:
        @"interaction container %@ height %.2f -> %.2f (parent %.2f, tab bar %.2f, refer %@)",
        NSStringFromClass(controller.class), oldHeight, targetHeight, parentHeight,
        tabBarHeight, referString ?: @"<nil>"]);
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

static void DYLiveFeedInteractionLayout(id self, SEL command) {
    if (DYLiveFeedOriginalInteractionLayout) {
        ((void (*)(id, SEL))DYLiveFeedOriginalInteractionLayout)(self, command);
    }
    if ([self isKindOfClass:UIViewController.class]) {
        DYLiveFeedApplyInteractionLayout((UIViewController *)self);
    }
}

static void DYLiveFeedInstallHooks(void) {
    DYLiveFeedInstallAttempts++;
    if (DYLiveFeedInteractionHookInstalled) return;

    Class cls = NSClassFromString(DYLiveFeedInteractionClassName);
    DYLiveFeedInteractionHookInstalled = DYLiveFeedInstallInstanceHook(
        cls, @selector(viewDidLayoutSubviews),
        (IMP)DYLiveFeedInteractionLayout, &DYLiveFeedOriginalInteractionLayout);

    if (DYLiveFeedInteractionHookInstalled) {
        DYLiveFeedLog(@"hooked AWEPlayInteractionViewController -viewDidLayoutSubviews (interaction layout only)");
        return;
    }
    if (DYLiveFeedInstallAttempts < 60) {
        DYLiveFeedScheduleInstall();
    } else {
        DYLiveFeedLog(@"AWEPlayInteractionViewController hook unavailable after retrying");
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
    // Wait until the app has registered the UIKit/aweme classes before hooking.
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
    if (!view || ![NSThread isMainThread]) return;
    UIViewController *controller = nil;
    UIResponder *responder = view;
    for (NSUInteger depth = 0; responder && depth < 64; depth++, responder = responder.nextResponder) {
        if ([responder isKindOfClass:UIViewController.class]) {
            controller = (UIViewController *)responder;
            break;
        }
    }
    if (controller) DYLiveFeedApplyInteractionLayout(controller);
}

@end
