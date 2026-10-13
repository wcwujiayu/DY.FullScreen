//
//  DYFSContext.h
//  DY.FullScreen
//
//  上下文判定：决定某个 view 属于必须放过的场景（个人主页、详情页），
//  还是允许本插件调整的信息流视频 cell。
//

#import <UIKit/UIKit.h>

BOOL DYFSInProfileContext(UIView *view);
BOOL DYFSIsDetailVideoContext(UIView *view);
BOOL DYFSIsFeedCellInteractionController(UIViewController *controller);
