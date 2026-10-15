//
//  Tweak.m
//  DY.FullScreen
//
//  入口：安装各模块的 hook 并持续重试，直到抖音懒加载的类都已就绪。
//  真正的逻辑分散在 DYFSLayout / DYFSChrome / DYFSTransparency /
//  DYFSSettings 四个模块里，本文件不做具体处理。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#import "DYFSCommon.h"
#import "DYFSLayout.h"
#import "DYFSChrome.h"
#import "DYFSSettings.h"

// 启动后两次重排：第一次消化初始布局，第二次修正延迟加载的视图
static const NSTimeInterval kDYFSStartupRelayoutDelayA = 0.20;
static const NSTimeInterval kDYFSStartupRelayoutDelayB = 0.65;

static void DYFSInstallHooks(void) {
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"";
    if (![bundle isEqualToString:DYFSBundleID]) return;

    DYFSLayoutInstallHooks();      // 全屏尺寸修正（0.3.15 逻辑）
    DYFSChromeInstallHooks();      // 底栏与进度条透明
    DYFSSettingsInstallHooks();    // 侧边栏入口与原生设置开关
    // 去灰底（DYFSTransparency）没有独立 hook，
    // 由上述 layout hook 在布局完成后触发。

    NSString *summary = [NSString stringWithFormat:
        @"video-list %@; story-container %@; interaction-controller %@; player-content %d/3; "
        @"element-stack %@; detail hooks %d/3; "
        @"tab bar hooks %lu/2; settings-switch %@",
        DYFSInstalledFeed ? @"on" : @"off",
        DYFSInstalledStory ? @"on" : @"off",
        DYFSInstalledInteractionController ? @"on" : @"off",
        (int)DYFSInstalledPlayerContentA + (int)DYFSInstalledPlayerContentB + (int)DYFSInstalledPlayerContentC,
        DYFSInstalledElementStack ? @"on" : @"off",
        (int)DYFSInstalledDetailTable + (int)DYFSInstalledDetailCell + (int)DYFSInstalledMixPanelDetail,
        (unsigned long)DYFSTabBarHookCount(),
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
        BOOL tabBarInstalled = DYFSInstalledTabBarLayout && DYFSInstalledTabBarHidden;
        BOOL playerLayoutInstalled = DYFSInstalledPlayerContentB || DYFSInstalledPlayerContentC;
        BOOL detailInstalled = DYFSInstalledDetailTable || DYFSInstalledDetailCell || DYFSInstalledMixPanelDetail;

        if (!DYFSStartupRelayoutScheduled && layoutInstalled && tabBarInstalled && playerLayoutInstalled) {
            DYFSStartupRelayoutScheduled = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDYFSStartupRelayoutDelayA * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ DYFSRequestRelayout(); });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDYFSStartupRelayoutDelayB * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ DYFSRequestRelayout(); });
        }

        if ((!layoutInstalled || !tabBarInstalled ||
             !DYFSInstalledNativeSettingsSwitch || !playerLayoutInstalled ||
             !DYFSInstalledElementStack || !detailInstalled) &&
            DYFSInstallAttempts < kDYFSMaxInstallAttempts) {
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
