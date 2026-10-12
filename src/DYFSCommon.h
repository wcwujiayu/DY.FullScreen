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
extern BOOL DYFSInstalledSidebarIcon;
extern BOOL DYFSInstalledSidebarRight;
extern BOOL DYFSInstalledTabBarLayout;
extern BOOL DYFSInstalledTabBarHidden;
extern BOOL DYFSInstalledTabBarDidMove;
extern BOOL DYFSInstalledTabBarDidAddSubview;
extern BOOL DYFSInstalledInteractionProgress;
extern BOOL DYFSInstalledSetFrameHook;
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
extern NSUInteger DYFSTabBarApplyCount;
extern BOOL DYFSLastHomeTabSelected;
extern BOOL DYFSLastTabBackgroundHidden;


// ---------------------------------------------------------------------------
// 抖音私有类名集中清单。
// 抖音改版导致类名变化时，只需要修改这里，不用在代码里逐个搜索替换。
// ---------------------------------------------------------------------------
extern NSString * const kDYFSClassFeedTableView;   // AWEFeedTableView
extern NSString * const kDYFSClassStoryContainer;   // AWEStoryContainerCollectionView
extern NSString * const kDYFSClassPlayInteraction;   // AWEPlayInteractionViewController
extern NSString * const kDYFSClassPlayVideoA;   // AWEAwemePlayVideoViewController
extern NSString * const kDYFSClassPlayVideoB;   // AWEDPlayerFeedPlayerViewController
extern NSString * const kDYFSClassPlayVideoC;   // AWEDPlayerViewController_Merge
extern NSString * const kDYFSClassSidebarIcon;   // AWELeftSideBarTopIconHorizontalView
extern NSString * const kDYFSClassSidebarRight;   // AWELeftSideBarTopRightLayoutView
extern NSString * const kDYFSClassInteractionProgress;   // AWEPlayInteractionProgressContainerView
extern NSString * const kDYFSClassPlayerProgress;   // AWEDPlayerProgressContainerView
extern NSString * const kDYFSClassTabBar;   // AWENormalModeTabBar
extern NSString * const kDYFSClassTabBarGeneralButton;   // AWENormalModeTabBarGeneralButton
extern NSString * const kDYFSClassTabBarGeneralPlusButton;   // AWENormalModeTabBarGeneralPlusButton
extern NSString * const kDYFSClassTabBarPlusButton;   // AWENormalModeTabBarPlusButton
extern NSString * const kDYFSClassSettings;   // AWESettingsTableViewController
extern NSString * const kDYFSClassSettingItemModel;   // AWESettingItemModel
extern NSString * const kDYFSClassSettingSectionModel;   // AWESettingSectionModel
extern NSString * const kDYFSClassLiveFeedCell;   // IESLiveInnerFeedLiveRoomCell
extern NSString * const kDYFSClassBarBackground;   // _UIBarBackground

// 安装调度
extern const NSUInteger kDYFSMaxInstallAttempts;      // 最多重试次数
extern const NSTimeInterval kDYFSInstallRetryInterval; // 每次重试间隔（秒）

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
