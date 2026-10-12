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

// 判断子视图是否承载了可见内容（账号、文案、按钮等）。
// 纯视频层 / 背景层没有文字也没有控件，返回 NO，避免被误移。
static BOOL DYFSLiveCardSubtreeHasContent(UIView *view, NSUInteger depth) {
    if (!view || depth > 8) return NO;
    if ([view isKindOfClass:UIControl.class]) return YES;
    if ([view isKindOfClass:UIButton.class]) return YES;
    if ([view isKindOfClass:UITextField.class]) return YES;
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        if (label.text.length > 0 || label.attributedText.length > 0) return YES;
    }
    for (UIView *sub in view.subviews) {
        if (DYFSLiveCardSubtreeHasContent(sub, depth + 1)) return YES;
    }
    return NO;
}

// 信息流直播卡片里的账号、文案与「进入直播间」按钮不需要居中，
// 而是应该停在底栏上方：把底部越过底栏的内容视图上移回去。
// fullHeight 用卡片（cell）的高度而不是观众视图自身高度，
// 因为观众视图可能尚未被撑满。
static void DYFSKeepLiveCardContentAboveTabBar(UIView *container, CGFloat tabBarHeight, CGFloat fullHeight) {
    if (!container || tabBarHeight <= 0 || fullHeight <= 0) return;
    CGFloat limitY = fullHeight - tabBarHeight;
    if (limitY <= 0) return;

    CGFloat cw = CGRectGetWidth(container.bounds);
    CGFloat ch = CGRectGetHeight(container.bounds);

    for (UIView *sub in [container.subviews copy]) {
        if (sub.hidden || sub.alpha <= 0.01) continue;

        CGFloat sw = CGRectGetWidth(sub.frame), sh = CGRectGetHeight(sub.frame);
        // 铺满容器的多半是视频层或背景层，不参与上移。
        if (cw > 0 && ch > 0 && sw >= cw * 0.95 && sh >= ch * 0.90) continue;
        if (!DYFSLiveCardSubtreeHasContent(sub, 0)) continue;

        CGFloat delta = CGRectGetMaxY(sub.frame) - limitY;
        if (delta <= 1.0) continue;

        CGRect frame = sub.frame;
        frame.origin.y -= delta;
        if (CGRectGetMinY(frame) < -1.0) continue;   // 别把它顶出屏幕外
        sub.frame = frame;
    }
}

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

    if (fabs(currentHeight - targetHeight) > 0.5) {
        CGRect frame = controllerView.frame;
        frame.size.height = targetHeight;
        controllerView.frame = frame;
    }

    // 高度补偿之后，再把账号 / 文案 / 按钮顶到底栏上方。
    DYFSKeepLiveCardContentAboveTabBar(controllerView, tabBarHeight, cellHeight);

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
