//
// DYLiveFeedFullscreen.m
// DY.FullScreen
//
// Narrow integration for Douyin's information-feed live card.
// Keep this hook scoped to IESLiveInnerFeedLiveRoomCell; never target the
// full live-room controller or the pre-stream preview route.
//

#import "DYLiveFeedFullscreen.h"
#import "DYFSCommon.h"
#import "DYFSLayout.h"
#import <objc/runtime.h>
#import <objc/message.h>

static IMP DYFSOriginalLiveFeedCellLayout = NULL;
static BOOL DYFSInstalledLiveFeedCellLayout = NO;

static BOOL DYFSIsPreStreamView(UIView *view) {
    for (UIView *cursor = view; cursor; cursor = cursor.superview) {
        NSString *name = NSStringFromClass(cursor.class);
        if ([name containsString:@"AWELiveNewPreStreamViewController"] ||
            [name containsString:@"AWELivePreStream"]) return YES;
    }
    UIResponder *responder = view;
    for (NSUInteger depth = 0; responder && depth < 40; depth++, responder = responder.nextResponder) {
        NSString *name = NSStringFromClass(responder.class);
        if ([name containsString:@"AWELiveNewPreStreamViewController"] ||
            [name containsString:@"AWELivePreStream"]) return YES;
    }
    return NO;
}

@implementation DYLiveFeedFullscreen

+ (void)load {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[self sharedInstance] installHooksIfNeeded];
    });
}

+ (instancetype)sharedInstance {
    static DYLiveFeedFullscreen *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[self alloc] init];
    });
    return manager;
}

- (BOOL)isLiveFeedView:(UIView *)view {
    if (!view || DYFSIsPreStreamView(view)) return NO;
    // A strict class match avoids unrelated live-room and preview controllers.
    for (UIView *cursor = view; cursor; cursor = cursor.superview) {
        if ([NSStringFromClass(cursor.class) isEqualToString:@"IESLiveInnerFeedLiveRoomCell"]) return YES;
    }
    return NO;
}

- (void)processLiveFeedView:(UIView *)view {
    if (![self isLiveFeedView:view]) return;

    UIView *cell = view;
    while (cell && ![NSStringFromClass(cell.class) isEqualToString:@"IESLiveInnerFeedLiveRoomCell"]) {
        cell = cell.superview;
    }
    if (!cell) return;

    id audienceController = nil;
    @try {
        SEL selector = NSSelectorFromString(@"audienceVC");
        if ([cell respondsToSelector:selector]) {
            audienceController = ((id (*)(id, SEL))objc_msgSend)(cell, selector);
        }
        if (!audienceController) audienceController = [cell valueForKey:@"audienceVC"];
    } @catch (__unused NSException *exception) {
        return;
    }

    UIView *controllerView = [audienceController isKindOfClass:UIViewController.class]
        ? ((UIViewController *)audienceController).view : nil;
    // Only size a controller view that is already a direct child of the card.
    // Never reparent it or touch the formal live-room / pre-stream hierarchy.
    if (![controllerView isKindOfClass:UIView.class] || controllerView.superview != cell) return;

    CGFloat cellHeight = CGRectGetHeight(cell.bounds);
    CGFloat currentHeight = CGRectGetHeight(controllerView.frame);
    if (CGRectGetWidth(cell.bounds) < 100.0 || cellHeight < 160.0 || currentHeight <= 1.0) return;

    // 只补偿「差一个底栏高度」或「差两个底栏高度」两种情况，其余一律交给抖音
    // 自己的布局计算（这与 DYYY 对播放器 contentView 的处理方式一致）。
    //
    // 千万不要无条件把观众视图拉伸到 cell.bounds：那样会绕过抖音内部的布局，
    // 用 frame 定位的标题文案与「进入直播间」按钮不会跟着重排，表现为不居中。
    CGFloat tabBarHeight = DYFSBottomTabBarHeight(cell);
    CGFloat tolerance = MAX(1.0, tabBarHeight * 0.03);
    CGFloat diff = cellHeight - currentHeight;
    CGFloat targetHeight = currentHeight;

    if (fabs(diff - tabBarHeight) <= tolerance) {
        targetHeight = cellHeight;
    } else if (fabs(diff - tabBarHeight * 2.0) <= tolerance) {
        targetHeight = cellHeight - tabBarHeight;
    } else {
        return;
    }

    if (fabs(currentHeight - targetHeight) <= 0.5) return;

    CGRect frame = controllerView.frame;
    frame.size.height = targetHeight;
    controllerView.frame = frame;
    [controllerView setNeedsLayout];
    [controllerView layoutIfNeeded];
}

- (void)installHooksIfNeeded {
    if (DYFSInstalledLiveFeedCellLayout) return;
    Class cls = NSClassFromString(kDYFSClassLiveFeedCell);
    SEL selector = @selector(layoutSubviews);
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method) return;

    const char *types = method_getTypeEncoding(method);
    IMP original = method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(^(__unsafe_unretained id object) {
        if (DYFSOriginalLiveFeedCellLayout) {
            ((void (*)(id, SEL))DYFSOriginalLiveFeedCellLayout)(object, selector);
        }
        UIView *cell = [object isKindOfClass:UIView.class] ? (UIView *)object : nil;
        if (cell) [[DYLiveFeedFullscreen sharedInstance] processLiveFeedView:cell];
    });
    if (class_addMethod(cls, selector, replacement, types)) {
        DYFSOriginalLiveFeedCellLayout = original;
    } else {
        DYFSOriginalLiveFeedCellLayout = method_setImplementation(method, replacement);
    }
    DYFSInstalledLiveFeedCellLayout = (DYFSOriginalLiveFeedCellLayout != replacement);
    NSLog(@"[DY.FullScreen] live-feed cell layout hook %@", DYFSInstalledLiveFeedCellLayout ? @"installed" : @"unavailable");
}

@end
