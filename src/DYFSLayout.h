//
//  DYFSLayout.h
//  DY.FullScreen
//
//  全屏尺寸修正（以 0.3.15 的逻辑为准）。
//
//  0.4.x 曾把 DYFSInteractionControllerLayout 加上「只在直播卡片内生效」的
//  守卫，导致普通视频的互动层高度不再被调整 —— 这就是 0.4 以后全屏被改坏
//  的直接原因。这里恢复成对普通信息流视频生效。
//

#import <UIKit/UIKit.h>

void DYFSFeedTableLayout(id self, SEL cmd);
void DYFSStoryContainerLayout(id self, SEL cmd);
void DYFSInteractionControllerLayout(id self, SEL cmd);
void DYFSPlayerContentLayoutA(id self, SEL cmd);
void DYFSPlayerContentLayoutB(id self, SEL cmd);
void DYFSPlayerContentLayoutC(id self, SEL cmd);
void DYFSDetailTableLayout(id self, SEL cmd);
void DYFSDetailCellLayout(id self, SEL cmd);
void DYFSMixPanelDetailLayout(id self, SEL cmd);
void DYFSElementStackLayout(id self, SEL cmd);

void DYFSLayoutInstallHooks(void);
