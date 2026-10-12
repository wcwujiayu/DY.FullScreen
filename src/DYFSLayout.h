//
//  DYFSLayout.h
//  DY.FullScreen
//
//  Layout (sizing) hooks, installed by Tweak.m.
//

#import <UIKit/UIKit.h>

/// 实测底栏高度；找不到 AWENormalModeTabBar 时回退 49 + safeArea。
CGFloat DYFSBottomTabBarHeight(UIView *view);

void DYFSFeedTableLayout(id self, SEL cmd);
void DYFSStoryContainerLayout(id self, SEL cmd);
void DYFSInteractionControllerLayout(id self, SEL cmd);
void DYFSLayoutInstallHooks(void);
