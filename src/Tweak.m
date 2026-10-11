#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>

static NSString * const DYFSBundleID = @"com.ss.iphone.ugc.Aweme";
static NSString * const DYFSTestedVersion = @"40.7.0";
static NSString * const DYFSEnabledKey = @"com.dy.fullscreen.enabled";
static BOOL DYFSInstalledFeed = NO;
static BOOL DYFSInstalledStory = NO;
static BOOL DYFSInstalledSidebarIcon = NO;
static BOOL DYFSInstalledSidebarRight = NO;
static NSUInteger DYFSInstallAttempts = 0;
static BOOL DYFSSchedulePending = NO;
static NSUInteger DYFSLayoutFixCount = 0;
static BOOL DYFSFoundHomeInteractionView = NO;
static BOOL DYFSSettingsEntryVisible = NO;
static NSString *DYFSLastInstallSummary = @"尚未检测";
static IMP DYFSOriginalFeedLayout = NULL;
static IMP DYFSOriginalStoryLayout = NULL;
static IMP DYFSOriginalSidebarIconMove = NULL;
static IMP DYFSOriginalSidebarRightMove = NULL;

static void DYFSLog(NSString *message) {
    NSLog(@"[DY.FullScreen] %@", message);
}

static BOOL DYFSIsEnabled(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:DYFSEnabledKey] == nil) return YES;
    return [defaults boolForKey:DYFSEnabledKey];
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



static NSUInteger DYFSLayoutHookCount(void) {
    return (DYFSInstalledFeed ? 1 : 0) + (DYFSInstalledStory ? 1 : 0);
}

static NSUInteger DYFSSidebarHookCount(void) {
    return (DYFSInstalledSidebarIcon ? 1 : 0) + (DYFSInstalledSidebarRight ? 1 : 0);
}

static UIView *DYFSFindSubviewOfClass(UIView *root, NSString *className, NSUInteger depth) {
    if (!root || depth > 14) return nil;
    if ([NSStringFromClass(root.class) isEqualToString:className]) return root;
    for (UIView *subview in root.subviews) {
        UIView *match = DYFSFindSubviewOfClass(subview, className, depth + 1);
        if (match) return match;
    }
    return nil;
}

static CGFloat DYFSBottomTabBarHeight(UIView *view) {
    UIWindow *window = view.window;
    if (!window) return 49.0;
    UIView *tabBar = DYFSFindSubviewOfClass(window, @"AWENormalModeTabBar", 0);
    CGFloat measured = CGRectGetHeight(tabBar.bounds);
    if (tabBar && isfinite(measured) && measured >= 30.0 && measured < CGRectGetHeight(window.bounds)) {
        return measured;
    }
    return 49.0 + MAX(0.0, window.safeAreaInsets.bottom);
}

static void DYFSRequestRelayout(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            [window setNeedsLayout];
            for (UIView *subview in [window.subviews copy]) {
                [subview setNeedsLayout];
            }
        }
    });
}

static NSString *DYFSStatusText(void) {
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"未知";
    return [NSString stringWithFormat:
        @"抖音版本：%@\n全屏开关：%@\n首页列表 Hook：%@\n互动容器 Hook：%@\n设置入口 Hook：%lu/2\n已识别首页互动视图：%@\n本次运行的布局调整次数：%lu\n\n若 Hook 显示未安装，请确认 TrollFools 注入的是本次构建的 DY.FullScreen.dylib。若 Hook 已安装但没有布局调整，说明当前页面的视图层级或内部类名与适配逻辑不一致。",
        version, DYFSIsEnabled() ? @"开启" : @"关闭",
        DYFSInstalledFeed ? @"已安装" : @"未找到类",
        DYFSInstalledStory ? @"已安装" : @"未找到类",
        (unsigned long)DYFSSidebarHookCount(),
        DYFSFoundHomeInteractionView ? @"是" : @"否",
        (unsigned long)DYFSLayoutFixCount];
}

static UIViewController *DYFSFindViewController(UIView *view) {
    UIResponder *responder = view;
    for (NSUInteger depth = 0; responder && depth < 40; depth++) {
        if ([responder isKindOfClass:UIViewController.class]) return (UIViewController *)responder;
        responder = responder.nextResponder;
    }
    return nil;
}

