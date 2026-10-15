//
//  DYFSContext.h
//  DY.FullScreen
//
//  上下文判定：决定某个 view 属于必须放过的场景（个人主页、详情页、IM 详情），
//  还是允许本插件调整的信息流视频 cell / 直播预览卡片。
//

#import <UIKit/UIKit.h>

BOOL DYFSInProfileContext(UIView *view);
BOOL DYFSIsDetailVideoContext(UIView *view);
BOOL DYFSIsIMDetailContext(UIView *view);
BOOL DYFSIsLivePreStreamContext(UIView *view);
BOOL DYFSIsFeedCellInteractionController(UIViewController *controller);
