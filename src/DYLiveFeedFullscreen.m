//
// DYLiveFeedFullscreen.m
// DY.FullScreen
//
// Narrow integration for Douyin's information-feed live card.
// Keep this hook scoped to IESLiveInnerFeedLiveRoomCell; never target the
// full live-room controller or the pre-stream preview route.
//

#import "DYLiveFeedFullscreen.h"
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
        [[self sharedInstance] installLiveFeedCellHookIfAvailable];
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
    CGRect target = cell.bounds;
    if (CGRectGetWidth(target) < 100.0 || CGRectGetHeight(target) < 160.0) return;
    if (!CGRectEqualToRect(controllerView.frame, target)) controllerView.frame = target;
    [controllerView setNeedsLayout];
    [controllerView layoutIfNeeded];
}

- (void)installLiveFeedCellHookIfAvailable {
    if (DYFSInstalledLiveFeedCellLayout) return;
    Class cls = NSClassFromString(@"IESLiveInnerFeedLiveRoomCell");
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