static UIViewController *DYFSActiveTopViewController(void) {
    UIWindow *activeWindow = nil;
    for (UIWindow *window in UIApplication.sharedApplication.windows.reverseObjectEnumerator) {
        if (window.isKeyWindow) {
            activeWindow = window;
            break;
        }
    }
    if (!activeWindow) activeWindow = UIApplication.sharedApplication.windows.lastObject;
    UIViewController *controller = activeWindow.rootViewController;
    while (controller) {
        if (controller.presentedViewController) {
            controller = controller.presentedViewController;
        } else if ([controller isKindOfClass:UINavigationController.class] &&
                   ((UINavigationController *)controller).topViewController) {
            controller = ((UINavigationController *)controller).topViewController;
        } else if ([controller isKindOfClass:UITabBarController.class] &&
                   ((UITabBarController *)controller).selectedViewController) {
            controller = ((UITabBarController *)controller).selectedViewController;
        } else {
            break;
        }
    }
    return controller;
}

static void DYFSOpenSettings(id sender);

@interface DYFSSettingsActionTarget : NSObject
+ (instancetype)sharedTarget;
- (void)openSettings:(id)sender;
@end

@implementation DYFSSettingsActionTarget
+ (instancetype)sharedTarget {
    static DYFSSettingsActionTarget *target = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        target = [[DYFSSettingsActionTarget alloc] init];
    });
    return target;
}
- (void)openSettings:(id)sender {
    DYFSOpenSettings(sender);
}
@end

@interface DYFSSettingsViewController : UIViewController
@property(nonatomic, strong) UISwitch *enabledSwitch;
@property(nonatomic, strong) UILabel *statusLabel;
@end

@implementation DYFSSettingsViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"DY.FullScreen";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"首页全屏";
    titleLabel.font = [UIFont boldSystemFontOfSize:24];
    titleLabel.textColor = UIColor.labelColor;

    UILabel *descriptionLabel = [[UILabel alloc] init];
    descriptionLabel.text = @"开启后尝试让首页视频列表铺满容器，并按底部导航栏高度调整互动容器。适配目标为抖音 40.7.0。";
    descriptionLabel.font = [UIFont systemFontOfSize:14];
    descriptionLabel.textColor = UIColor.secondaryLabelColor;
    descriptionLabel.numberOfLines = 0;

    UILabel *switchTitle = [[UILabel alloc] init];
    switchTitle.text = @"启用首页全屏";
    switchTitle.font = [UIFont systemFontOfSize:16];
    switchTitle.textColor = UIColor.labelColor;

    self.enabledSwitch = [[UISwitch alloc] init];
    self.enabledSwitch.on = DYFSIsEnabled();
    [self.enabledSwitch addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];

    UIStackView *switchRow = [[UIStackView alloc] initWithArrangedSubviews:@[switchTitle, self.enabledSwitch]];
    switchRow.axis = UILayoutConstraintAxisHorizontal;
    switchRow.alignment = UIStackViewAlignmentCenter;
    switchRow.distribution = UIStackViewDistributionEqualSpacing;

    UILabel *diagnosticsTitle = [[UILabel alloc] init];
    diagnosticsTitle.text = @"运行诊断";
    diagnosticsTitle.font = [UIFont boldSystemFontOfSize:17];
    diagnosticsTitle.textColor = UIColor.labelColor;

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.font = [UIFont systemFontOfSize:13];
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.statusLabel.text = DYFSStatusText();

    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [closeButton setTitle:@"完成" forState:UIControlStateNormal];
    closeButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [closeButton addTarget:self action:@selector(closeSettings) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        titleLabel, descriptionLabel, switchRow, diagnosticsTitle, self.statusLabel, closeButton
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 18;
    stack.alignment = UIStackViewAlignmentFill;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],
        [stack.topAnchor constraintEqualToAnchor:safe.topAnchor constant:24],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:safe.bottomAnchor constant:-20]
    ]];
    self.preferredContentSize = CGSizeMake(360, 430);
}

- (void)enabledChanged:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:DYFSEnabledKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    DYFSLog(sender.isOn ? @"homepage full-screen enabled" : @"homepage full-screen disabled");
    DYFSRequestRelayout();
    self.statusLabel.text = DYFSStatusText();
}

- (void)closeSettings {
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end

static void DYFSOpenSettings(id sender) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *senderView = [sender isKindOfClass:UIView.class] ? (UIView *)sender : nil;
        UIViewController *target = senderView ? DYFSFindViewController(senderView) : nil;
        if (!target) target = DYFSActiveTopViewController();
        if (!target) {
            DYFSLog(@"cannot present settings: no visible view controller");
            return;
        }
        if ([target isKindOfClass:DYFSSettingsViewController.class]) return;
        DYFSSettingsViewController *settings = [[DYFSSettingsViewController alloc] init];
        settings.modalPresentationStyle = UIModalPresentationPageSheet;
        [target presentViewController:settings animated:YES completion:nil];
    });
}

