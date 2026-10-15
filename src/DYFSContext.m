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
            [name containsString:@"AWEMixVideoPanelDetailTableViewController"] ||
            [name containsString:@"AWEAwemeIMDetailTableViewController"]) {
            return YES;
        }
    }
    return NO;
}

BOOL DYFSIsIMDetailContext(UIView *view) {
    UIViewController *controller = DYFSFindViewController(view);
    for (NSUInteger depth = 0; controller && depth < 20; depth++, controller = controller.parentViewController) {
        if ([NSStringFromClass(controller.class) containsString:@"AWEAwemeIMDetailTableViewController"]) {
            return YES;
        }
    }
    return NO;
}

// 普通聊天会话窗口：消息列表 + 底部输入栏（IESIMInputViewController）。
// 这类页面底部本来就有毛玻璃底栏，兜底的「贴底深色条隐藏」会把它误判成黑条
// 隐藏掉，出现底栏透明一块。因此整个聊天会话都不做处理。
// 注意：聊天里点开的「分享视频详情」(AWEAwemeIMDetailTableViewController)
// 不属于这里，仍要正常做底栏透明。
BOOL DYFSIsChatConversationContext(UIView *view) {
    if (DYFSIsIMDetailContext(view)) return NO;
    UIViewController *controller = DYFSFindViewController(view);
    for (NSUInteger depth = 0; controller && depth < 20; depth++, controller = controller.parentViewController) {
        NSString *name = NSStringFromClass(controller.class);
        if ([name containsString:@"AWEIMMessageBaseViewController"] ||
            [name containsString:@"AWEIMConversationViewController"] ||
            [name containsString:@"AWEIMMessageListViewController"] ||
            [name containsString:@"AWEIMChatListViewController"] ||
            [name containsString:@"IESIMInputViewController"]) {
            return YES;
        }
    }
    return NO;
}

BOOL DYFSIsLivePreStreamContext(UIView *view) {
    UIResponder *item = view;
    for (NSUInteger depth = 0; item && depth < 20; depth++) {
        item = item.nextResponder;
        NSString *name = item ? NSStringFromClass(item.class) : @"";
        if ([name containsString:@"AWELiveNewPreStreamViewController"] ||
            [name containsString:@"AWEFeedLiveStreamTableViewCell"] ||
            [name containsString:@"AWELivePreStream"]) {
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
