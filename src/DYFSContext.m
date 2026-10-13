//
//  DYFSContext.m
//  DY.FullScreen
//
//  Context guards: decide whether a view belongs to a place the tweak must
//  leave alone (profile, real live room, pre-stream preview, detail page).
//

#import "DYFSContext.h"
#import "DYFSCommon.h"
#import <objc/message.h>

// 上下文判定用的类名特征串（抖音改版时只需改这里）
static NSString * const kDYFSGuardUserHome = @"UserHomeViewController";
static NSString * const kDYFSGuardUserProfile = @"UserProfileViewController";
static NSString * const kDYFSGuardProfile = @"ProfileViewController";
static NSString * const kDYFSGuardPreStreamVC = @"AWELiveNewPreStreamViewController";
static NSString * const kDYFSGuardPreStream = @"AWELivePreStream";
static NSString * const kDYFSGuardIESAudience = @"IESLiveAudienceViewController";
static NSString * const kDYFSGuardAWEAudience = @"AWELiveAudienceViewController";
static NSString * const kDYFSGuardLiveRoomContainer = @"LiveRoomContainerViewController";
static NSString * const kDYFSGuardLiveRoom = @"LiveRoomViewController";
static NSString * const kDYFSGuardDetailTable = @"AWEAwemeDetailTableViewController";
static NSString * const kDYFSGuardDetailCell = @"AWEAwemeDetailCellViewController";
static NSString * const kDYFSGuardMixPanel = @"AWEMixVideoPanelDetailTableViewController";
static NSString * const kDYFSGuardFeedCell = @"AWEFeedCellViewController";

static BOOL DYFSClassNameIsLiveRoom(NSString *name) {
    if (name.length == 0) return NO;
    // 注意：信息流里的直播「卡片」(IESLiveInnerFeedLiveRoomCell) 不是真实直播间，
    // 它的 audienceVC 才是 IESLiveAudienceViewController。把它也算进 live room 会让
    // DYFSLiveCellLayout 的「直播卡片上移」逻辑因 early-return 而永远不执行。
    // 真实直播间只认下面这几种 VC / 容器类名。
    return [name containsString:kDYFSGuardIESAudience] ||
           [name containsString:kDYFSGuardAWEAudience] ||
           [name containsString:kDYFSGuardLiveRoom] ||
           [name containsString:kDYFSGuardLiveRoomContainer];
}

BOOL DYFSInProfileContext(UIView *view) {
    UIResponder *item = view;
    for (NSUInteger depth = 0; item && depth < 20; depth++) {
        item = item.nextResponder;
        NSString *name = item ? NSStringFromClass(item.class) : @"";
        if ([name containsString:kDYFSGuardUserHome] ||
            [name containsString:kDYFSGuardUserProfile] ||
            [name containsString:kDYFSGuardProfile]) {
            return YES;
        }
    }
    return NO;
}

BOOL DYFSIsLivePreStreamContext(UIView *view) {
    if (!view) return NO;

    for (UIView *cursor = view; cursor; cursor = cursor.superview) {
        NSString *name = NSStringFromClass(cursor.class);
        if ([name containsString:kDYFSGuardPreStreamVC] ||
            [name containsString:kDYFSGuardPreStream]) {
            return YES;
        }
    }

    UIViewController *controller = DYFSFindViewController(view);
    for (NSUInteger depth = 0; controller && depth < 20; depth++, controller = controller.parentViewController) {
        NSString *name = NSStringFromClass(controller.class);
        if ([name containsString:kDYFSGuardPreStreamVC] ||
            [name containsString:kDYFSGuardPreStream]) {
            return YES;
        }
    }

    UIResponder *responder = view;
    for (NSUInteger depth = 0; responder && depth < 40; depth++, responder = responder.nextResponder) {
        NSString *name = NSStringFromClass(responder.class);
        if ([name containsString:kDYFSGuardPreStreamVC] ||
            [name containsString:kDYFSGuardPreStream]) {
            return YES;
        }
    }
    return NO;
}

BOOL DYFSIsLivePreStreamPlayer(id playerController) {
    if (!playerController) return NO;

    NSString *ownName = NSStringFromClass([playerController class]);
    if ([ownName containsString:kDYFSGuardPreStreamVC] ||
        [ownName containsString:kDYFSGuardPreStream]) {
        return YES;
    }

    if ([playerController isKindOfClass:UIViewController.class]) {
        UIViewController *cursor = (UIViewController *)playerController;
        for (NSUInteger depth = 0; cursor && depth < 20; depth++, cursor = cursor.parentViewController) {
            NSString *name = NSStringFromClass(cursor.class);
            if ([name containsString:kDYFSGuardPreStreamVC] ||
                [name containsString:kDYFSGuardPreStream]) {
                return YES;
            }
        }
        if (DYFSIsLivePreStreamContext(((UIViewController *)playerController).view)) return YES;
    }

    // Some Douyin builds host the preview player in a sibling controller rather
    // than making it a child of the pre-stream controller. Protect it based on
    // the active screen as well, so the player height hook cannot pull it off-center.
    UIViewController *active = DYFSActiveTopViewController();
    for (NSUInteger depth = 0; active && depth < 20; depth++, active = active.parentViewController) {
        NSString *name = NSStringFromClass(active.class);
        if ([name containsString:kDYFSGuardPreStreamVC] ||
            [name containsString:kDYFSGuardPreStream]) {
            return YES;
        }
    }

    return NO;
}