static void DYFSInstallSettingsEntry(UIView *settingsIcon) {
    if (!settingsIcon || ![settingsIcon.accessibilityLabel isEqualToString:@"设置"]) return;
    UIView *targetSuperView = settingsIcon.superview.superview.superview ?: settingsIcon.superview ?: settingsIcon;
    UIButton *oldButton = (UIButton *)[targetSuperView viewWithTag:420740];
    if (oldButton) {
        DYFSSettingsEntryVisible = YES;
        return;
    }

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = 420740;
    button.accessibilityLabel = @"DY.FullScreen 设置入口";
    [button setTitle:@"全屏" forState:UIControlStateNormal];
    [button setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    button.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.12];
    button.layer.cornerRadius = 8.0;
    button.clipsToBounds = YES;
    CGRect frame = settingsIcon.frame;
    button.frame = CGRectMake(frame.origin.x + frame.size.width - 40.0 - 2.0, 8.0, 60.0, 32.0);
    button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [button addTarget:[DYFSSettingsActionTarget sharedTarget]
               action:@selector(openSettings:)
     forControlEvents:UIControlEventTouchUpInside];
    [targetSuperView addSubview:button];
    DYFSSettingsEntryVisible = YES;
    DYFSLog(@"installed DY.FullScreen button next to Douyin Settings");
}

static void DYFSScanForSettingsEntry(UIView *root, NSUInteger depth) {
    if (!root || depth > 18 || DYFSSettingsEntryVisible) return;
    NSString *className = NSStringFromClass(root.class);
    if (([className isEqualToString:@"AWELeftSideBarTopIconHorizontalView"] ||
         [className isEqualToString:@"AWELeftSideBarTopRightLayoutView"]) &&
        [root.accessibilityLabel isEqualToString:@"设置"]) {
        DYFSInstallSettingsEntry(root);
        if (DYFSSettingsEntryVisible) return;
    }
    for (UIView *subview in [root.subviews copy]) {
        DYFSScanForSettingsEntry(subview, depth + 1);
        if (DYFSSettingsEntryVisible) return;
    }
}


static void DYFSFeedTableLayout(id self, SEL cmd) {
    if (DYFSOriginalFeedLayout) ((void (*)(id, SEL))DYFSOriginalFeedLayout)(self, cmd);
    if (!DYFSIsEnabled()) return;

    UIView *view = (UIView *)self;
    UIView *parent = view.superview;
    if (!parent || DYFSInProfileContext(view)) return;
    CGRect frame = view.frame;
    CGFloat targetHeight = CGRectGetHeight(parent.bounds);
    if (!isfinite(targetHeight) || targetHeight <= 1.0 ||
        fabs(CGRectGetHeight(frame) - targetHeight) <= 0.5) return;

    CGFloat oldHeight = CGRectGetHeight(frame);
    frame.size.height = targetHeight;
    view.frame = frame;
    DYFSLayoutFixCount++;
    DYFSLog([NSString stringWithFormat:@"AWEFeedTableView height %.2f -> %.2f", oldHeight, targetHeight]);
}

static void DYFSStoryLayout(id self, SEL cmd) {
    if (DYFSOriginalStoryLayout) ((void (*)(id, SEL))DYFSOriginalStoryLayout)(self, cmd);
    if (!DYFSIsEnabled()) return;

    UIView *container = (UIView *)self;
    if (DYFSInProfileContext(container) || container.subviews.count == 2) return;

    BOOL isHome = NO;
    @try {
        id value = [container valueForKey:@"enableEnterProfile"];
        if ([value respondsToSelector:@selector(boolValue)]) isHome = [value boolValue];
    } @catch (__unused NSException *exception) {
        isHome = NO;
    }
    if (!isHome) return;

    for (UIView *subview in [container.subviews copy]) {
        UIResponder *responder = subview.nextResponder;
        NSString *responderName = responder ? NSStringFromClass(responder.class) : @"";
        if (![responderName containsString:@"AWEPlayInteractionViewController"]) continue;

        id baseViewController = nil;
        @try {
            baseViewController = [responder valueForKey:@"awemeBaseViewController"];
        } @catch (__unused NSException *exception) {
            baseViewController = nil;
        }
        NSString *baseName = baseViewController ? NSStringFromClass([baseViewController class]) : @"";
        if (![baseName containsString:@"AWEFeedCellViewController"]) continue;

        DYFSFoundHomeInteractionView = YES;
        UIView *parent = subview.superview;
        if (!parent) continue;
        CGFloat parentHeight = CGRectGetHeight(parent.bounds);
        CGFloat tabBarHeight = DYFSBottomTabBarHeight(subview);
        CGFloat targetHeight = parentHeight - tabBarHeight;
        if (!isfinite(targetHeight) || targetHeight <= 1.0) continue;

        CGRect frame = subview.frame;
        if (fabs(CGRectGetHeight(frame) - targetHeight) <= 0.5) continue;
        CGFloat oldHeight = CGRectGetHeight(frame);
        frame.size.height = targetHeight;
        subview.frame = frame;
        DYFSLayoutFixCount++;
        DYFSLog([NSString stringWithFormat:
            @"home interaction container height %.2f -> %.2f (parent %.2f, tab bar %.2f)",
            oldHeight, targetHeight, parentHeight, tabBarHeight]);
    }
}

