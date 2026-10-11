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
static BOOL DYFSInstalledInteractionController = NO;
static BOOL DYFSInstalledPlayerContentA = NO;
static BOOL DYFSInstalledPlayerContentB = NO;
static BOOL DYFSInstalledPlayerContentC = NO;
static BOOL DYFSInstalledLiveStack = NO;
static BOOL DYFSInstalledSidebarIcon = NO;
static BOOL DYFSInstalledSidebarRight = NO;
static BOOL DYFSInstalledTabBarLayout = NO;
static BOOL DYFSInstalledTabBarHidden = NO;
static BOOL DYFSInstalledTabBarDidMove = NO;
static BOOL DYFSInstalledTabBarDidAddSubview = NO;
static BOOL DYFSInstalledDetailTable = NO;
static BOOL DYFSInstalledDetailCell = NO;
static BOOL DYFSInstalledMixPanelDetail = NO;
static BOOL DYFSStartupRelayoutScheduled = NO;
static BOOL DYFSInstalledInteractionProgress = NO;
static BOOL DYFSInstalledPlayerProgress = NO;
static BOOL DYFSInstalledCommentPanel = NO;
static BOOL DYFSInstalledCommentInputContainer = NO;
static BOOL DYFSInstalledCommentInputBackground = NO;
static BOOL DYFSInstalledCommentInputController = NO;
static BOOL DYFSInstalledNativeSettingsSwitch = NO;
static BOOL DYFSNativeSettingsRowAdded = NO;
static NSUInteger DYFSInstallAttempts = 0;
static BOOL DYFSSchedulePending = NO;
static NSUInteger DYFSLayoutFixCount = 0;
static NSUInteger DYFSInteractionContainerAdjustCount = 0;
static NSUInteger DYFSPlayerContentAdjustCount = 0;
static NSUInteger DYFSTabBarApplyCount = 0;
static NSUInteger DYFSCommentBarTransparencyApplyCount = 0;
static BOOL DYFSLastHomeTabSelected = NO;
static BOOL DYFSLastTabBackgroundHidden = NO;
static BOOL DYFSSettingsEntryVisible = NO;
static NSString *DYFSLastInstallSummary = @"尚未检测";
static IMP DYFSOriginalFeedLayout = NULL;
static IMP DYFSOriginalStoryLayout = NULL;
static IMP DYFSOriginalInteractionControllerLayout = NULL;
static IMP DYFSOriginalPlayerContentA = NULL;
static IMP DYFSOriginalPlayerContentB = NULL;
static IMP DYFSOriginalPlayerContentC = NULL;
static IMP DYFSOriginalLiveStackLayout = NULL;
static IMP DYFSOriginalSidebarIconMove = NULL;
static IMP DYFSOriginalSidebarRightMove = NULL;
static IMP DYFSOriginalTabBarLayout = NULL;
static IMP DYFSOriginalTabBarHidden = NULL;
static IMP DYFSOriginalTabBarDidMove = NULL;
static IMP DYFSOriginalTabBarDidAddSubview = NULL;
static IMP DYFSOriginalDetailTableLayout = NULL;
static IMP DYFSOriginalDetailCellLayout = NULL;
static IMP DYFSOriginalMixPanelDetailLayout = NULL;
static IMP DYFSOriginalInteractionProgressLayout = NULL;
static IMP DYFSOriginalPlayerProgressLayout = NULL;
static IMP DYFSOriginalCommentPanelLayout = NULL;
static IMP DYFSOriginalCommentInputContainerLayout = NULL;
static IMP DYFSOriginalCommentInputBackgroundLayout = NULL;
static IMP DYFSOriginalCommentInputControllerLayout = NULL;
static char kDYFSPlayerLayoutPendingKey;
static char kDYFSPlayerParentHeightKey;
static char kDYFSPlayerSettledGeometryKey;
static IMP DYFSOriginalNativeSettingsDidAppear = NULL;

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



static NSUInteger DYFSSidebarHookCount(void) {
    return (DYFSInstalledSidebarIcon ? 1 : 0) + (DYFSInstalledSidebarRight ? 1 : 0);
}

static NSUInteger DYFSTabBarHookCount(void) {
    return (DYFSInstalledTabBarLayout ? 1 : 0) + (DYFSInstalledTabBarHidden ? 1 : 0);
}

static void DYFSMarkNeedsLayoutRecursively(UIView *view, NSUInteger depth) {
    if (!view || depth > 32) return;
    [view setNeedsLayout];
    for (UIView *subview in [view.subviews copy]) {
        DYFSMarkNeedsLayoutRecursively(subview, depth + 1);
    }
}

static void DYFSRequestRelayout(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            DYFSMarkNeedsLayoutRecursively(window, 0);
            [window layoutIfNeeded];
        }
    });
}

static NSString *DYFSStatusText(void) {
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"未知";
    return [NSString stringWithFormat:
        @"抖音版本：%@\n全屏开关：%@\n首页视频列表 Hook：%@\n互动控制器 Hook：%@\n互动层调整次数：%lu\n播放器画面调整次数：%lu\n直播预览原位保护：%@\n底栏透明 Hook：%lu/2\n侧边栏入口 Hook：%lu/2\n侧边栏全屏入口：%@\n原生设置页开关 Hook：%@\n原生设置页全屏开关：%@\n当前首页 Tab 选中：%@\n底栏背景已隐藏：%@\n底栏布局处理次数：%lu\n视频列表布局调整次数：%lu\n\n设置项名称为“胖胖专属 / 插件开关”。普通视频与图集全屏独立调整；直播预览不做尺寸/位移修改，避免视频、文案与“点击进入直播间”错位。评论页面底部输入栏背景透明处理次数：%lu。",
        version, DYFSIsEnabled() ? @"开启" : @"关闭",
        DYFSInstalledFeed ? @"已安装" : @"未找到类",
        DYFSInstalledInteractionController ? @"已安装" : @"未找到类",
        (unsigned long)DYFSInteractionContainerAdjustCount,
        (unsigned long)DYFSPlayerContentAdjustCount,
        DYFSInstalledLiveStack ? @"已安装（不移位）" : @"未找到类",
        (unsigned long)DYFSTabBarHookCount(),
        (unsigned long)DYFSSidebarHookCount(),
        DYFSSettingsEntryVisible ? @"已挂载" : @"未找到侧边栏设置图标",
        DYFSInstalledNativeSettingsSwitch ? @"已安装" : @"未找到 AWESettingsTableViewController",
        DYFSNativeSettingsRowAdded ? @"已插入" : @"尚未插入（请打开一次抖音设置）",
        DYFSLastHomeTabSelected ? @"是" : @"否",
        DYFSLastTabBackgroundHidden ? @"是" : @"否",
        (unsigned long)DYFSTabBarApplyCount,
        (unsigned long)DYFSLayoutFixCount,
        (unsigned long)DYFSCommentBarTransparencyApplyCount];
}

static UIViewController *DYFSFindViewController(UIView *view) {
    UIResponder *responder = view;
    for (NSUInteger depth = 0; responder && depth < 40; depth++) {
        if ([responder isKindOfClass:UIViewController.class]) return (UIViewController *)responder;
        responder = responder.nextResponder;
    }
    return nil;
}

