//
//  DYFSLayout.h
//  DY.FullScreen
//
//  Layout (sizing) hooks, installed by Tweak.m.
//

#import <UIKit/UIKit.h>

// 尺寸修正相关的 hook。DYFSBottomTabBarHeight 仅模块内部使用，不对外暴露。
void DYFSFeedTableLayout(id self, SEL cmd);
void DYFSStoryContainerLayout(id self, SEL cmd);
void DYFSInteractionControllerLayout(id self, SEL cmd);
void DYFSPlayerContentLayoutA(id self, SEL cmd);
void DYFSPlayerContentLayoutB(id self, SEL cmd);
void DYFSPlayerContentLayoutC(id self, SEL cmd);
void DYFSLayoutInstallHooks(void);
