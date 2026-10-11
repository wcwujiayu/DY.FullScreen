#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>

static NSString * const DYFSBundleID = @"com.ss.iphone.ugc.Aweme";
static NSString * const DYFSTestedVersion = @"40.7.0";
static BOOL DYFSInstalledFeed = NO;
static BOOL DYFSInstalledStory = NO;
static BOOL DYFSInstalledPlayer = NO;
static BOOL DYFSInstalledMerge = NO;
static NSUInteger DYFSInstallAttempts = 0;
static BOOL DYFSSchedulePending = NO;
static IMP DYFSOriginalFeedLayout = NULL;
static IMP DYFSOriginalStoryLayout = NULL;
static IMP DYFSOriginalPlayerLayout = NULL;
static IMP DYFSOriginalMergeLayout = NULL;

static void DYFSLog(NSString *message) {
    NSLog(@"[DY.FullScreen] %@", message);
}

static BOOL DYFSInProfileContext(UIView *view) {
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

static void DYFSFillHeight(UIView *view, NSString *reason) {
    UIView *parent = view.superview;
    if (!parent || view.hidden || DYFSInProfileContext(view)) return;

    // Use the parent's local coordinate space. Deliberately avoid global offsets
    // and transform changes because the reported issue is whole-overlay vertical drift.
    CGFloat targetHeight = CGRectGetHeight(parent.bounds);
    if (!isfinite(targetHeight) || targetHeight <= 1.0) return;

    CGRect frame = view.frame;
    if (fabs(CGRectGetHeight(frame) - targetHeight) <= 0.5) return;
    frame.size.height = targetHeight;
    view.frame = frame;

    DYFSLog([NSString stringWithFormat:@"%@ height %.2f -> %.2f; parent=%@ bounds=%@",
             reason, CGRectGetHeight(view.frame), targetHeight,
             NSStringFromClass(parent.class), NSStringFromCGRect(parent.bounds)]);
}

static BOOL DYFSInstallHook(Class cls, SEL selector, IMP replacement, IMP *originalOut) {
    if (!cls || !selector || !replacement || !originalOut) return NO;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return NO;

    const char *types = method_getTypeEncoding(method);
    IMP original = method_getImplementation(method);
    if (class_addMethod(cls, selector, replacement, types)) {
        *originalOut = original;
        return YES;
    }

    Method ownMethod = class_getInstanceMethod(cls, selector);
    IMP previous = method_setImplementation(ownMethod, replacement);
    *originalOut = previous;
    return previous != replacement;
}

static void DYFSFeedTableLayout(id self, SEL cmd) {
    if (DYFSOriginalFeedLayout) ((void (*)(id, SEL))DYFSOriginalFeedLayout)(self, cmd);
    DYFSFillHeight((UIView *)self, @"AWEFeedTableView");
}

static void DYFSStoryLayout(id self, SEL cmd) {
    if (DYFSOriginalStoryLayout) ((void (*)(id, SEL))DYFSOriginalStoryLayout)(self, cmd);
    UIView *container = (UIView *)self;
    if (DYFSInProfileContext(container)) return;
    for (UIView *subview in [container.subviews copy]) {
        UIResponder *responder = subview.nextResponder;
        NSString *name = responder ? NSStringFromClass(responder.class) : @"";
        if ([name containsString:@"AWEPlayInteractionViewController"]) {
            DYFSFillHeight(subview, @"home interaction overlay");
        }
    }
}

static void DYFSPlayerLayout(id self, SEL cmd) {
    if (DYFSOriginalPlayerLayout) ((void (*)(id, SEL))DYFSOriginalPlayerLayout)(self, cmd);
    SEL selector = NSSelectorFromString(@"contentView");
    if ([self respondsToSelector:selector]) {
        id view = ((id (*)(id, SEL))objc_msgSend)(self, selector);
        if ([view isKindOfClass:UIView.class]) DYFSFillHeight(view, @"feed player contentView");
    }
}

static void DYFSMergeLayout(id self, SEL cmd) {
    if (DYFSOriginalMergeLayout) ((void (*)(id, SEL))DYFSOriginalMergeLayout)(self, cmd);
    SEL selector = NSSelectorFromString(@"contentView");
    if ([self respondsToSelector:selector]) {
        id view = ((id (*)(id, SEL))objc_msgSend)(self, selector);
        if ([view isKindOfClass:UIView.class]) DYFSFillHeight(view, @"merge player contentView");
    }
}

static void DYFSInstallHooks(void) {
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"";
    if (![bundle isEqualToString:DYFSBundleID]) return;

    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown";
    if (![version hasPrefix:DYFSTestedVersion]) {
        DYFSLog([NSString stringWithFormat:@"Designed for %@; current app reports %@.", DYFSTestedVersion, version]);
    }

    Class cls = NSClassFromString(@"AWEFeedTableView");
    if (!DYFSInstalledFeed && cls) {
        DYFSInstalledFeed = DYFSInstallHook(cls, @selector(layoutSubviews),
                                            (IMP)DYFSFeedTableLayout, &DYFSOriginalFeedLayout);
    }

    cls = NSClassFromString(@"AWEStoryContainerCollectionView");
    if (!DYFSInstalledStory && cls) {
        DYFSInstalledStory = DYFSInstallHook(cls, @selector(layoutSubviews),
                                             (IMP)DYFSStoryLayout, &DYFSOriginalStoryLayout);
    }

    cls = NSClassFromString(@"AWEDPlayerFeedPlayerViewController");
    if (!DYFSInstalledPlayer && cls) {
        DYFSInstalledPlayer = DYFSInstallHook(cls, @selector(viewDidLayoutSubviews),
                                              (IMP)DYFSPlayerLayout, &DYFSOriginalPlayerLayout);
    }

    cls = NSClassFromString(@"AWEDPlayerViewController_Merge");
    if (!DYFSInstalledMerge && cls) {
        DYFSInstalledMerge = DYFSInstallHook(cls, @selector(viewDidLayoutSubviews),
                                             (IMP)DYFSMergeLayout, &DYFSOriginalMergeLayout);
    }

    NSUInteger installed = (DYFSInstalledFeed ? 1 : 0) + (DYFSInstalledStory ? 1 : 0) +
                           (DYFSInstalledPlayer ? 1 : 0) + (DYFSInstalledMerge ? 1 : 0);
    DYFSLog([NSString stringWithFormat:@"runtime hook groups installed: %lu/4",
             (unsigned long)installed]);
}

static void DYFSScheduleHooks(void) {
    if (DYFSSchedulePending || DYFSInstallAttempts >= 6) return;
    DYFSSchedulePending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        DYFSSchedulePending = NO;
        DYFSInstallAttempts++;
        DYFSInstallHooks();
        BOOL allInstalled = DYFSInstalledFeed && DYFSInstalledStory &&
                            DYFSInstalledPlayer && DYFSInstalledMerge;
        if (!allInstalled && DYFSInstallAttempts < 6) DYFSScheduleHooks();
    });
}

__attribute__((constructor)) static void DYFSConstructor(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:DYFSBundleID]) return;
        DYFSLog(@"loaded into Douyin");
        DYFSScheduleHooks();
    }
}
