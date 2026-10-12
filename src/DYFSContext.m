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

static BOOL DYFSClassNameIsLiveRoom(NSString *name) {
    if (name.length == 0) return NO;
    return [name containsString:@"IESLiveAudienceViewController"] ||
           [name containsString:@"AWELiveAudienceViewController"] ||
           [name containsString:@"IESLiveInnerFeedLiveRoomCell"] ||
           [name containsString:@"LiveRoomViewController"] ||
           [name containsString:@"LiveRoomContainerViewController"];
}

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

BOOL DYFSIsLivePreStreamContext(UIView *view) {
    if (!view) return NO;

    for (UIView *cursor = view; cursor; cursor = cursor.superview) {
        NSString *name = NSStringFromClass(cursor.class);
        if ([name containsString:@"AWELiveNewPreStreamViewController"] ||
            [name containsString:@"AWELivePreStream"]) {
            return YES;
        }
    }

    UIViewController *controller = DYFSFindViewController(view);
    for (NSUInteger depth = 0; controller && depth < 20; depth++, controller = controller.parentViewController) {
        NSString *name = NSStringFromClass(controller.class);
        if ([name containsString:@"AWELiveNewPreStreamViewController"] ||
            [name containsString:@"AWELivePreStream"]) {
            return YES;
        }
    }

    UIResponder *responder = view;
    for (NSUInteger depth = 0; responder && depth < 40; depth++, responder = responder.nextResponder) {
        NSString *name = NSStringFromClass(responder.class);
        if ([name containsString:@"AWELiveNewPreStreamViewController"] ||
            [name containsString:@"AWELivePreStream"]) {
            return YES;
        }
    }
    return NO;
}

BOOL DYFSIsLivePreStreamPlayer(id playerController) {
    if (!playerController) return NO;

    NSString *ownName = NSStringFromClass([playerController class]);
    if ([ownName containsString:@"AWELiveNewPreStreamViewController"] ||
        [ownName containsString:@"AWELivePreStream"]) {
        return YES;
    }

    if ([playerController isKindOfClass:UIViewController.class]) {
        UIViewController *cursor = (UIViewController *)playerController;
        for (NSUInteger depth = 0; cursor && depth < 20; depth++, cursor = cursor.parentViewController) {
            NSString *name = NSStringFromClass(cursor.class);
            if ([name containsString:@"AWELiveNewPreStreamViewController"] ||
                [name containsString:@"AWELivePreStream"]) {
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
        if ([name containsString:@"AWELiveNewPreStreamViewController"] ||
            [name containsString:@"AWELivePreStream"]) {
            return YES;
        }
    }

    return NO;
}

BOOL DYFSIsActualLiveRoomContext(UIView *view) {
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
        if ([name containsString:@"AWEAwemeDetailTableViewController"] ||
            [name containsString:@"AWEAwemeDetailCellViewController"] ||
            [name containsString:@"AWEMixVideoPanelDetailTableViewController"]) {
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
    if ([baseName containsString:@"AWEFeedCellViewController"]) return YES;

    // Some live cards wrap the interaction controller in a different base class.
    // Keep the fallback restricted to an attached feed interaction controller;
    // the caller separately excludes profile, pre-stream and actual live-room contexts.
    id model = DYFSSafeValueForKey(base, @"model");
    if (!model) model = DYFSSafeValueForKey(controller, @"model");
    BOOL hasLiveSignal = DYFSModelHasLiveSignal(model);

    UIViewController *cursor = controller.parentViewController;
    for (NSUInteger depth = 0; cursor && depth < 12; depth++, cursor = cursor.parentViewController) {
        NSString *name = NSStringFromClass(cursor.class);
        if ([name containsString:@"AWEFeedCellViewController"]) return YES;
    }

    return hasLiveSignal && controller.isViewLoaded && controller.view.window != nil &&
        controller.view.superview != nil;
}
