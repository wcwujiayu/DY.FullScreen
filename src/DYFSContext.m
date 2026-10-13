//
//  DYFSContext.m
//  DY.FullScreen
//
//  上下文判定：个人主页、详情页、信息流视频 cell。
//  （直播间 / 开播预览相关判定已全部移除）
//

#import "DYFSContext.h"
#import "DYFSCommon.h"
BOOL DYFSInProfileContext(UIView *view) {
    UIResponder *item = view;
    for (NSUInteger depth = 0; item && depth < 20; depth++) {
        item = item.nextResponder;
        NSString *name = item ? NSStringFromClass(item.class) : @"";
        if ([name containsString:@"UserHomeViewController"] ||
            [name containsString:@"UserProfileViewController"] ||
            [name containsString:@"ProfileViewController"]) {
            return YES;
        }
    }
    return NO;
}

BOOL DYFSIsDetailVideoContext(UIView *view) {
    UIViewController *controller = DYFSFindViewController(view);
    for (NSUInteger depth = 0; controller && depth < 20; depth++, controller = controller.parentViewController) {
        NSString *name = NSStringFromClass(controller.class);
        if ([name containsString:@"AWEAwemeDetailTableViewController"] ||
            [name containsString:@"AWEAwemeDetailCellViewController"] ||
            [name containsString:@"AWEMixVideoPanelDetailTableViewController"]) {
            return YES;
        }
    }
    return NO;
}

BOOL DYFSIsFeedCellInteractionController(UIViewController *controller) {
    if (!controller) return NO;

    id base = DYFSSafeValueForKey(controller, @"awemeBaseViewController");
    NSString *baseName = base ? NSStringFromClass([base class]) : @"";
    if ([baseName containsString:@"AWEFeedCellViewController"]) return YES;
    if (base) return NO;

    UIViewController *cursor = controller.parentViewController;
    for (NSUInteger depth = 0; cursor && depth < 12; depth++, cursor = cursor.parentViewController) {
        NSString *name = NSStringFromClass(cursor.class);
        if ([name containsString:@"AWEFeedCellViewController"]) return YES;
    }
    return NO;
}
