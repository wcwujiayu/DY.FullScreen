//
//  DYFSCommon.h
//  DY.FullScreen
//
//  Shared constants, runtime helpers and cross-module state.
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

extern NSString * const DYFSBundleID;
extern NSString * const DYFSTestedVersion;
extern NSString * const DYFSEnabledKey;
extern NSString * const DYFSSettingsTitle;

// Hook installation state (written by Tweak.m, read by diagnostics).
extern BOOL DYFSInstalledFeed;
extern BOOL DYFSInstalledStory;
extern BOOL DYFSInstalledInteractionController;
extern BOOL DYFSInstalledPlayerContentA;
extern BOOL DYFSInstalledPlayerContentB;
extern BOOL DYFSInstalledPlayerContentC;
extern BOOL DYFSInstalledSidebarIcon;
extern BOOL DYFSInstalledSidebarRight;
extern BOOL DYFSInstalledTabBarLayout;
extern BOOL DYFSInstalledTabBarHidden;
extern BOOL DYFSInstalledTabBarDidMove;
extern BOOL DYFSInstalledTabBarDidAddSubview;
extern BOOL DYFSInstalledInteractionProgress;
extern BOOL DYFSInstalledPlayerProgress;
extern BOOL DYFSInstalledNativeSettingsSwitch;
extern BOOL DYFSNativeSettingsRowAdded;
extern BOOL DYFSStartupRelayoutScheduled;
extern BOOL DYFSSchedulePending;
extern NSUInteger DYFSInstallAttempts;
extern BOOL DYFSSettingsEntryVisible;
extern BOOL DYFSVersionMismatch;
extern NSString *DYFSLastInstallSummary;

// Adjustment counters, surfaced by the diagnostics panel.
extern NSUInteger DYFSLayoutFixCount;
extern NSUInteger DYFSInteractionContainerAdjustCount;
extern NSUInteger DYFSPlayerContentAdjustCount;
extern NSUInteger DYFSLivePreviewPlayerAdjustCount;
extern NSUInteger DYFSTabBarApplyCount;
extern BOOL DYFSLastHomeTabSelected;
extern BOOL DYFSLastTabBackgroundHidden;

void DYFSLog(NSString *message);
BOOL DYFSIsEnabled(void);
BOOL DYFSInstallHook(Class cls, SEL selector, IMP replacement, IMP *originalOut);
id DYFSSafeValueForKey(id object, NSString *key);
BOOL DYFSSafeSetValueForKey(id object, id value, NSString *key);
UIViewController *DYFSFindViewController(UIView *view);
UIViewController *DYFSActiveTopViewController(void);
UIView *DYFSFindSubviewOfClass(UIView *root, NSString *className, NSUInteger depth);
void DYFSRequestRelayout(void);
NSUInteger DYFSSidebarHookCount(void);
NSUInteger DYFSTabBarHookCount(void);
