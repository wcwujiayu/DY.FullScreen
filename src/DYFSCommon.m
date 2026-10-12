//
//  DYFSCommon.m
//  DY.FullScreen
//
//  Shared constants, runtime helpers and cross-module state.
//

#import "DYFSCommon.h"
#import <objc/message.h>

// 抖音私有类名集中清单（改版时只需改这里）
NSString * const kDYFSClassFeedTableView = @"AWEFeedTableView";
NSString * const kDYFSClassStoryContainer = @"AWEStoryContainerCollectionView";
NSString * const kDYFSClassPlayInteraction = @"AWEPlayInteractionViewController";
NSString * const kDYFSClassPlayVideoA = @"AWEAwemePlayVideoViewController";
NSString * const kDYFSClassPlayVideoB = @"AWEDPlayerFeedPlayerViewController";
NSString * const kDYFSClassPlayVideoC = @"AWEDPlayerViewController_Merge";
NSString * const kDYFSClassSidebarIcon = @"AWELeftSideBarTopIconHorizontalView";
NSString * const kDYFSClassSidebarRight = @"AWELeftSideBarTopRightLayoutView";
NSString * const kDYFSClassInteractionProgress = @"AWEPlayInteractionProgressContainerView";
NSString * const kDYFSClassPlayerProgress = @"AWEDPlayerProgressContainerView";
NSString * const kDYFSClassTabBar = @"AWENormalModeTabBar";
NSString * const kDYFSClassTabBarGeneralButton = @"AWENormalModeTabBarGeneralButton";
NSString * const kDYFSClassTabBarGeneralPlusButton = @"AWENormalModeTabBarGeneralPlusButton";
NSString * const kDYFSClassTabBarPlusButton = @"AWENormalModeTabBarPlusButton";
NSString * const kDYFSClassSettings = @"AWESettingsTableViewController";
NSString * const kDYFSClassSettingItemModel = @"AWESettingItemModel";
NSString * const kDYFSClassSettingSectionModel = @"AWESettingSectionModel";
NSString * const kDYFSClassLiveFeedCell = @"IESLiveInnerFeedLiveRoomCell";
NSString * const kDYFSClassBarBackground = @"_UIBarBackground";

const NSUInteger kDYFSMaxInstallAttempts = 60;
const NSTimeInterval kDYFSInstallRetryInterval = 1.0;

NSString * const DYFSBundleID = @"com.ss.iphone.ugc.Aweme";
NSString * const DYFSTestedVersion = @"40.7.0";
NSString * const DYFSEnabledKey = @"com.dy.fullscreen.enabled";
NSString * const DYFSSettingsTitle = @"启用全屏";

BOOL DYFSInstalledFeed = NO;
BOOL DYFSInstalledStory = NO;
BOOL DYFSInstalledInteractionController = NO;
BOOL DYFSInstalledSidebarIcon = NO;
BOOL DYFSInstalledSidebarRight = NO;
BOOL DYFSInstalledTabBarLayout = NO;
BOOL DYFSInstalledTabBarHidden = NO;
BOOL DYFSInstalledTabBarDidMove = NO;
BOOL DYFSInstalledTabBarDidAddSubview = NO;
BOOL DYFSInstalledInteractionProgress = NO;
BOOL DYFSInstalledSetFrameHook = NO;
BOOL DYFSInstalledPlayerProgress = NO;
BOOL DYFSInstalledNativeSettingsSwitch = NO;
BOOL DYFSNativeSettingsRowAdded = NO;
BOOL DYFSStartupRelayoutScheduled = NO;
BOOL DYFSSchedulePending = NO;
NSUInteger DYFSInstallAttempts = 0;
BOOL DYFSSettingsEntryVisible = NO;
BOOL DYFSVersionMismatch = NO;
NSString *DYFSLastInstallSummary = @"尚未检测";

// Adjustment counters, surfaced by the diagnostics panel in DYFSSettings.
NSUInteger DYFSTabBarApplyCount = 0;
BOOL DYFSLastHomeTabSelected = NO;
BOOL DYFSLastTabBackgroundHidden = NO;