// Full-screen sizing belongs to ordinary homepage video cells and photo posts.
// Live push/preview has its own layout coordinator (including DYYY's) and must
// retain Douyin's native video centering, prompt and "enter live room" positions.
static BOOL DYFSIsLivePreStreamContext(UIView *view) {
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

static UIViewController *DYFSActiveTopViewController(void);

static BOOL DYFSIsLivePreStreamPlayer(id playerController) {
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
    self.title = @"胖胖专属";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"胖胖专属";
    titleLabel.font = [UIFont boldSystemFontOfSize:24];
    titleLabel.textColor = UIColor.labelColor;

    UILabel *descriptionLabel = [[UILabel alloc] init];
    descriptionLabel.text = @"首页视频与图集全屏、底栏透明设置。适配抖音 40.7.0。";
    descriptionLabel.font = [UIFont systemFontOfSize:14];
    descriptionLabel.textColor = UIColor.secondaryLabelColor;
    descriptionLabel.numberOfLines = 0;

    UILabel *switchTitle = [[UILabel alloc] init];
    switchTitle.text = @"插件开关";
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

static BOOL DYFSViewHasSettingsLabel(UIView *view, NSUInteger depth) {
    if (!view || depth > 8) return NO;

    if ([view.accessibilityLabel isEqualToString:@"设置"]) return YES;
    if ([view isKindOfClass:UILabel.class] &&
        [((UILabel *)view).text isEqualToString:@"设置"]) return YES;
    if ([view isKindOfClass:UIButton.class]) {
        NSString *title = [((UIButton *)view) titleForState:UIControlStateNormal];
        if ([title isEqualToString:@"设置"]) return YES;
    }

    for (UIView *subview in [view.subviews copy]) {
        if (DYFSViewHasSettingsLabel(subview, depth + 1)) return YES;
    }
    return NO;
}

static BOOL DYFSIsSidebarSettingsClass(UIView *view) {
    NSString *name = NSStringFromClass(view.class);
    return [name isEqualToString:@"AWELeftSideBarTopIconHorizontalView"] ||
           [name isEqualToString:@"AWELeftSideBarTopRightLayoutView"];
}

static void DYFSInstallSettingsEntry(UIView *settingsIcon) {
    // Douyin may expose "设置" on the icon itself or on one of its child views.
    if (!settingsIcon || !DYFSViewHasSettingsLabel(settingsIcon, 0)) return;

    UIView *targetSuperView = settingsIcon.superview.superview.superview ?: settingsIcon.superview ?: settingsIcon;
    if (!targetSuperView) return;

    UIButton *button = (UIButton *)[targetSuperView viewWithTag:420740];
    if (![button isKindOfClass:UIButton.class]) button = nil;

    // Convert the anchor's bounds into the coordinate space of the actual
    // superview that will contain the button; using settingsIcon.frame directly
    // here mixes coordinate systems and can place the entry off-screen.
    CGRect anchorFrame = [settingsIcon convertRect:settingsIcon.bounds toView:targetSuperView];
    CGFloat buttonWidth = 88.0;
    CGFloat buttonHeight = 32.0;
    CGFloat availableWidth = CGRectGetWidth(targetSuperView.bounds);
    CGFloat availableHeight = CGRectGetHeight(targetSuperView.bounds);

    CGFloat x = CGRectGetMaxX(anchorFrame) + 6.0;
    if (availableWidth > buttonWidth && x + buttonWidth > availableWidth - 4.0) {
        x = CGRectGetMinX(anchorFrame) - buttonWidth - 6.0;
    }
    if (availableWidth > buttonWidth) {
        x = MIN(MAX(4.0, x), availableWidth - buttonWidth - 4.0);
    } else {
        x = MAX(4.0, CGRectGetMaxX(anchorFrame) + 6.0);
    }

    CGFloat y = CGRectGetMidY(anchorFrame) - buttonHeight / 2.0;
    if (availableHeight > buttonHeight) {
        y = MIN(MAX(4.0, y), availableHeight - buttonHeight - 4.0);
    } else {
        y = 8.0;
    }

    if (!button) {
        button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = 420740;
        button.accessibilityLabel = @"DY.FullScreen 设置入口";
        button.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.16];
        button.layer.cornerRadius = 8.0;
        button.clipsToBounds = YES;
        [button addTarget:[DYFSSettingsActionTarget sharedTarget]
                   action:@selector(openSettings:)
         forControlEvents:UIControlEventTouchUpInside];
        [targetSuperView addSubview:button];
    }

    [button setTitle:@"胖胖专属" forState:UIControlStateNormal];
    [button setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    button.frame = CGRectMake(x, y, buttonWidth, buttonHeight);
    button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;

    DYFSSettingsEntryVisible = YES;
    DYFSLog([NSString stringWithFormat:@"mounted DY.FullScreen entry (parent %.0fx%.0f, frame %@)",
            availableWidth, availableHeight, NSStringFromCGRect(button.frame)]);
}

static void DYFSScanForSettingsEntry(UIView *root, NSUInteger depth) {
    if (!root || depth > 18 || DYFSSettingsEntryVisible) return;

    if (DYFSIsSidebarSettingsClass(root) && DYFSViewHasSettingsLabel(root, 0)) {
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

static BOOL DYFSSafeSetValueForKey(id object, id value, NSString *key) {
    if (!object || key.length == 0) return NO;
    @try {
        [object setValue:value forKey:key];
        return YES;
    } @catch (NSException *exception) {
        DYFSLog([NSString stringWithFormat:@"KVC set failed for %@: %@", key, exception.reason ?: @"unknown"]);
        return NO;
    }
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
    if (window) {
        UIView *tabBar = DYFSFindSubviewOfClass(window, @"AWENormalModeTabBar", 0);
        CGFloat measured = CGRectGetHeight(tabBar.bounds);
        if (tabBar && isfinite(measured) && measured >= 30.0 && measured < CGRectGetHeight(window.bounds)) {
            return measured;
        }
        return 49.0 + MAX(0.0, window.safeAreaInsets.bottom);
    }
    return 49.0;
}

static NSString *DYFSVisibleTextForView(UIView *view) {
    if (!view) return @"";
    NSString *text = @"";
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        text = label.attributedText.string ?: label.text ?: @"";
    } else if ([view isKindOfClass:UITextField.class]) {
        UITextField *field = (UITextField *)view;
        text = field.placeholder ?: field.text ?: @"";
    } else if ([view isKindOfClass:UITextView.class]) {
        text = ((UITextView *)view).text ?: @"";
    } else if ([view isKindOfClass:UIButton.class]) {
        text = [((UIButton *)view) titleForState:UIControlStateNormal] ?: @"";
    }
    if (text.length == 0) text = view.accessibilityLabel ?: @"";
    if (text.length == 0) text = view.accessibilityValue ?: @"";
    if (text.length == 0) {
        id value = DYFSSafeValueForKey(view, @"text");
        if ([value isKindOfClass:NSString.class]) text = value;
        if (text.length == 0) {
            id attributed = DYFSSafeValueForKey(view, @"attributedText");
            if ([attributed respondsToSelector:@selector(string)]) {
                id string = ((id (*)(id, SEL))objc_msgSend)(attributed, @selector(string));
                if ([string isKindOfClass:NSString.class]) text = string;
            }
        }
    }
    return text ?: @"";
}

static BOOL DYFSIsRecommendationBoxLabel(UIView *view) {
    NSString *text = DYFSVisibleTextForView(view);
    return [text containsString:@"相关搜索"] ||
           ([text containsString:@"相关"] && [text containsString:@"搜索"]) ||
           [text containsString:@"合集"] || [text containsString:@"视频合集"];
}

static BOOL DYFSViewContainsControl(UIView *view, NSUInteger depth) {
    if (!view || depth > 8) return NO;
    NSString *name = NSStringFromClass(view.class);
    if ([view isKindOfClass:UIControl.class] ||
        [name containsString:@"GeneralButton"] ||
        [name containsString:@"PlusButton"] ||
        [name containsString:@"Button"]) return YES;
    for (UIView *subview in view.subviews) {
        if (DYFSViewContainsControl(subview, depth + 1)) return YES;
    }
    return NO;
}

static BOOL DYFSViewContainsRelevantText(UIView *view, NSUInteger depth) {
    if (!view || depth > 8) return NO;
    NSString *name = NSStringFromClass(view.class);
    NSString *text = DYFSVisibleTextForView(view);
    if (text.length > 0 &&
        ([view isKindOfClass:UILabel.class] || [view isKindOfClass:UITextField.class] ||
         [view isKindOfClass:UITextView.class] || [name containsString:@"VirtualLabel"] ||
         [name containsString:@"TextLabel"] || [text containsString:@"相关搜索"] ||
         [text containsString:@"合集"] || [text containsString:@"爱评论"] ||
         [text containsString:@"评论"] || [text containsString:@"搜索"] ||
         [text containsString:@"输入"])) return YES;
    for (UIView *subview in view.subviews) {
        if (DYFSViewContainsRelevantText(subview, depth + 1)) return YES;
    }
    return NO;
}

static BOOL DYFSIsBackgroundChrome(UIView *view) {
    if (!view) return NO;
    NSString *name = NSStringFromClass(view.class);
    return [view isKindOfClass:UIVisualEffectView.class] ||
           [name containsString:@"Background"] || [name containsString:@"Backdrop"] ||
           [name containsString:@"Blur"] || [name containsString:@"BackPlate"] ||
           [name containsString:@"Material"] || [name containsString:@"Gradient"] ||
           [name isEqualToString:@"_UIBarBackground"];
}

static void DYFSClearViewBackgroundOnly(UIView *view) {
    if (!view) return;
    view.backgroundColor = UIColor.clearColor;
    view.layer.backgroundColor = UIColor.clearColor.CGColor;
    view.opaque = NO;
    // Text attributes, alpha, icons, interaction state, frame and transforms remain untouched.
}

static void DYFSClearSmallCardChrome(UIView *card, NSUInteger depth) {
    if (!card || depth > 8) return;
    DYFSClearViewBackgroundOnly(card);
    CGFloat cardWidth = CGRectGetWidth(card.bounds);
    CGFloat cardHeight = CGRectGetHeight(card.bounds);
    for (UIView *subview in [card.subviews copy]) {
        CGRect rect = [subview convertRect:subview.bounds toView:card];
        CGFloat width = CGRectGetWidth(rect);
        CGFloat height = CGRectGetHeight(rect);
        BOOL fillsCard = cardWidth > 0.0 && cardHeight > 0.0 &&
            width >= cardWidth * 0.82 && height >= cardHeight * 0.68;
        BOOL containsControl = DYFSViewContainsControl(subview, 0);
        BOOL containsText = DYFSViewContainsRelevantText(subview, 0);
        BOOL genericBacking = [subview isMemberOfClass:UIView.class] ||
            [subview isKindOfClass:UIImageView.class] ||
            [subview isKindOfClass:UIVisualEffectView.class] ||
            DYFSIsBackgroundChrome(subview);
        if (fillsCard && !containsControl && !containsText && genericBacking) {
            subview.hidden = YES;
            continue;
        }
        if (DYFSIsBackgroundChrome(subview) ||
            ([subview isMemberOfClass:UIView.class] && !containsControl && !containsText)) {
            DYFSClearViewBackgroundOnly(subview);
        }
        if (!subview.hidden) DYFSClearSmallCardChrome(subview, depth + 1);
    }
}

static CGFloat DYFSIntersectionRatio(CGRect rect, CGRect target) {
    if (CGRectIsEmpty(rect) || CGRectIsEmpty(target)) return 0.0;
    CGRect intersection = CGRectIntersection(rect, target);
    if (CGRectIsNull(intersection) || CGRectIsEmpty(intersection)) return 0.0;
    CGFloat targetArea = CGRectGetWidth(target) * CGRectGetHeight(target);
    if (targetArea <= 1.0) return 0.0;
    return CGRectGetWidth(intersection) * CGRectGetHeight(intersection) / targetArea;
}

static void DYFSClearOverlappingBackgroundSiblings(UIView *anchor, UIView *root, CGFloat maxHeight) {
    if (!anchor || !root) return;
    CGRect targetRect = [anchor convertRect:anchor.bounds toView:root];
    CGFloat targetWidth = CGRectGetWidth(targetRect);
    CGFloat targetHeight = CGRectGetHeight(targetRect);
    if (targetWidth < 24.0 || targetHeight < 14.0 || targetHeight > maxHeight) return;

    UIView *cursor = anchor;
    for (NSUInteger depth = 0; cursor && cursor != root && depth < 8; depth++, cursor = cursor.superview) {
        UIView *parent = cursor.superview;
        if (!parent) break;
        for (UIView *sibling in [parent.subviews copy]) {
            if (sibling == cursor || sibling.hidden ||
                DYFSViewContainsControl(sibling, 0) ||
                DYFSViewContainsRelevantText(sibling, 0)) continue;
            NSString *name = NSStringFromClass(sibling.class);
            BOOL couldBeBackground = DYFSIsBackgroundChrome(sibling) ||
                [sibling isMemberOfClass:UIView.class] ||
                [sibling isKindOfClass:UIImageView.class];
            if (!couldBeBackground) continue;
            CGRect siblingRect = [sibling convertRect:sibling.bounds toView:root];
            CGFloat siblingHeight = CGRectGetHeight(siblingRect);
            if (siblingHeight < targetHeight * 0.60 ||
                siblingHeight > MAX(targetHeight * 2.5, targetHeight + 55.0) ||
                CGRectGetWidth(siblingRect) > CGRectGetWidth(root.bounds) * 0.99) continue;
            if (DYFSIntersectionRatio(siblingRect, targetRect) < 0.65) continue;
            if (DYFSIsBackgroundChrome(sibling) ||
                [sibling isMemberOfClass:UIView.class] ||
                [name containsString:@"ImageView"]) sibling.hidden = YES;
        }
    }
}

static void DYFSApplyRecommendationTransparencyInView(UIView *root) {
    if (!root || !DYFSIsEnabled()) return;
    CGFloat rootWidth = CGRectGetWidth(root.bounds);
    CGFloat rootHeight = CGRectGetHeight(root.bounds);
    if (rootWidth < 100.0 || rootHeight < 160.0) return;

    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:root];
    while (pending.count > 0) {
        UIView *label = pending.lastObject;
        [pending removeLastObject];
        [pending addObjectsFromArray:label.subviews];
        if (!DYFSIsRecommendationBoxLabel(label)) continue;

        UIView *card = nil;
        // Nearest plausible pill first; its opaque grey plate is often a sibling.
        for (UIView *candidate = label.superview; candidate && candidate != root; candidate = candidate.superview) {
            CGRect rect = [candidate convertRect:candidate.bounds toView:root];
            CGFloat width = CGRectGetWidth(rect);
            CGFloat height = CGRectGetHeight(rect);
            CGFloat minY = CGRectGetMinY(rect);
            CGFloat maxY = CGRectGetMaxY(rect);
            if (width < MAX(58.0, rootWidth * 0.12) ||
                width > rootWidth * 0.99 ||
                height < 20.0 || height > 160.0 ||
                minY < rootHeight * 0.18 || maxY > rootHeight + 4.0) continue;
            card = candidate;
            break;
        }
        if (card) {
            DYFSClearSmallCardChrome(card, 0);
            DYFSClearOverlappingBackgroundSiblings(card, root, 180.0);
        }
    }
}

static BOOL DYFSIsCommentDockView(UIView *view) {
    if (!view) return NO;
    NSString *name = NSStringFromClass(view.class);
    return [name containsString:@"CommentInputContainerView"] ||
           [name containsString:@"AWECommentInputBackgroundView"] ||
           [name containsString:@"CommentInputBackgroundView"];
}

static void DYFSClearCommentDockBackground(UIView *dock, NSUInteger depth) {
    if (!dock || depth > 8) return;
    DYFSClearViewBackgroundOnly(dock);
    CGFloat dockWidth = CGRectGetWidth(dock.bounds);
    CGFloat dockHeight = CGRectGetHeight(dock.bounds);
    for (UIView *subview in [dock.subviews copy]) {
        CGRect rect = [subview convertRect:subview.bounds toView:dock];
        CGFloat width = CGRectGetWidth(rect);
        CGFloat height = CGRectGetHeight(rect);
        BOOL fillsDock = dockWidth > 0.0 && dockHeight > 0.0 &&
            width >= dockWidth * 0.82 && height >= dockHeight * 0.60;
        BOOL containsControl = DYFSViewContainsControl(subview, 0);
        BOOL containsText = DYFSViewContainsRelevantText(subview, 0);
        BOOL backing = DYFSIsBackgroundChrome(subview) ||
            [subview isMemberOfClass:UIView.class] ||
            [subview isKindOfClass:UIImageView.class];
        if (fillsDock && !containsControl && !containsText && backing) {
            subview.hidden = YES;
            continue;
        }
        if (DYFSIsBackgroundChrome(subview) ||
            ([subview isMemberOfClass:UIView.class] && !containsControl && !containsText)) {
            DYFSClearViewBackgroundOnly(subview);
        }
        if (!subview.hidden && ![subview isKindOfClass:UIControl.class]) {
            DYFSClearCommentDockBackground(subview, depth + 1);
        }
    }
}

static void DYFSApplyVideoDetailBottomTransparencyInView(UIView *root) {
    if (!root || !DYFSIsEnabled()) return;
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:root];
    while (pending.count > 0) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        [pending addObjectsFromArray:view.subviews];
        if (DYFSIsCommentDockView(view)) {
            DYFSClearCommentDockBackground(view, 0);
            DYFSClearOverlappingBackgroundSiblings(view, root, 180.0);
        }
    }
}

