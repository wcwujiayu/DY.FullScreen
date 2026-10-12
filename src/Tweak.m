//
//  Tweak.m
//  DY.FullScreen
//
//  Entry point only: install every hook and keep retrying until Douyin's
//  lazily-loaded classes exist. All real work lives in the feature modules.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "DYFSCommon.h"
#import "DYFSContext.h"
#import "DYFSLayout.h"
#import "DYFSChrome.h"
#import "DYFSSettings.h"

// 启动后两次重排：第一次消化初始布局，第二次修正延迟加载的视图
static const NSTimeInterval kDYFSStartupRelayoutDelayA = 0.20;
static const NSTimeInterval kDYFSStartupRelayoutDelayB = 0.65;

static void DYFSInstallHooks(void) {
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"";
    if (![bundle isEqualToString:DYFSBundleID]) return;

    DYFSLayoutInstallHooks();
    DYFSChromeInstallHooks();
    DYFSSettingsInstallHooks();

    NSString *summary = [NSString stringWithFormat:@"video-list %@; story-container %@; interaction-controller %@; setFrame %@; sidebar hooks %lu/2; tab bar hooks %lu/2; settings-switch %@",
                         DYFSInstalledFeed ? @"on" : @"off", DYFSInstalledStory ? @"on" : @"off",
                         DYFSInstalledInteractionController ? @"on" : @"off",
                         DYFSInstalledSetFrameHook ? @"on" : @"off",
                         (unsigned long)DYFSSidebarHookCount(), (unsigned long)DYFSTabBarHookCount(),
                         DYFSInstalledNativeSettingsSwitch ? @"on" : @"off"];
    if (![summary isEqualToString:DYFSLastInstallSummary]) {
        DYFSLastInstallSummary = [summary copy];
        DYFSLog(summary);
    }
}

static void DYFSScheduleHooks(void) {
    if (DYFSSchedulePending || DYFSInstallAttempts >= kDYFSMaxInstallAttempts) return;
    DYFSSchedulePending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDYFSInstallRetryInterval * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        DYFSSchedulePending = NO;
        DYFSInstallAttempts++;
        DYFSInstallHooks();

        BOOL layoutInstalled = DYFSInstalledFeed && DYFSInstalledStory && DYFSInstalledInteractionController;
        BOOL sidebarInstalled = DYFSInstalledSidebarIcon || DYFSInstalledSidebarRight;
        BOOL tabBarInstalled = DYFSInstalledTabBarLayout && DYFSInstalledTabBarHidden;
        BOOL sizingInstalled = DYFSInstalledSetFrameHook;

        if (!DYFSStartupRelayoutScheduled && layoutInstalled && tabBarInstalled && sizingInstalled) {
            DYFSStartupRelayoutScheduled = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDYFSStartupRelayoutDelayA * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ DYFSRequestRelayout(); });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDYFSStartupRelayoutDelayB * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ DYFSRequestRelayout(); });
        }

        if ((!layoutInstalled || !sidebarInstalled || !tabBarInstalled || !DYFSInstalledNativeSettingsSwitch ||
             !playerLayoutInstalled) && DYFSInstallAttempts < kDYFSMaxInstallAttempts) {
            DYFSScheduleHooks();
            return;
        }

        // 放弃重试前把缺失项一次性打出来，方便定位是哪几个类没找到。
        if (DYFSInstallAttempts >= kDYFSMaxInstallAttempts &&
            (!layoutInstalled || !sidebarInstalled || !tabBarInstalled ||
             !DYFSInstalledNativeSettingsSwitch || !sizingInstalled)) {
            NSMutableArray *missing = [NSMutableArray array];
            if (!DYFSInstalledFeed) [missing addObject:@"AWEFeedTableView"];
            if (!DYFSInstalledStory) [missing addObject:@"AWEStoryContainerCollectionView"];
            if (!DYFSInstalledInteractionController) [missing addObject:@"AWEPlayInteractionViewController"];
            if (!DYFSInstalledSetFrameHook) [missing addObject:@"UIView setFrame hook"];
            if (!DYFSInstalledTabBarLayout || !DYFSInstalledTabBarHidden) [missing addObject:@"AWENormalModeTabBar"];
            if (!DYFSInstalledSidebarIcon && !DYFSInstalledSidebarRight) [missing addObject:@"sidebar entry"];
            if (!DYFSInstalledNativeSettingsSwitch) [missing addObject:@"AWESettingsTableViewController"];
            DYFSLog([NSString stringWithFormat:@"gave up after %lu attempts; missing: %@",
                     (unsigned long)DYFSInstallAttempts,
                     missing.count ? [missing componentsJoinedByString:@", "] : @"(unknown)"]);
        }
    });
}

__attribute__((constructor)) static void DYFSConstructor(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:DYFSBundleID]) return;

        DYFSLog(@"loaded into Douyin");
        NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown";
        DYFSVersionMismatch = ![version hasPrefix:DYFSTestedVersion];
        if (DYFSVersionMismatch) {
            DYFSLog([NSString stringWithFormat:@"tested for %@; current app version is %@", DYFSTestedVersion, version]);
        }
        if ([NSUserDefaults.standardUserDefaults objectForKey:DYFSEnabledKey] == nil) {
            [NSUserDefaults.standardUserDefaults setBool:YES forKey:DYFSEnabledKey];
        }
        DYFSScheduleHooks();
    }
}
