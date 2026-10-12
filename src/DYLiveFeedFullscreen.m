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

// 探测子树里是否有「进入直播间」文案（用于定位按钮组容器）
static BOOL DYFSLiveCardSubtreeHasEnterLiveText(UIView *view, NSUInteger depth) {
    if (!view || depth > 8) return NO;
    if ([view isKindOfClass:UILabel.class] &&
        [((UILabel *)view).text containsString:@"进入直播间"]) return YES;
    if ([view isKindOfClass:UIButton.class] &&
        ([((UIButton *)view).currentTitle containsString:@"进入直播间"] ||
         [((UIButton *)view).accessibilityLabel containsString:@"进入直播间"])) return YES;
    NSString *a11y = view.accessibilityLabel ?: @"";
    if ([a11y containsString:@"进入直播间"]) return YES;
    for (UIView *sub in view.subviews) {
        if (DYFSLiveCardSubtreeHasEnterLiveText(sub, depth + 1)) return YES;
    }
    return NO;
}

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
    CGFloat cellWidth = CGRectGetWidth(cell.bounds);
    if (cellWidth < 100.0 || cellHeight < 160.0) return;

    // 1) 观众视图撑满整张卡片，视频不留黑边。
    //    内容的位置不依赖抖音的内部布局，由下面两步自己修正。
    if (!CGRectEqualToRect(controllerView.frame, cell.bounds)) {
        controllerView.frame = cell.bounds;
    }

    CGFloat tabBarHeight = DYFSBottomTabBarHeight(cell);
    CGFloat limitY = cellHeight - tabBarHeight;

    for (UIView *sub in [controllerView.subviews copy]) {
        if (sub.hidden || sub.alpha <= 0.01) continue;

        CGFloat sw = CGRectGetWidth(sub.frame), sh = CGRectGetHeight(sub.frame);
        // 铺满容器的多半是视频层或背景层，不参与修正。
        if (cellWidth > 0 && cellHeight > 0 && sw >= cellWidth * 0.95 && sh >= cellHeight * 0.90) continue;
        if (!DYFSLiveCardSubtreeHasContent(sub, 0)) continue;

        // 2) 账号 / 文案：底边对齐到底栏上方，不随全屏居中。
        CGFloat delta = CGRectGetMaxY(sub.frame) - limitY;
        if (delta > 1.0) {
            CGRect frame = sub.frame;
            frame.origin.y -= delta;
            if (CGRectGetMinY(frame) >= -1.0) sub.frame = frame;
        }

        // 3) 「进入直播间 + 横屏」按钮组：整体水平居中。
        if (DYFSLiveCardSubtreeHasEnterLiveText(sub, 0)) {
            CGFloat dx = (cellWidth - CGRectGetWidth(sub.frame)) / 2.0 - CGRectGetMinX(sub.frame);
            if (fabs(dx) > 0.5) {
                CGRect frame = sub.frame;
                frame.origin.x += dx;
                sub.frame = frame;
            }
        }
    }

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