static void DYFSDetailTableLayout(id self, SEL cmd) {
    if (DYFSOriginalDetailTableLayout) {
        ((void (*)(id, SEL))DYFSOriginalDetailTableLayout)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;
    UIView *root = [self isKindOfClass:UIViewController.class] ? ((UIViewController *)self).view : nil;
    DYFSApplyVideoDetailBottomTransparencyInView(root);
    DYFSApplyRecommendationTransparencyInView(root);
}

static void DYFSDetailCellLayout(id self, SEL cmd) {
    if (DYFSOriginalDetailCellLayout) {
        ((void (*)(id, SEL))DYFSOriginalDetailCellLayout)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;
    UIView *root = [self isKindOfClass:UIViewController.class] ? ((UIViewController *)self).view : nil;
    DYFSApplyVideoDetailBottomTransparencyInView(root);
    DYFSApplyRecommendationTransparencyInView(root);
}

static void DYFSMixPanelDetailLayout(id self, SEL cmd) {
    if (DYFSOriginalMixPanelDetailLayout) {
        ((void (*)(id, SEL))DYFSOriginalMixPanelDetailLayout)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;
    UIView *root = [self isKindOfClass:UIViewController.class] ? ((UIViewController *)self).view : nil;
    DYFSApplyVideoDetailBottomTransparencyInView(root);
    DYFSApplyRecommendationTransparencyInView(root);
}

static BOOL DYFSIsDetailVideoContext(UIView *view) {
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

static BOOL DYFSIsFeedCellInteractionController(UIViewController *controller) {
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

// Ordinary video posts and photo carousels use different player wrappers and
// different child counts. Constrain the feed interaction controller directly,
// so the right-side actions and caption stay within their original usable area.
static void DYFSInteractionControllerLayout(id self, SEL cmd) {
    if (DYFSOriginalInteractionControllerLayout) {
        ((void (*)(id, SEL))DYFSOriginalInteractionControllerLayout)(self, cmd);
    }
    UIViewController *controller = (UIViewController *)self;
    UIView *view = controller.view;
    if (!DYFSIsEnabled()) return;
    DYFSApplyRecommendationTransparencyInView(view);
    if (view.superview) DYFSApplyRecommendationTransparencyInView(view.superview);
    if (!view || !view.superview || DYFSInProfileContext(view) || DYFSIsLivePreStreamContext(view) || DYFSIsLivePreStreamPlayer(controller)) return;
    if (!DYFSIsFeedCellInteractionController(controller)) return;

    UIView *parent = view.superview;
    CGFloat parentHeight = CGRectGetHeight(parent.bounds);
    CGFloat tabBarHeight = DYFSBottomTabBarHeight(view);
    CGFloat targetHeight = parentHeight - tabBarHeight;
    CGRect frame = view.frame;
    CGFloat screenWidth = CGRectGetWidth(UIScreen.mainScreen.bounds);

    if (!isfinite(targetHeight) || targetHeight <= 1.0 ||
        (fabs(CGRectGetWidth(frame) - screenWidth) > 1.0 && CGRectGetHeight(frame) < parentHeight)) {
        return;
    }
    if (fabs(CGRectGetHeight(frame) - targetHeight) <= 0.5) return;

    CGFloat oldHeight = CGRectGetHeight(frame);
    frame.size.height = targetHeight;
    view.frame = frame;
    DYFSInteractionContainerAdjustCount++;
    DYFSLog([NSString stringWithFormat:
        @"interaction controller height %.2f -> %.2f (parent %.2f, tab bar %.2f)",
        oldHeight, targetHeight, parentHeight, tabBarHeight]);
}

static void DYFSApplyPlayerContentHeightNow(id playerController) {
    if (!DYFSIsEnabled()) return;

    UIView *controllerView = [playerController isKindOfClass:UIViewController.class]
        ? ((UIViewController *)playerController).view : nil;
    if (DYFSIsLivePreStreamPlayer(playerController) || DYFSIsLivePreStreamContext(controllerView)) return;

    UIView *contentView = DYFSSafeValueForKey(playerController, @"contentView");
    if (DYFSIsLivePreStreamContext(contentView)) return;
    if (DYFSInProfileContext(controllerView) || DYFSInProfileContext(contentView) ||
        DYFSIsDetailVideoContext(controllerView) || DYFSIsDetailVideoContext(contentView)) {
        DYFSApplyVideoDetailBottomTransparencyInView(controllerView);
        return;
    }
    if (![contentView isKindOfClass:UIView.class] || !contentView.superview ||
        !contentView.window || !contentView.superview.window) return;

    UIView *parent = contentView.superview;
    CGFloat parentHeight = CGRectGetHeight(parent.bounds);
    CGFloat currentHeight = CGRectGetHeight(contentView.frame);
    CGFloat diff = parentHeight - currentHeight;
    CGFloat tabBarHeight = DYFSBottomTabBarHeight(contentView);
    CGFloat tolerance = MAX(1.0, tabBarHeight * 0.03);
    CGFloat targetHeight = currentHeight;

    // Match the two common wrapper cases seen in DYYY: one tab-bar height short,
    // or two tab-bar heights short. This targets contentView only, never controls.
    if (fabs(diff - tabBarHeight) <= tolerance) {
        targetHeight = parentHeight;
    } else if (fabs(diff - (tabBarHeight * 2.0)) <= tolerance) {
        targetHeight = parentHeight - tabBarHeight;
    } else {
        return;
    }

    if (!isfinite(targetHeight) || targetHeight <= 1.0 ||
        fabs(currentHeight - targetHeight) <= 0.5) return;

    CGRect frame = contentView.frame;
    frame.size.height = targetHeight;
    contentView.frame = frame;
    DYFSPlayerContentAdjustCount++;
    DYFSLog([NSString stringWithFormat:
        @"%@ contentView height %.2f -> %.2f (parent %.2f, diff %.2f, tab bar %.2f)",
        NSStringFromClass([playerController class]), currentHeight, targetHeight, parentHeight, diff, tabBarHeight]);
}

static void DYFSSchedulePlayerContentHeight(id playerController) {
    if (!playerController || !DYFSIsEnabled()) return;
    UIViewController *controllerViewController = [playerController isKindOfClass:UIViewController.class]
        ? (UIViewController *)playerController : nil;
    UIView *controllerView = controllerViewController.view;
    if (DYFSInProfileContext(controllerView) || DYFSIsDetailVideoContext(controllerView)) {
        DYFSApplyVideoDetailBottomTransparencyInView(controllerView);
        if (controllerView.superview) DYFSApplyVideoDetailBottomTransparencyInView(controllerView.superview);
        return;
    }

    UIView *currentContent = DYFSSafeValueForKey(playerController, @"contentView");
    UIView *currentParent = [currentContent isKindOfClass:UIView.class] ? currentContent.superview : nil;
    if ([currentContent isKindOfClass:UIView.class] && currentParent && currentContent.window && currentParent.window) {
        NSArray *settled = objc_getAssociatedObject(playerController, &kDYFSPlayerSettledGeometryKey);
        if ([settled isKindOfClass:NSArray.class] && settled.count == 3) {
            CGFloat parentWidth = CGRectGetWidth(currentParent.bounds);
            CGFloat parentHeight = CGRectGetHeight(currentParent.bounds);
            CGFloat contentHeight = CGRectGetHeight(currentContent.bounds);
            if (fabs([settled[0] doubleValue] - parentWidth) <= 1.0 &&
                fabs([settled[1] doubleValue] - parentHeight) <= 1.0 &&
                fabs([settled[2] doubleValue] - contentHeight) <= 1.0) return;
        }
    }
    if ([objc_getAssociatedObject(playerController, &kDYFSPlayerLayoutPendingKey) boolValue]) return;

    objc_setAssociatedObject(playerController, &kDYFSPlayerLayoutPendingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak id weakController = playerController;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        id strongController = weakController;
        if (!strongController) return;
        objc_setAssociatedObject(strongController, &kDYFSPlayerLayoutPendingKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        UIViewController *vc = [strongController isKindOfClass:UIViewController.class]
            ? (UIViewController *)strongController : nil;
        UIView *content = DYFSSafeValueForKey(strongController, @"contentView");
        UIView *parent = [content isKindOfClass:UIView.class] ? content.superview : nil;
        if (!content.window || !parent.window) return;

        CGFloat parentHeight = CGRectGetHeight(parent.bounds);
        NSNumber *previousHeight = objc_getAssociatedObject(content, &kDYFSPlayerParentHeightKey);
        if (!previousHeight || fabs(previousHeight.doubleValue - parentHeight) > 1.0) {
            objc_setAssociatedObject(content, &kDYFSPlayerParentHeightKey, @(parentHeight), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            DYFSSchedulePlayerContentHeight(strongController);
            return;
        }

        if (vc) {
            DYFSApplyRecommendationTransparencyInView(vc.view);
            if (vc.view.superview) DYFSApplyRecommendationTransparencyInView(vc.view.superview);
        }
        DYFSApplyPlayerContentHeightNow(strongController);

        CGFloat settledParentWidth = CGRectGetWidth(parent.bounds);
        CGFloat settledParentHeight = CGRectGetHeight(parent.bounds);
        CGFloat settledContentHeight = CGRectGetHeight(content.bounds);
        objc_setAssociatedObject(strongController, &kDYFSPlayerSettledGeometryKey,
            @[@(settledParentWidth), @(settledParentHeight), @(settledContentHeight)],
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}

static void DYFSPlayerContentLayoutA(id self, SEL cmd) {
    if (DYFSOriginalPlayerContentA) ((void (*)(id, SEL))DYFSOriginalPlayerContentA)(self, cmd);
    UIView *root = [self isKindOfClass:UIViewController.class] ? ((UIViewController *)self).view : nil;
    DYFSApplyRecommendationTransparencyInView(root);
    if (root.superview) DYFSApplyRecommendationTransparencyInView(root.superview);
    if (DYFSInProfileContext(root) || DYFSIsDetailVideoContext(root)) {
        DYFSApplyVideoDetailBottomTransparencyInView(root);
        if (root.superview) DYFSApplyVideoDetailBottomTransparencyInView(root.superview);
    }
    DYFSSchedulePlayerContentHeight(self);
}
static void DYFSPlayerContentLayoutB(id self, SEL cmd) {
    if (DYFSOriginalPlayerContentB) ((void (*)(id, SEL))DYFSOriginalPlayerContentB)(self, cmd);
    UIView *root = [self isKindOfClass:UIViewController.class] ? ((UIViewController *)self).view : nil;
    DYFSApplyRecommendationTransparencyInView(root);
    if (root.superview) DYFSApplyRecommendationTransparencyInView(root.superview);
    if (DYFSInProfileContext(root) || DYFSIsDetailVideoContext(root)) {
        DYFSApplyVideoDetailBottomTransparencyInView(root);
        if (root.superview) DYFSApplyVideoDetailBottomTransparencyInView(root.superview);
    }
    DYFSSchedulePlayerContentHeight(self);
}
static void DYFSPlayerContentLayoutC(id self, SEL cmd) {
    if (DYFSOriginalPlayerContentC) ((void (*)(id, SEL))DYFSOriginalPlayerContentC)(self, cmd);
    UIView *root = [self isKindOfClass:UIViewController.class] ? ((UIViewController *)self).view : nil;
    DYFSApplyRecommendationTransparencyInView(root);
    if (root.superview) DYFSApplyRecommendationTransparencyInView(root.superview);
    if (DYFSInProfileContext(root) || DYFSIsDetailVideoContext(root)) {
        DYFSApplyVideoDetailBottomTransparencyInView(root);
        if (root.superview) DYFSApplyVideoDetailBottomTransparencyInView(root.superview);
    }
    DYFSSchedulePlayerContentHeight(self);
}

static void DYFSLiveElementStackLayout(id self, SEL cmd) {
    // Keep this pass-through hook only so layoutSubviews chaining remains intact.
    // Do not offset this stack: DYYY has its own live-preview layout coordinator,
    // and a second tab-bar-height translation moves the copy and entry affordance.
    if (DYFSOriginalLiveStackLayout) {
        ((void (*)(id, SEL))DYFSOriginalLiveStackLayout)(self, cmd);
    }
}

// Expand the feed canvas while keeping the interaction controller (right-side
// actions, caption and other copy) within the usable area above the bottom
// tab bar. Only the parent interaction container is sized; individual controls
// and text views retain Douyin's own layout behavior.
static void DYFSStoryContainerLayout(id self, SEL cmd) {
    if (DYFSOriginalStoryLayout) {
        ((void (*)(id, SEL))DYFSOriginalStoryLayout)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;

    UIView *container = (UIView *)self;
    if (DYFSInProfileContext(container) || DYFSIsLivePreStreamContext(container)) return;

    id homeValue = DYFSSafeValueForKey(container, @"enableEnterProfile");
    BOOL isHome = [homeValue respondsToSelector:@selector(boolValue)] && [homeValue boolValue];
    if (!isHome) return;

    for (UIView *subview in [container.subviews copy]) {
        UIResponder *responder = subview.nextResponder;
        NSString *responderName = responder ? NSStringFromClass(responder.class) : @"";
        if (![responderName containsString:@"AWEPlayInteractionViewController"]) continue;

        id baseViewController = DYFSSafeValueForKey(responder, @"awemeBaseViewController");
        NSString *baseName = baseViewController ? NSStringFromClass([baseViewController class]) : @"";
        if (![baseName containsString:@"AWEFeedCellViewController"]) continue;

        UIView *parent = subview.superview;
        if (!parent) continue;

        CGFloat parentHeight = CGRectGetHeight(parent.bounds);
        CGFloat tabBarHeight = DYFSBottomTabBarHeight(subview);
        CGFloat targetHeight = parentHeight - tabBarHeight;
        if (!isfinite(targetHeight) || targetHeight <= 1.0) continue;

        CGRect frame = subview.frame;
        CGFloat oldHeight = CGRectGetHeight(frame);
        if (fabs(oldHeight - targetHeight) <= 0.5) continue;

        frame.size.height = targetHeight;
        subview.frame = frame;
        DYFSInteractionContainerAdjustCount++;
        DYFSLog([NSString stringWithFormat:
            @"home interaction layer height %.2f -> %.2f (parent %.2f, tab bar %.2f)",
            oldHeight, targetHeight, parentHeight, tabBarHeight]);
    }
}

static void DYFSEnsureNativeSettingsSwitch(UIViewController *controller) {
    Class settingsClass = NSClassFromString(@"AWESettingsTableViewController");
    if (!controller || !settingsClass || ![controller isKindOfClass:settingsClass]) return;

    id viewModel = nil;
    @try {
        if ([controller respondsToSelector:@selector(viewModel)]) {
            viewModel = ((id (*)(id, SEL))objc_msgSend)(controller, @selector(viewModel));
        }
    } @catch (NSException *exception) {
        DYFSLog([NSString stringWithFormat:@"cannot get native settings view model: %@", exception.reason ?: @"unknown"]);
        return;
    }

    id rawSections = DYFSSafeValueForKey(viewModel, @"sectionDataArray");
    if (![rawSections isKindOfClass:NSArray.class]) {
        DYFSLog(@"native settings sectionDataArray not ready; will retry next appearance");
        return;
    }
    NSArray *sections = (NSArray *)rawSections;
    NSString *itemIdentifier = DYFSEnabledKey;

    for (id section in sections) {
        id rawItems = DYFSSafeValueForKey(section, @"itemArray");
        if (![rawItems isKindOfClass:NSArray.class]) continue;
        for (id item in (NSArray *)rawItems) {
            NSString *identifier = DYFSSafeValueForKey(item, @"identifier");
            if (![identifier isEqualToString:itemIdentifier]) continue;
            DYFSSafeSetValueForKey(item, @"胖胖专属", @"title");
            DYFSSafeSetValueForKey(item, @"插件开关", @"subTitle");
            DYFSSafeSetValueForKey(item, @"", @"detail");
            DYFSSafeSetValueForKey(item, @(DYFSIsEnabled()), @"isSwitchOn");
            DYFSNativeSettingsRowAdded = YES;
            return;
        }
    }

    Class itemClass = NSClassFromString(@"AWESettingItemModel");
    Class sectionClass = NSClassFromString(@"AWESettingSectionModel");
    if (!itemClass || !sectionClass) {
        DYFSLog(@"native settings item/section classes not found");
        return;
    }

    id item = [[itemClass alloc] init];
    DYFSSafeSetValueForKey(item, itemIdentifier, @"identifier");
    DYFSSafeSetValueForKey(item, @"胖胖专属", @"title");
    DYFSSafeSetValueForKey(item, @"插件开关", @"subTitle");
    DYFSSafeSetValueForKey(item, @"", @"detail");
    DYFSSafeSetValueForKey(item, @6, @"cellType");
    DYFSSafeSetValueForKey(item, @0, @"colorStyle");
    DYFSSafeSetValueForKey(item, @YES, @"isEnable");
    DYFSSafeSetValueForKey(item, @(DYFSIsEnabled()), @"isSwitchOn");
    DYFSSafeSetValueForKey(item, @"ic_fullscreen_outlined_16", @"svgIconImageName");

    __weak id weakItem = item;
    void (^switchChangedBlock)(void) = ^{
        id strongItem = weakItem;
        if (!strongItem) return;
        id currentValue = DYFSSafeValueForKey(strongItem, @"isSwitchOn");
        BOOL newValue = ![currentValue respondsToSelector:@selector(boolValue)] || ![currentValue boolValue];
        DYFSSafeSetValueForKey(strongItem, @(newValue), @"isSwitchOn");
        [[NSUserDefaults standardUserDefaults] setBool:newValue forKey:DYFSEnabledKey];
        DYFSLog(newValue ? @"native settings enabled homepage fullscreen" : @"native settings disabled homepage fullscreen");
        DYFSRequestRelayout();
    };
    DYFSSafeSetValueForKey(item, [switchChangedBlock copy], @"switchChangedBlock");

    id section = [[sectionClass alloc] init];
    DYFSSafeSetValueForKey(section, @"", @"sectionHeaderTitle");
    DYFSSafeSetValueForKey(section, @"", @"sectionFooterTitle");
    DYFSSafeSetValueForKey(section, @0, @"sectionHeaderHeight");
    DYFSSafeSetValueForKey(section, @NO, @"useNewFooterLayout");
    DYFSSafeSetValueForKey(section, @0, @"type");
    DYFSSafeSetValueForKey(section, @[item], @"itemArray");

    NSMutableArray *updatedSections = [sections mutableCopy];
    [updatedSections insertObject:section atIndex:0];
    if (!DYFSSafeSetValueForKey(viewModel, updatedSections, @"sectionDataArray")) {
        DYFSLog(@"failed to insert native settings section");
        return;
    }

    id tableView = DYFSSafeValueForKey(controller, @"tableView");
    if ([tableView isKindOfClass:UITableView.class]) {
        [(UITableView *)tableView reloadData];
    }
    DYFSNativeSettingsRowAdded = YES;
    DYFSLog(@"inserted homepage fullscreen switch in native Douyin Settings");
}

static void DYFSRetryNativeSettingsSwitch(UIViewController *controller, NSUInteger attemptsLeft) {
    DYFSEnsureNativeSettingsSwitch(controller);
    if (DYFSNativeSettingsRowAdded || attemptsLeft == 0) return;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        DYFSRetryNativeSettingsSwitch(controller, attemptsLeft - 1);
    });
}

static void DYFSNativeSettingsDidAppear(id self, SEL cmd, BOOL animated) {
    if (DYFSOriginalNativeSettingsDidAppear) {
        ((void (*)(id, SEL, BOOL))DYFSOriginalNativeSettingsDidAppear)(self, cmd, animated);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        // Re-check each time Settings opens. Douyin can populate sectionDataArray
        // after viewDidAppear, so retry briefly instead of waiting for a reopen.
        DYFSNativeSettingsRowAdded = NO;
        DYFSRetryNativeSettingsSwitch((UIViewController *)self, 8);
    });
}

static BOOL DYFSIsTabBarControl(UIView *view, Class generalButtonClass, Class plusButtonClass) {
    if (!view) return NO;
    NSString *name = NSStringFromClass(view.class);
    return [view isKindOfClass:UIControl.class] ||
           (generalButtonClass && [view isKindOfClass:generalButtonClass]) ||
           (plusButtonClass && [view isKindOfClass:plusButtonClass]) ||
           [name containsString:@"AWENormalModeTabBarGeneralButton"] ||
           [name containsString:@"AWENormalModeTabBarGeneralPlusButton"] ||
           [name containsString:@"AWENormalModeTabBarPlusButton"];
}

static BOOL DYFSContainsTabBarControl(UIView *view, Class generalButtonClass, Class plusButtonClass, NSUInteger depth) {
    if (!view || depth > 8) return NO;
    if (DYFSIsTabBarControl(view, generalButtonClass, plusButtonClass)) return YES;
    for (UIView *subview in view.subviews) {
        if (DYFSContainsTabBarControl(subview, generalButtonClass, plusButtonClass, depth + 1)) return YES;
    }
    return NO;
}

static void DYFSApplyTabBarBackgroundsRecursively(UIView *container, UIView *tabBar,
                                                  BOOL enabled, Class generalButtonClass,
                                                  Class plusButtonClass, Class barBackgroundClass,
                                                  NSUInteger depth) {
    if (!container || depth > 10) return;
    CGFloat barWidth = CGRectGetWidth(tabBar.bounds);
    CGFloat barHeight = CGRectGetHeight(tabBar.bounds);

    for (UIView *subview in [container.subviews copy]) {
        if (DYFSIsTabBarControl(subview, generalButtonClass, plusButtonClass)) continue;

        NSString *name = NSStringFromClass(subview.class);
        CGRect rect = [subview convertRect:subview.bounds toView:tabBar];
        CGFloat width = CGRectGetWidth(rect);
        CGFloat height = CGRectGetHeight(rect);
        CGFloat minX = CGRectGetMinX(rect);
        CGFloat minY = CGRectGetMinY(rect);

        BOOL namedBackground = (barBackgroundClass && [subview isKindOfClass:barBackgroundClass]) ||
            [name containsString:@"Background"] || [name containsString:@"Backdrop"] ||
            [name containsString:@"Blur"] || [subview isKindOfClass:UIVisualEffectView.class];
        BOOL fillsBar = barWidth > 0.0 && barHeight > 0.0 &&
            width >= barWidth * 0.88 && minX <= barWidth * 0.06 &&
            height >= MAX(24.0, barHeight * 0.40) && height <= barHeight * 1.35 &&
            minY <= barHeight * 0.38 && CGRectGetMaxY(rect) >= barHeight * 0.50;
        BOOL plainFullBarBackground = [subview isMemberOfClass:UIView.class] &&
            fillsBar && !DYFSContainsTabBarControl(subview, generalButtonClass, plusButtonClass, 0);
        BOOL divider = height > 0.0 && height < 1.2 && width >= barWidth * 0.75;

        if (namedBackground || plainFullBarBackground || divider) {
            subview.hidden = enabled;
            if (namedBackground || plainFullBarBackground) subview.backgroundColor = UIColor.clearColor;
        }
        if (!subview.hidden) {
            DYFSApplyTabBarBackgroundsRecursively(subview, tabBar, enabled, generalButtonClass,
                                                   plusButtonClass, barBackgroundClass, depth + 1);
        }
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

    // Hide only the tab bar's background layers on every tab. Buttons remain
    // visible/tappable; the selected tab does not change transparency behavior.
    id skinContainer = DYFSSafeValueForKey(tabBar, @"skinContainerView");
    if ([skinContainer isKindOfClass:UIView.class]) {
        ((UIView *)skinContainer).hidden = enabled;
    }

    BOOL shouldHideBackgrounds = enabled;
    CGFloat barHeight = CGRectGetHeight(tabBar.bounds);
    if (barHeight <= 0.0 || !isfinite(barHeight)) {
        barHeight = 49.0 + MAX(0.0, tabBar.window.safeAreaInsets.bottom);
    }

    DYFSApplyTabBarBackgroundsRecursively(tabBar, tabBar, shouldHideBackgrounds,
                                          generalButtonClass, plusButtonClass,
                                          barBackgroundClass, 0);

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

static void DYFSTabBarDidMoveToWindow(id self, SEL cmd) {
    if (DYFSOriginalTabBarDidMove) ((void (*)(id, SEL))DYFSOriginalTabBarDidMove)(self, cmd);
    DYFSApplyTabBarTransparency((UIView *)self);
}

static void DYFSTabBarDidAddSubview(id self, SEL cmd, UIView *subview) {
    if (DYFSOriginalTabBarDidAddSubview) ((void (*)(id, SEL, UIView *))DYFSOriginalTabBarDidAddSubview)(self, cmd, subview);
    DYFSApplyTabBarTransparency((UIView *)self);
}

// Douyin's full-screen mode can expose dark one-pixel/background views inside
// either progress-bar wrapper as a full-width black line. Keep the correction
// scoped to progress-container children only; never resize or recolor controls.
static void DYFSInteractionProgressLayout(id self, SEL cmd) {
    if (DYFSOriginalInteractionProgressLayout) {
        ((void (*)(id, SEL))DYFSOriginalInteractionProgressLayout)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;

    UIView *container = (UIView *)self;
    for (UIView *subview in [container.subviews copy]) {
        if ([subview class] == UIView.class) {
            subview.backgroundColor = UIColor.clearColor;
        }
    }
}

static void DYFSPlayerProgressLayout(id self, SEL cmd) {
    if (DYFSOriginalPlayerProgressLayout) {
        ((void (*)(id, SEL))DYFSOriginalPlayerProgressLayout)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;

    UIView *container = (UIView *)self;
    for (UIView *subview in [container.subviews copy]) {
        if (![subview isMemberOfClass:UIView.class]) continue;

        UIColor *background = subview.backgroundColor;
        if (!background) continue;
        CGFloat hue = 0.0, saturation = 0.0, brightness = 1.0, alpha = 1.0;
        if ([background getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha] &&
            brightness < 0.2) {
            subview.backgroundColor = UIColor.clearColor;
        }
    }
}

static UIView *DYFSFindCommentInputBar(UIView *root) {
    if (!root) return nil;
    UIView *fallback = nil;
    CGFloat bestScore = -CGFLOAT_MAX;
    CGFloat rootWidth = CGRectGetWidth(root.bounds);
    CGFloat rootHeight = CGRectGetHeight(root.bounds);
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:root];
    while (pending.count > 0) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        [pending addObjectsFromArray:view.subviews];
        if (view.hidden || view.alpha <= 0.01) continue;
        if (DYFSIsCommentDockView(view)) return view;
        CGRect rect = [view convertRect:view.bounds toView:root];
        CGFloat width = CGRectGetWidth(rect);
        CGFloat height = CGRectGetHeight(rect);
        CGFloat bottomGap = rootHeight - CGRectGetMaxY(rect);
        if (width < rootWidth * 0.78 || height < 42.0 || height > 150.0 ||
            bottomGap < -3.0 || bottomGap > 180.0) continue;
        CGFloat score = width / MAX(1.0, rootWidth) * 3.0 -
            fabs(height - 68.0) / 100.0 - fabs(bottomGap) / 180.0;
        if (score > bestScore) { bestScore = score; fallback = view; }
    }
    return fallback;
}

static void DYFSClearCommentInputBackgrounds(UIView *view, NSUInteger depth) {
    if (!view || depth > 8) return;
    DYFSClearCommentDockBackground(view, depth);
    DYFSClearOverlappingBackgroundSiblings(view, view.superview ?: view, 180.0);
}

static void DYFSCommentPanelLayout(id self, SEL cmd) {
    if (DYFSOriginalCommentPanelLayout) {
        ((void (*)(id, SEL))DYFSOriginalCommentPanelLayout)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;

    UIViewController *controller = (UIViewController *)self;
    UIView *root = controller.view;
    UIView *bar = DYFSFindCommentInputBar(root);
    if (!bar) return;

    DYFSClearCommentInputBackgrounds(bar, 0);
    DYFSCommentBarTransparencyApplyCount++;
}

static void DYFSCommentInputContainerLayout(id self, SEL cmd) {
    if (DYFSOriginalCommentInputContainerLayout) {
        ((void (*)(id, SEL))DYFSOriginalCommentInputContainerLayout)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;
    UIView *view = (UIView *)self;
    DYFSClearCommentDockBackground(view, 0);
    DYFSClearOverlappingBackgroundSiblings(view, view.superview ?: view, 180.0);
    DYFSCommentBarTransparencyApplyCount++;
}

static void DYFSCommentInputBackgroundLayout(id self, SEL cmd) {
    if (DYFSOriginalCommentInputBackgroundLayout) {
        ((void (*)(id, SEL))DYFSOriginalCommentInputBackgroundLayout)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;
    UIView *view = (UIView *)self;
    DYFSClearCommentDockBackground(view, 0);
    DYFSClearOverlappingBackgroundSiblings(view, view.superview ?: view, 180.0);
    DYFSCommentBarTransparencyApplyCount++;
}

static void DYFSCommentInputControllerLayout(id self, SEL cmd) {
    if (DYFSOriginalCommentInputControllerLayout) {
        ((void (*)(id, SEL))DYFSOriginalCommentInputControllerLayout)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;
    UIViewController *controller = (UIViewController *)self;
    DYFSApplyVideoDetailBottomTransparencyInView(controller.view);
    if (controller.view.superview) {
        DYFSApplyVideoDetailBottomTransparencyInView(controller.view.superview);
    }
}

static void DYFSFeedTableLayout(id self, SEL cmd) {
    if (DYFSOriginalFeedLayout) ((void (*)(id, SEL))DYFSOriginalFeedLayout)(self, cmd);
    if (!DYFSIsEnabled()) return;

    UIView *view = (UIView *)self;
    UIView *parent = view.superview;
    if (!parent || DYFSInProfileContext(view) || DYFSIsLivePreStreamContext(view)) return;
    CGRect frame = view.frame;
    CGFloat targetHeight = CGRectGetHeight(parent.bounds);
    if (!isfinite(targetHeight) || targetHeight <= 1.0) return;
    if (fabs(CGRectGetHeight(frame) - targetHeight) <= 0.5 &&
        fabs(CGRectGetMinY(frame)) <= 0.5) return;

    CGFloat oldHeight = CGRectGetHeight(frame);
    CGFloat oldY = CGRectGetMinY(frame);
    frame.origin.y = 0.0;
    frame.size.height = targetHeight;
    view.frame = frame;
    DYFSLayoutFixCount++;
    DYFSLog([NSString stringWithFormat:@"AWEFeedTableView frame y %.2f -> %.2f, height %.2f -> %.2f",
             oldY, CGRectGetMinY(frame), oldHeight, targetHeight]);
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
                    (IMP)DYFSStoryContainerLayout, &DYFSOriginalStoryLayout);
    }

    cls = NSClassFromString(@"AWEPlayInteractionViewController");
    if (!DYFSInstalledInteractionController && cls) {
        DYFSInstalledInteractionController = DYFSInstallHook(cls, @selector(viewDidLayoutSubviews),
                    (IMP)DYFSInteractionControllerLayout, &DYFSOriginalInteractionControllerLayout);
    }

    cls = NSClassFromString(@"AWEAwemePlayVideoViewController");
    if (!DYFSInstalledPlayerContentA && cls) {
        DYFSInstalledPlayerContentA = DYFSInstallHook(cls, @selector(viewDidLayoutSubviews),
                    (IMP)DYFSPlayerContentLayoutA, &DYFSOriginalPlayerContentA);
    }

    cls = NSClassFromString(@"AWEDPlayerFeedPlayerViewController");
    if (!DYFSInstalledPlayerContentB && cls) {
        DYFSInstalledPlayerContentB = DYFSInstallHook(cls, @selector(viewDidLayoutSubviews),
                    (IMP)DYFSPlayerContentLayoutB, &DYFSOriginalPlayerContentB);
    }

    cls = NSClassFromString(@"AWEDPlayerViewController_Merge");
    if (!DYFSInstalledPlayerContentC && cls) {
        DYFSInstalledPlayerContentC = DYFSInstallHook(cls, @selector(viewDidLayoutSubviews),
                    (IMP)DYFSPlayerContentLayoutC, &DYFSOriginalPlayerContentC);
    }

    cls = NSClassFromString(@"AWEElementStackView");
    if (!DYFSInstalledLiveStack && cls) {
        DYFSInstalledLiveStack = DYFSInstallHook(cls, @selector(layoutSubviews),
                    (IMP)DYFSLiveElementStackLayout, &DYFSOriginalLiveStackLayout);
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


    DYFSSettingsEntryVisible = NO;
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        DYFSScanForSettingsEntry(window, 0);
        if (DYFSSettingsEntryVisible) break;
    }

    cls = NSClassFromString(@"AWEPlayInteractionProgressContainerView");
    if (cls && !DYFSInstalledInteractionProgress) {
        DYFSInstalledInteractionProgress = DYFSInstallHook(cls, @selector(layoutSubviews),
                    (IMP)DYFSInteractionProgressLayout, &DYFSOriginalInteractionProgressLayout);
    }

    cls = NSClassFromString(@"AWEDPlayerProgressContainerView");
    if (cls && !DYFSInstalledPlayerProgress) {
        DYFSInstalledPlayerProgress = DYFSInstallHook(cls, @selector(layoutSubviews),
                    (IMP)DYFSPlayerProgressLayout, &DYFSOriginalPlayerProgressLayout);
    }

    cls = NSClassFromString(@"AWECommentPanelContainerSwiftImpl.CommentContainerInnerViewController");
    if (cls && !DYFSInstalledCommentPanel) {
        DYFSInstalledCommentPanel = DYFSInstallHook(cls, @selector(viewDidLayoutSubviews),
                    (IMP)DYFSCommentPanelLayout, &DYFSOriginalCommentPanelLayout);
    }

    cls = NSClassFromString(@"AWECommentInputViewSwiftImpl.CommentInputContainerView");
    if (cls && !DYFSInstalledCommentInputContainer) {
        DYFSInstalledCommentInputContainer = DYFSInstallHook(cls, @selector(layoutSubviews),
            (IMP)DYFSCommentInputContainerLayout, &DYFSOriginalCommentInputContainerLayout);
    }

    cls = NSClassFromString(@"AWECommentInputBackgroundView");
    if (cls && !DYFSInstalledCommentInputBackground) {
        DYFSInstalledCommentInputBackground = DYFSInstallHook(cls, @selector(layoutSubviews),
            (IMP)DYFSCommentInputBackgroundLayout, &DYFSOriginalCommentInputBackgroundLayout);
    }

    cls = NSClassFromString(@"AWECommentInputViewController");
    if (cls && !DYFSInstalledCommentInputController) {
        DYFSInstalledCommentInputController = DYFSInstallHook(cls, @selector(viewDidLayoutSubviews),
            (IMP)DYFSCommentInputControllerLayout, &DYFSOriginalCommentInputControllerLayout);
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

    cls = NSClassFromString(@"AWENormalModeTabBar");
    if (cls) {
        if (!DYFSInstalledTabBarDidMove) {
            DYFSInstalledTabBarDidMove = DYFSInstallHook(cls, @selector(didMoveToWindow),
                (IMP)DYFSTabBarDidMoveToWindow, &DYFSOriginalTabBarDidMove);
        }
        if (!DYFSInstalledTabBarDidAddSubview) {
            DYFSInstalledTabBarDidAddSubview = DYFSInstallHook(cls, @selector(didAddSubview:),
                (IMP)DYFSTabBarDidAddSubview, &DYFSOriginalTabBarDidAddSubview);
        }
    }

    cls = NSClassFromString(@"AWEAwemeDetailTableViewController");
    if (cls && !DYFSInstalledDetailTable) {
        DYFSInstalledDetailTable = DYFSInstallHook(cls, @selector(viewDidLayoutSubviews),
            (IMP)DYFSDetailTableLayout, &DYFSOriginalDetailTableLayout);
    }
    cls = NSClassFromString(@"AWEAwemeDetailCellViewController");
    if (cls && !DYFSInstalledDetailCell) {
        DYFSInstalledDetailCell = DYFSInstallHook(cls, @selector(viewDidLayoutSubviews),
            (IMP)DYFSDetailCellLayout, &DYFSOriginalDetailCellLayout);
    }
    cls = NSClassFromString(@"AWEMixVideoPanelDetailTableViewController");
    if (cls && !DYFSInstalledMixPanelDetail) {
        DYFSInstalledMixPanelDetail = DYFSInstallHook(cls, @selector(viewDidLayoutSubviews),
            (IMP)DYFSMixPanelDetailLayout, &DYFSOriginalMixPanelDetailLayout);
    }

    cls = NSClassFromString(@"AWESettingsTableViewController");
    if (cls && !DYFSInstalledNativeSettingsSwitch) {
        DYFSInstalledNativeSettingsSwitch = DYFSInstallHook(cls, @selector(viewDidAppear:),
                    (IMP)DYFSNativeSettingsDidAppear, &DYFSOriginalNativeSettingsDidAppear);
    }

    NSString *summary = [NSString stringWithFormat:@"video-list %@; story-container %@; interaction-controller %@; player-content %d/3; live-copy %@; sidebar hooks %lu/2; tab bar hooks %lu/2; settings-switch %@",
                         DYFSInstalledFeed ? @"on" : @"off", DYFSInstalledStory ? @"on" : @"off",
                         DYFSInstalledInteractionController ? @"on" : @"off",
                         (int)DYFSInstalledPlayerContentA + (int)DYFSInstalledPlayerContentB + (int)DYFSInstalledPlayerContentC,
                         DYFSInstalledLiveStack ? @"on" : @"off",
                         (unsigned long)DYFSSidebarHookCount(), (unsigned long)DYFSTabBarHookCount(),
                         DYFSInstalledNativeSettingsSwitch ? @"on" : @"off"];
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

        BOOL layoutInstalled = DYFSInstalledFeed && DYFSInstalledStory && DYFSInstalledInteractionController;
        BOOL sidebarInstalled = DYFSInstalledSidebarIcon || DYFSInstalledSidebarRight;
        BOOL tabBarInstalled = DYFSInstalledTabBarLayout && DYFSInstalledTabBarHidden;
        BOOL playerLayoutInstalled = DYFSInstalledPlayerContentB || DYFSInstalledPlayerContentC;
        BOOL detailTransparencyInstalled = DYFSInstalledDetailTable || DYFSInstalledDetailCell || DYFSInstalledMixPanelDetail;

        if (!DYFSStartupRelayoutScheduled && layoutInstalled && tabBarInstalled && playerLayoutInstalled) {
            DYFSStartupRelayoutScheduled = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.20 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ DYFSRequestRelayout(); });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.65 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ DYFSRequestRelayout(); });
        }

        if ((!layoutInstalled || !sidebarInstalled || !tabBarInstalled || !DYFSInstalledNativeSettingsSwitch ||
             !playerLayoutInstalled || !DYFSInstalledLiveStack || !detailTransparencyInstalled) && DYFSInstallAttempts < 60) {
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