void DYFSLog(NSString *message) {
    NSLog(@"[DY.FullScreen] %@", message);
}

BOOL DYFSIsEnabled(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:DYFSEnabledKey] == nil) return YES;
    return [defaults boolForKey:DYFSEnabledKey];
}

BOOL DYFSInstallHook(Class cls, SEL selector, IMP replacement, IMP *originalOut) {
    if (!cls || !selector || !replacement || !originalOut) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return NO;

    const char *types = method_getTypeEncoding(method);
    IMP original = method_getImplementation(method);
    if (class_addMethod(cls, selector, replacement, types)) {
        *originalOut = original;
        return YES;
    }

    Method ownMethod = class_getInstanceMethod(cls, selector);
    IMP previous = method_setImplementation(ownMethod, replacement);
    *originalOut = previous;
    return previous != replacement;
}

static void DYFSMarkNeedsLayoutRecursively(UIView *view, NSUInteger depth) {
    if (!view || depth > 32) return;
    [view setNeedsLayout];
    for (UIView *subview in [view.subviews copy]) {
        DYFSMarkNeedsLayoutRecursively(subview, depth + 1);
    }
}

void DYFSRequestRelayout(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            DYFSMarkNeedsLayoutRecursively(window, 0);
            [window layoutIfNeeded];
        }
    });
}

NSUInteger DYFSSidebarHookCount(void) {
    return (DYFSInstalledSidebarIcon ? 1 : 0) + (DYFSInstalledSidebarRight ? 1 : 0);
}

NSUInteger DYFSTabBarHookCount(void) {
    return (DYFSInstalledTabBarLayout ? 1 : 0) + (DYFSInstalledTabBarHidden ? 1 : 0);
}

UIViewController *DYFSFindViewController(UIView *view) {
    UIResponder *responder = view;
    for (NSUInteger depth = 0; responder && depth < 40; depth++) {
        if ([responder isKindOfClass:UIViewController.class]) return (UIViewController *)responder;
        responder = responder.nextResponder;
    }
    return nil;
}

UIViewController *DYFSActiveTopViewController(void) {
    UIWindow *activeWindow = nil;
    for (UIWindow *window in UIApplication.sharedApplication.windows.reverseObjectEnumerator) {
        if (window.isKeyWindow) {
            activeWindow = window;
            break;
        }
    }
    if (!activeWindow) activeWindow = UIApplication.sharedApplication.windows.lastObject;
    UIViewController *controller = activeWindow.rootViewController;
    while (controller) {
        if (controller.presentedViewController) {
            controller = controller.presentedViewController;
        } else if ([controller isKindOfClass:UINavigationController.class] &&
                   ((UINavigationController *)controller).topViewController) {
            controller = ((UINavigationController *)controller).topViewController;
        } else if ([controller isKindOfClass:UITabBarController.class] &&
                   ((UITabBarController *)controller).selectedViewController) {
            controller = ((UITabBarController *)controller).selectedViewController;
        } else {
            break;
        }
    }
    return controller;
}

UIView *DYFSFindSubviewOfClass(UIView *root, NSString *className, NSUInteger depth) {
    if (!root || depth > 14) return nil;
    if ([NSStringFromClass(root.class) isEqualToString:className]) return root;
    for (UIView *subview in root.subviews) {
        UIView *match = DYFSFindSubviewOfClass(subview, className, depth + 1);
        if (match) return match;
    }
    return nil;
}

id DYFSSafeValueForKey(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

BOOL DYFSSafeSetValueForKey(id object, id value, NSString *key) {
    if (!object || key.length == 0) return NO;
    @try {
        [object setValue:value forKey:key];
        return YES;
    } @catch (NSException *exception) {
        DYFSLog([NSString stringWithFormat:@"KVC set failed for %@: %@", key, exception.reason ?: @"unknown"]);
        return NO;
    }
}