// 信息流里的直播卡片（IESLiveInnerFeedLiveRoomCell）会内嵌一个 audienceVC，
// 但它的宿主是信息流而非真实直播间。把它误判成「真实直播间」会让透明化与
// 卡片内容上移全部 early-return 而失效，因此这里显式排除。
BOOL DYFSViewIsInsideLiveFeedCell(UIView *view) {
    for (UIView *cursor = view; cursor; cursor = cursor.superview) {
        if ([NSStringFromClass(cursor.class) isEqualToString:kDYFSClassLiveFeedCell]) return YES;
    }
    return NO;
}

BOOL DYFSIsActualLiveRoomContext(UIView *view) {
    // 直播卡片内嵌 audienceVC，但属于信息流，不当成真实直播间处理。
    if (DYFSViewIsInsideLiveFeedCell(view)) return NO;

    for (UIView *cursor = view; cursor; cursor = cursor.superview) {
        if (DYFSClassNameIsLiveRoom(NSStringFromClass(cursor.class))) return YES;
    }

    UIResponder *responder = view;
    for (NSUInteger depth = 0; responder && depth < 40; depth++, responder = responder.nextResponder) {
        if (DYFSClassNameIsLiveRoom(NSStringFromClass(responder.class))) return YES;
    }

    UIViewController *controller = DYFSFindViewController(view);
    for (NSUInteger depth = 0; controller && depth < 20; depth++, controller = controller.parentViewController) {
        if (DYFSClassNameIsLiveRoom(NSStringFromClass(controller.class))) return YES;
    }

    // The preview/live player can be a sibling of the active room controller.
    UIViewController *active = DYFSActiveTopViewController();
    for (NSUInteger depth = 0; active && depth < 20; depth++, active = active.parentViewController) {
        if (DYFSClassNameIsLiveRoom(NSStringFromClass(active.class))) return YES;
    }
    return NO;
}

BOOL DYFSIsDetailVideoContext(UIView *view) {
    UIViewController *controller = DYFSFindViewController(view);
    for (NSUInteger depth = 0; controller && depth < 20; depth++, controller = controller.parentViewController) {
        NSString *name = NSStringFromClass(controller.class);
        if ([name containsString:kDYFSGuardDetailTable] ||
            [name containsString:kDYFSGuardDetailCell] ||
            [name containsString:kDYFSGuardMixPanel]) {
            return YES;
        }
    }
    return NO;
}

static BOOL DYFSModelHasLiveSignal(id model) {
    if (!model) return NO;
    @try {
        SEL isLiveSelector = NSSelectorFromString(@"isLive");
        if ([model respondsToSelector:isLiveSelector] &&
            ((BOOL (*)(id, SEL))objc_msgSend)(model, isLiveSelector)) {
            return YES;
        }
        SEL cellRoomSelector = NSSelectorFromString(@"cellRoom");
        if ([model respondsToSelector:cellRoomSelector] &&
            ((id (*)(id, SEL))objc_msgSend)(model, cellRoomSelector) != nil) {
            return YES;
        }
        SEL feedTagSelector = NSSelectorFromString(@"videoFeedTag");
        if ([model respondsToSelector:feedTagSelector]) {
            id tag = ((id (*)(id, SEL))objc_msgSend)(model, feedTagSelector);
            if ([tag isKindOfClass:NSString.class] && [tag isEqualToString:@"直播中"]) {
                return YES;
            }
        }
    } @catch (__unused NSException *exception) {
        return NO;
    }
    return NO;
}

BOOL DYFSIsFeedCellInteractionController(UIViewController *controller) {
    if (!controller) return NO;

    id base = DYFSSafeValueForKey(controller, @"awemeBaseViewController");
    NSString *baseName = base ? NSStringFromClass([base class]) : @"";
    if ([baseName containsString:kDYFSGuardFeedCell]) return YES;

    // Some live cards wrap the interaction controller in a different base class.
    // Keep the fallback restricted to an attached feed interaction controller;
    // the caller separately excludes profile, pre-stream and actual live-room contexts.
    id model = DYFSSafeValueForKey(base, @"model");
    if (!model) model = DYFSSafeValueForKey(controller, @"model");
    BOOL hasLiveSignal = DYFSModelHasLiveSignal(model);

    UIViewController *cursor = controller.parentViewController;
    for (NSUInteger depth = 0; cursor && depth < 12; depth++, cursor = cursor.parentViewController) {
        NSString *name = NSStringFromClass(cursor.class);
        if ([name containsString:kDYFSGuardFeedCell]) return YES;
    }

    return hasLiveSignal && controller.isViewLoaded && controller.view.window != nil &&
        controller.view.superview != nil;
}
