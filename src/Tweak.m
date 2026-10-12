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
#import "DYLiveFeedFullscreen.h"

static void DYFSInstallHooks(void) {
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"";
    if (![bundle isEqualToString:DYFSBundleID]) return;

    // The feed live-cell class may become available after initial +load.
    // Keep installation idempotent and retry alongside the existing hook pass.
    [[DYLiveFeedFullscreen sharedInstance] installHooksIfNeeded];

    DYFSLayoutInstallHooks();
    DYFSChromeInstallHooks();
    DYFSSettingsInstallHooks();

    NSString *summary = [NSString stringWithFormat:@"video-list %@; story-container %@; interaction-controller %@; player-content %d/3; sidebar hooks %lu/2; tab bar hooks %lu/2; settings-switch %@",
                         DYFSInstalledFeed ? @"on" : @"off", DYFSInstalledStory ? @"on" : @"off",
                         DYFSInstalledInteractionController ? @"on" : @"off",
                         (int)DYFSInstalledPlayerContentA + (int)DYFSInstalledPlayerContentB + (int)DYFSInstalledPlayerContentC,
                         (unsigned long)DYFSSidebarHookCount(), (unsigned long)DYFSTabBarHookCount(),
                         DYFSInstalledNativeSettingsSwitch ? @"on" : @"off"];
    if (![summary isEqualToString:DYFSLastInstallSummary]) {
        DYFSLastInstallSummary = [summary copy];
        DYFSLog(summary);
    }
}

static void DYFSScheduleHooks(void) {
    if (DYFSSchedulePending || DYFSInstallAttempts >= 60) return;
    DYFSSchedulePending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        DYFSSchedulePending = NO;
        DYFSInstallAttempts++;
        DYFSInstallHooks();

        BOOL layoutInstalled = DYFSInstalledFeed && DYFSInstalledStory && DYFSInstalledInteractionController;
        BOOL sidebarInstalled = DYFSInstalledSidebarIcon || DYFSInstalledSidebarRight;
        BOOL tabBarInstalled = DYFSInstalledTabBarLayout && DYFSInstalledTabBarHidden;
        BOOL playerLayoutInstalled = DYFSInstalledPlayerContentB || DYFSInstalledPlayerContentC;

        if (!DYFSStartupRelayoutScheduled && layoutInstalled && tabBarInstalled && playerLayoutInstalled) {
            DYFSStartupRelayoutScheduled = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ DYFSRequestRelayout(); });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ DYFSRequestRelayout(); });
        }

        if ((!layoutInstalled || !sidebarInstalled || !tabBarInstalled || !DYFSInstalledNativeSettingsSwitch ||
             !playerLayoutInstalled) && DYFSInstallAttempts < 60) {
            DYFSScheduleHooks();
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
