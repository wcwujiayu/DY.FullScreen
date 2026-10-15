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
extern BOOL DYFSInstalledElementStack;
extern BOOL DYFSInstalledPlayerContentA;
extern BOOL DYFSInstalledPlayerContentB;
extern BOOL DYFSInstalledPlayerContentC;
extern BOOL DYFSInstalledTabBarLayout;
extern BOOL DYFSInstalledTabBarHidden;
extern BOOL DYFSInstalledTabBarDidMove;
extern BOOL DYFSInstalledTabBarDidAddSubview;
extern BOOL DYFSInstalledInteractionProgress;
extern BOOL DYFSInstalledPlayerProgress;
extern BOOL DYFSInstalledDetailTable;
extern BOOL DYFSInstalledDetailCell;
extern BOOL DYFSInstalledMixPanelDetail;
extern BOOL DYFSInstalledNativeSettingsSwitch;
extern BOOL DYFSNativeSettingsRowAdded;
extern BOOL DYFSStartupRelayoutScheduled;
extern BOOL DYFSSchedulePending;
extern NSUInteger DYFSInstallAttempts;
extern BOOL DYFSVersionMismatch;
extern NSString *DYFSLastInstallSummary;

// Adjustment counters, surfaced by the diagnostics panel.
extern NSUInteger DYFSLayoutFixCount;
extern NSUInteger DYFSInteractionContainerAdjustCount;
extern NSUInteger DYFSPlayerContentAdjustCount;
extern NSUInteger DYFSTabBarApplyCount;
extern NSUInteger DYFSBottomChromeHideCount;
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
extern NSString * const kDYFSClassInteractionProgress;   // AWEPlayInteractionProgressContainerView
extern NSString * const kDYFSClassPlayerProgress;   // AWEDPlayerProgressContainerView
extern NSString * const kDYFSClassTabBar;   // AWENormalModeTabBar
extern NSString * const kDYFSClassTabBarGeneralButton;   // AWENormalModeTabBarGeneralButton
extern NSString * const kDYFSClassTabBarGeneralPlusButton;   // AWENormalModeTabBarGeneralPlusButton
extern NSString * const kDYFSClassTabBarPlusButton;   // AWENormalModeTabBarPlusButton
extern NSString * const kDYFSClassSettings;   // AWESettingsTableViewController
extern NSString * const kDYFSClassSettingItemModel;   // AWESettingItemModel
extern NSString * const kDYFSClassSettingSectionModel;   // AWESettingSectionModel
extern NSString * const kDYFSClassBarBackground;   // _UIBarBackground
extern NSString * const kDYFSClassDetailTable;   // AWEAwemeDetailTableViewController
extern NSString * const kDYFSClassDetailCell;   // AWEAwemeDetailCellViewController
extern NSString * const kDYFSClassMixPanel;   // AWEMixVideoPanelDetailTableViewController
extern NSString * const kDYFSClassElementStack;   // AWEElementStackView

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
NSUInteger DYFSTabBarHookCount(void);

// ---------------------------------------------------------------------------
// 外观原值备份。
//
// 之前的透明化是「单向写入」：一旦把 backgroundColor 清成透明、把 view 隐藏，
// 关掉开关也不会还原，必须杀掉抖音进程重开。这里在首次改动前把原值存到
// associated object 上，关掉开关时统一恢复。
// ---------------------------------------------------------------------------
void DYFSBackupAppearance(UIView *view);
void DYFSRestoreAllAppearance(void);

// 命中率日志：几何阈值失配（去灰底悄悄失效）时打一条，方便定位。
void DYFSNoteCardMiss(CGFloat width, CGFloat height, CGFloat refWidth);

// ---------------------------------------------------------------------------
// 视图探测与背景清除（原 DYFSTransparency 内部 static，
// 0.5.7 拆分为「卡片去灰底」与「底栏清理」两个模块后提为共享）。
// ---------------------------------------------------------------------------
NSString *DYFSTextForView(UIView *view);
BOOL DYFSIsCaptionDescriptionView(UIView *view);
BOOL DYFSSubtreeHasCaptionDescription(UIView *view, NSUInteger depth);
BOOL DYFSSubtreeHasText(UIView *view, NSUInteger depth);
BOOL DYFSSubtreeHasControl(UIView *view, NSUInteger depth);
BOOL DYFSIsNamedChrome(UIView *view);
BOOL DYFSIsPlainBacking(UIView *view);
BOOL DYFSIsDarkBackgroundView(UIView *view);
void DYFSClearOwnBackground(UIView *view);
// 只把「纯黑不透明」底板清成透明（改颜色，不动 frame）。
void DYFSClearOpaqueBlackBackground(UIView *view);
/// 实测底栏高度；找不到 AWENormalModeTabBar 时回退 49 + safeArea。
CGFloat DYFSBottomTabBarHeight(UIView *view);
