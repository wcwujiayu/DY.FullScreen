#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>

static NSString * const DYFSBundleID = @"com.ss.iphone.ugc.Aweme";
static NSString * const DYFSTestedVersion = @"40.7.0";
static NSString * const DYFSEnabledKey = @"com.dy.fullscreen.enabled";
static BOOL DYFSInstalledFeed = NO;
static BOOL DYFSInstalledSidebarIcon = NO;
static BOOL DYFSInstalledSidebarRight = NO;
static BOOL DYFSInstalledTabBarLayout = NO;
static BOOL DYFSInstalledTabBarHidden = NO;
static BOOL DYFSInstalledProgressContainer = NO;
static NSUInteger DYFSInstallAttempts = 0;
static BOOL DYFSSchedulePending = NO;
static NSUInteger DYFSLayoutFixCount = 0;
static NSUInteger DYFSTabBarApplyCount = 0;
static BOOL DYFSLastHomeTabSelected = NO;
static BOOL DYFSLastTabBackgroundHidden = NO;
static BOOL DYFSSettingsEntryVisible = NO;
static NSString *DYFSLastInstallSummary = @"尚未检测";
static IMP DYFSOriginalFeedLayout = NULL;
static IMP DYFSOriginalSidebarIconMove = NULL;
static IMP DYFSOriginalSidebarRightMove = NULL;
static IMP DYFSOriginalTabBarLayout = NULL;
static IMP DYFSOriginalTabBarHidden = NULL;
static IMP DYFSOriginalProgressLayout = NULL;

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
    return DYFSInstalledFeed ? 1 : 0;
}

static NSUInteger DYFSSidebarHookCount(void) {
    return (DYFSInstalledSidebarIcon ? 1 : 0) + (DYFSInstalledSidebarRight ? 1 : 0);
}

