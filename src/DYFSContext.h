//
//  DYFSContext.h
//  DY.FullScreen
//
//  Context guards used before touching any layout.
//

#import <UIKit/UIKit.h>

BOOL DYFSInProfileContext(UIView *view);
BOOL DYFSIsLivePreStreamContext(UIView *view);
BOOL DYFSIsLivePreStreamPlayer(id playerController);
BOOL DYFSIsActualLiveRoomContext(UIView *view);
BOOL DYFSViewIsInsideLiveFeedCell(UIView *view);
BOOL DYFSIsDetailVideoContext(UIView *view);
BOOL DYFSIsFeedCellInteractionController(UIViewController *controller);