static void DYFSLeftSidebarIconDidMove(id self, SEL cmd) {
    if (DYFSOriginalSidebarIconMove) ((void (*)(id, SEL))DYFSOriginalSidebarIconMove)(self, cmd);
    UIView *view = (UIView *)self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        DYFSInstallSettingsEntry(view);
    });
}

static void DYFSLeftSidebarRightDidMove(id self, SEL cmd) {
    if (DYFSOriginalSidebarRightMove) ((void (*)(id, SEL))DYFSOriginalSidebarRightMove)(self, cmd);
    UIView *view = (UIView *)self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        DYFSInstallSettingsEntry(view);
    });
}

static void DYFSInstallHooks(void) {
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"";
    if (![bundle isEqualToString:DYFSBundleID]) return;

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

    cls = NSClassFromString(@"AWELeftSideBarTopIconHorizontalView");
    if (!DYFSInstalledSidebarIcon && cls) {
        DYFSInstalledSidebarIcon = DYFSInstallHook(cls, @selector(didMoveToSuperview),
                    (IMP)DYFSLeftSidebarIconDidMove, &DYFSOriginalSidebarIconMove);
    }

    cls = NSClassFromString(@"AWELeftSideBarTopRightLayoutView");
    if (!DYFSInstalledSidebarRight && cls) {
        DYFSInstalledSidebarRight = DYFSInstallHook(cls, @selector(didMoveToSuperview),
                    (IMP)DYFSLeftSidebarRightDidMove, &DYFSOriginalSidebarRightMove);
    }


    if (!DYFSSettingsEntryVisible) {
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            DYFSScanForSettingsEntry(window, 0);
            if (DYFSSettingsEntryVisible) break;
        }
    }

    NSString *summary = [NSString stringWithFormat:@"layout hooks %lu/2; sidebar hooks %lu/2",
                         (unsigned long)DYFSLayoutHookCount(), (unsigned long)DYFSSidebarHookCount()];
    if (![summary isEqualToString:DYFSLastInstallSummary]) {
        DYFSLastInstallSummary = [summary copy];
        DYFSLog(summary);
    }
}

static void DYFSScheduleHooks(void) {
    if (DYFSSchedulePending || DYFSInstallAttempts >= 60) return;
    DYFSSchedulePending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        DYFSSchedulePending = NO;
        DYFSInstallAttempts++;
        DYFSInstallHooks();

        BOOL layoutsInstalled = DYFSInstalledFeed && DYFSInstalledStory;
        BOOL sidebarInstalled = DYFSInstalledSidebarIcon || DYFSInstalledSidebarRight;
        if ((!layoutsInstalled || !sidebarInstalled) && DYFSInstallAttempts < 60) {
            DYFSScheduleHooks();
        }
    });
}

__attribute__((constructor)) static void DYFSConstructor(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:DYFSBundleID]) return;

        DYFSLog(@"loaded into Douyin");
        NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown";
        if (![version hasPrefix:DYFSTestedVersion]) {
            DYFSLog([NSString stringWithFormat:@"tested for %@; current app version is %@", DYFSTestedVersion, version]);
        }
        if ([NSUserDefaults.standardUserDefaults objectForKey:DYFSEnabledKey] == nil) {
            [NSUserDefaults.standardUserDefaults setBool:YES forKey:DYFSEnabledKey];
        }
        DYFSScheduleHooks();
    }
}