static NSUInteger DYFSTabBarHookCount(void) {
    return (DYFSInstalledTabBarLayout ? 1 : 0) + (DYFSInstalledTabBarHidden ? 1 : 0);
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
        @"抖音版本：%@\n全屏开关：%@\n首页视频列表 Hook：%@\n底栏透明 Hook：%lu/2\n进度容器透明 Hook：%@\n设置入口 Hook：%lu/2\n当前首页 Tab 选中：%@\n底栏背景已隐藏：%@\n底栏布局处理次数：%lu\n视频列表布局调整次数：%lu\n\nDY.FullScreen 不调整点赞、评论、分享等功能区的位置或高度；这部分由 DYYY 管理。编译通过只代表构建成功，仍需在实机检查视觉效果。",
        version, DYFSIsEnabled() ? @"开启" : @"关闭",
        DYFSInstalledFeed ? @"已安装" : @"未找到类",
        (unsigned long)DYFSTabBarHookCount(),
        DYFSInstalledProgressContainer ? @"已安装" : @"未找到类",
        (unsigned long)DYFSSidebarHookCount(),
        DYFSLastHomeTabSelected ? @"是" : @"否",
        DYFSLastTabBackgroundHidden ? @"是" : @"否",
        (unsigned long)DYFSTabBarApplyCount,
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
    descriptionLabel.text = @"只扩展首页视频列表显示区域，并处理底栏皮肤背景和分割线透明（保留功能按钮）。不修改点赞、评论、分享等视频功能区的位置或高度；如需调整功能区，请使用 DYYY。适配目标为抖音 40.7.0。";
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


static id DYFSSafeValueForKey(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static void DYFSApplyTabBarTransparency(UIView *tabBar) {
    if (!tabBar) return;

    BOOL enabled = DYFSIsEnabled();
    Class generalButtonClass = NSClassFromString(@"AWENormalModeTabBarGeneralButton");
    Class plusButtonClass = NSClassFromString(@"AWENormalModeTabBarGeneralPlusButton");
    Class barBackgroundClass = NSClassFromString(@"_UIBarBackground");

    BOOL isHomeSelected = NO;
    for (UIView *subview in [tabBar.subviews copy]) {
        if (!generalButtonClass || ![subview isKindOfClass:generalButtonClass]) continue;
        NSString *label = subview.accessibilityLabel ?: @"";
        id status = DYFSSafeValueForKey(subview, @"status");
        BOOL selected = [status respondsToSelector:@selector(integerValue)] && [status integerValue] == 2;
        if (selected && [label isEqualToString:@"首页"]) {
            isHomeSelected = YES;
        }
    }

    // DYYY hides the skin layer while full-screen is active, and hides the
    // actual bar background only while the Home tab is selected. Buttons stay
    // visible/tappable; only background layers and the hairline are hidden.
    id skinContainer = DYFSSafeValueForKey(tabBar, @"skinContainerView");
    if ([skinContainer isKindOfClass:UIView.class]) {
        ((UIView *)skinContainer).hidden = enabled;
    }

    BOOL shouldHideBackgrounds = enabled && isHomeSelected;
    CGFloat barHeight = CGRectGetHeight(tabBar.bounds);
    if (barHeight <= 0.0 || !isfinite(barHeight)) {
        barHeight = 49.0 + MAX(0.0, tabBar.window.safeAreaInsets.bottom);
    }

    for (UIView *subview in [tabBar.subviews copy]) {
        if ((generalButtonClass && [subview isKindOfClass:generalButtonClass]) ||
            (plusButtonClass && [subview isKindOfClass:plusButtonClass])) {
            continue;
        }

        CGFloat subviewHeight = CGRectGetHeight(subview.frame);
        CGFloat subviewWidth = CGRectGetWidth(subview.frame);
        BOOL isBackgroundView = (barBackgroundClass && [subview isKindOfClass:barBackgroundClass]) ||
            ([subview isMemberOfClass:UIView.class] &&
             barHeight > 0.0 && fabs(subviewHeight - barHeight) < 1.0);
        BOOL isDivider = (subviewHeight > 0.0 && subviewHeight < 1.0 && subviewWidth > 300.0);

        if (isBackgroundView) {
            subview.hidden = shouldHideBackgrounds;
        }
        if (isDivider) {
            subview.hidden = enabled;
        }
    }

    DYFSLastHomeTabSelected = isHomeSelected;
    DYFSLastTabBackgroundHidden = shouldHideBackgrounds;
    DYFSTabBarApplyCount++;
}

static void DYFSTabBarLayout(id self, SEL cmd) {
    if (DYFSOriginalTabBarLayout) ((void (*)(id, SEL))DYFSOriginalTabBarLayout)(self, cmd);
    DYFSApplyTabBarTransparency((UIView *)self);
}

static void DYFSTabBarSetHidden(id self, SEL cmd, BOOL hidden) {
    if (DYFSOriginalTabBarHidden) ((void (*)(id, SEL, BOOL))DYFSOriginalTabBarHidden)(self, cmd, hidden);
    DYFSApplyTabBarTransparency((UIView *)self);
}

static void DYFSProgressContainerLayout(id self, SEL cmd) {
    if (DYFSOriginalProgressLayout) ((void (*)(id, SEL))DYFSOriginalProgressLayout)(self, cmd);
    if (!DYFSIsEnabled()) return;

    UIView *container = (UIView *)self;
    for (UIView *subview in [container.subviews copy]) {
        if ([subview class] == UIView.class) {
            subview.backgroundColor = UIColor.clearColor;
        }
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

    cls = NSClassFromString(@"AWENormalModeTabBar");
    if (cls && !DYFSInstalledTabBarLayout) {
        DYFSInstalledTabBarLayout = DYFSInstallHook(cls, @selector(layoutSubviews),
                    (IMP)DYFSTabBarLayout, &DYFSOriginalTabBarLayout);
    }
    if (cls && !DYFSInstalledTabBarHidden) {
        DYFSInstalledTabBarHidden = DYFSInstallHook(cls, @selector(setHidden:),
                    (IMP)DYFSTabBarSetHidden, &DYFSOriginalTabBarHidden);
    }

    cls = NSClassFromString(@"AWEPlayInteractionProgressContainerView");
    if (cls && !DYFSInstalledProgressContainer) {
        DYFSInstalledProgressContainer = DYFSInstallHook(cls, @selector(layoutSubviews),
                    (IMP)DYFSProgressContainerLayout, &DYFSOriginalProgressLayout);
    }

    NSString *summary = [NSString stringWithFormat:@"video-list hook %@; sidebar hooks %lu/2; tab bar hooks %lu/2; interaction-area resizing off; player-frame hook off",
                         DYFSInstalledFeed ? @"on" : @"off", (unsigned long)DYFSSidebarHookCount(),
                         (unsigned long)DYFSTabBarHookCount()];
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

        BOOL layoutInstalled = DYFSInstalledFeed;
        BOOL sidebarInstalled = DYFSInstalledSidebarIcon || DYFSInstalledSidebarRight;
        BOOL tabBarInstalled = DYFSInstalledTabBarLayout && DYFSInstalledTabBarHidden;
        if ((!layoutInstalled || !sidebarInstalled || !tabBarInstalled) &&
            DYFSInstallAttempts < 60) {
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
