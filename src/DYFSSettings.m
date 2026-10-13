//
//  DYFSSettings.m
//  DY.FullScreen
//
//  Settings surfaces: the sidebar entry button, the plugin's own panel with
//  diagnostics, and the switch injected into Douyin's native Settings.
//

#import "DYFSSettings.h"
#import "DYFSCommon.h"
#import "DYFSContext.h"
#import <objc/message.h>

static IMP DYFSOriginalSidebarIconMove = NULL;
static IMP DYFSOriginalSidebarRightMove = NULL;
static IMP DYFSOriginalNativeSettingsDidAppear = NULL;

static const NSInteger kDYFSSettingsEntryButtonTag = 420740;
static const CGFloat kDYFSSettingsEntryButtonWidth = 88.0;
static const CGFloat kDYFSSettingsEntryButtonHeight = 32.0;

// 原生设置项注入的重试策略：抖音可能在 viewDidAppear 之后才填充 sectionDataArray
static const NSUInteger kDYFSNativeSettingsRetryCount = 8;
static const NSTimeInterval kDYFSNativeSettingsRetryInterval = 0.25;
// 侧边栏图标布局完成前挂载入口可能取到错误坐标
static const NSTimeInterval kDYFSEntryMountDelay = 0.3;

static NSString *DYFSStatusText(void) {
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"未知";
    return [NSString stringWithFormat:
        @"抖音版本：%@（测试版本 %@）\n全屏开关：%@\n首页视频列表 Hook：%@\n互动控制器 Hook：%@\n互动层调整次数：%lu\n播放器画面调整次数：%lu\n推流预览播放器调整次数：%lu\n底栏透明 Hook：%lu/2\n侧边栏入口 Hook：%lu/2\n侧边栏全屏入口：%@\n原生设置页开关 Hook：%@\n原生设置页全屏开关：%@\n当前首页 Tab 选中：%@\n底栏背景已隐藏：%@\n底栏布局处理次数：%lu\n视频列表布局调整次数：%lu\n直播卡片 Hook：%@\n直播卡片处理次数：%lu\n直播卡片底部上移次数：%lu\n贴底黑条清理次数：%lu\n播放器画面兜底补高次数：%lu\n\n设置项名称为“启用全屏”。普通视频与图集全屏独立调整；推流预览仅在播放器容器匹配高度条件时调整视频画面，不平移覆盖文案和按钮。\n版本匹配：%@",
        version, DYFSTestedVersion, DYFSIsEnabled() ? @"开启" : @"关闭",
        DYFSInstalledFeed ? @"已安装" : @"未找到类",
        DYFSInstalledInteractionController ? @"已安装" : @"未找到类",
        (unsigned long)DYFSInteractionContainerAdjustCount,
        (unsigned long)DYFSPlayerContentAdjustCount,
        (unsigned long)DYFSLivePreviewPlayerAdjustCount,
        (unsigned long)DYFSTabBarHookCount(),
        (unsigned long)DYFSSidebarHookCount(),
        DYFSSettingsEntryVisible ? @"已挂载" : @"未找到侧边栏设置图标",
        DYFSInstalledNativeSettingsSwitch ? @"已安装" : @"未找到 AWESettingsTableViewController",
        DYFSNativeSettingsRowAdded ? @"已插入" : @"尚未插入（请打开一次抖音设置）",
        DYFSLastHomeTabSelected ? @"是" : @"否",
        DYFSLastTabBackgroundHidden ? @"是" : @"否",
        (unsigned long)DYFSTabBarApplyCount,
        (unsigned long)DYFSLayoutFixCount,
        DYFSLiveCardHookInstalled ? @"已安装" : @"未找到 IESLiveInnerFeedLiveRoomCell",
        (unsigned long)DYFSLiveCardProcessCount,
        (unsigned long)DYFSLiveCardLiftCount,
        (unsigned long)DYFSBottomChromeHideCount,
        (unsigned long)DYFSSetFrameLiftCount,
        DYFSVersionMismatch ? @"不一致，布局可能异常" : @"一致"];
}

// Forward declaration: DYFSSettingsActionTarget below calls into it.
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
    self.title = DYFSSettingsTitle;
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = DYFSSettingsTitle;
    titleLabel.font = [UIFont boldSystemFontOfSize:24];
    titleLabel.textColor = UIColor.labelColor;

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
        titleLabel, switchRow, diagnosticsTitle, self.statusLabel, closeButton
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

    // Douyin's sidebar hierarchy depth differs between builds, so walk up a
    // bounded number of levels and pick the nearest ancestor that can actually
    // host the entry button, instead of assuming a fixed three-level jump.
    CGFloat neededWidth = kDYFSSettingsEntryButtonWidth + 12.0;
    CGFloat neededHeight = kDYFSSettingsEntryButtonHeight + 8.0;
    UIView *targetSuperView = nil;
    for (UIView *cursor = settingsIcon.superview; cursor; cursor = cursor.superview) {
        if ([cursor isKindOfClass:UIWindow.class]) break;
        if (CGRectGetWidth(cursor.bounds) >= neededWidth &&
            CGRectGetHeight(cursor.bounds) >= neededHeight) {
            targetSuperView = cursor;
            break;
        }
    }
    if (!targetSuperView) targetSuperView = settingsIcon.superview ?: settingsIcon;
    if (!targetSuperView) return;

    UIButton *button = (UIButton *)[targetSuperView viewWithTag:kDYFSSettingsEntryButtonTag];
    if (![button isKindOfClass:UIButton.class]) button = nil;

    // Convert the anchor's bounds into the coordinate space of the actual
    // superview that will contain the button; using settingsIcon.frame directly
    // here mixes coordinate systems and can place the entry off-screen.
    CGRect anchorFrame = [settingsIcon convertRect:settingsIcon.bounds toView:targetSuperView];
    CGFloat buttonWidth = kDYFSSettingsEntryButtonWidth;
    CGFloat buttonHeight = kDYFSSettingsEntryButtonHeight;
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
        button.tag = kDYFSSettingsEntryButtonTag;
        button.accessibilityLabel = @"DY.FullScreen 设置入口";
        button.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.16];
        button.layer.cornerRadius = 8.0;
        button.clipsToBounds = YES;
        [button addTarget:[DYFSSettingsActionTarget sharedTarget]
                   action:@selector(openSettings:)
         forControlEvents:UIControlEventTouchUpInside];
        [targetSuperView addSubview:button];
    }

    [button setTitle:@"全屏设置" forState:UIControlStateNormal];
    [button setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    button.frame = CGRectMake(x, y, buttonWidth, buttonHeight);
    button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;

    DYFSSettingsEntryVisible = YES;
    DYFSLog([NSString stringWithFormat:@"mounted DY.FullScreen entry (parent %.0fx%.0f, frame %@)",
            availableWidth, availableHeight, NSStringFromCGRect(button.frame)]);
}

void DYFSScanForSettingsEntry(UIView *root, NSUInteger depth) {
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

static void DYFSEnsureNativeSettingsSwitch(UIViewController *controller) {
    Class settingsClass = NSClassFromString(kDYFSClassSettings);
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
            DYFSSafeSetValueForKey(item, DYFSSettingsTitle, @"title");
            // Clear secondary text left behind by earlier plugin versions.
            DYFSSafeSetValueForKey(item, @"", @"subTitle");
            DYFSSafeSetValueForKey(item, @"", @"subtitle");
            DYFSSafeSetValueForKey(item, @"", @"detail");
            DYFSSafeSetValueForKey(item, @(DYFSIsEnabled()), @"isSwitchOn");
            // Existing rows can already have a cached native settings cell; reload after renaming.
            id existingTableView = DYFSSafeValueForKey(controller, @"tableView");
            if ([existingTableView isKindOfClass:UITableView.class]) {
                [(UITableView *)existingTableView reloadData];
            }
            DYFSNativeSettingsRowAdded = YES;
            return;
        }
    }

    Class itemClass = NSClassFromString(kDYFSClassSettingItemModel);
    Class sectionClass = NSClassFromString(kDYFSClassSettingSectionModel);
    if (!itemClass || !sectionClass) {
        DYFSLog(@"native settings item/section classes not found");
        return;
    }

    id item = [[itemClass alloc] init];
    DYFSSafeSetValueForKey(item, itemIdentifier, @"identifier");
    DYFSSafeSetValueForKey(item, DYFSSettingsTitle, @"title");
    DYFSSafeSetValueForKey(item, @"", @"subTitle");
    DYFSSafeSetValueForKey(item, @"", @"subtitle");
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

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDYFSNativeSettingsRetryInterval * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        DYFSRetryNativeSettingsSwitch(controller, attemptsLeft - 1);
    });
}

void DYFSNativeSettingsDidAppear(id self, SEL cmd, BOOL animated) {
    if (DYFSOriginalNativeSettingsDidAppear) {
        ((void (*)(id, SEL, BOOL))DYFSOriginalNativeSettingsDidAppear)(self, cmd, animated);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        // Re-check each time Settings opens. Douyin can populate sectionDataArray
        // after viewDidAppear, so retry briefly instead of waiting for a reopen.
        DYFSNativeSettingsRowAdded = NO;
        DYFSRetryNativeSettingsSwitch((UIViewController *)self, kDYFSNativeSettingsRetryCount);
    });
}

void DYFSLeftSidebarIconDidMove(id self, SEL cmd) {
    if (DYFSOriginalSidebarIconMove) ((void (*)(id, SEL))DYFSOriginalSidebarIconMove)(self, cmd);
    UIView *view = (UIView *)self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDYFSEntryMountDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        DYFSInstallSettingsEntry(view);
    });
}

void DYFSLeftSidebarRightDidMove(id self, SEL cmd) {
    if (DYFSOriginalSidebarRightMove) ((void (*)(id, SEL))DYFSOriginalSidebarRightMove)(self, cmd);
    UIView *view = (UIView *)self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kDYFSEntryMountDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        DYFSInstallSettingsEntry(view);
    });
}


void DYFSSettingsInstallHooks(void) {
    Class cls = NSClassFromString(kDYFSClassSidebarIcon);
    if (!DYFSInstalledSidebarIcon && cls) {
        DYFSInstalledSidebarIcon = DYFSInstallHook(cls, @selector(didMoveToSuperview),
                    (IMP)DYFSLeftSidebarIconDidMove, &DYFSOriginalSidebarIconMove);
    }

    cls = NSClassFromString(kDYFSClassSidebarRight);
    if (!DYFSInstalledSidebarRight && cls) {
        DYFSInstalledSidebarRight = DYFSInstallHook(cls, @selector(didMoveToSuperview),
                    (IMP)DYFSLeftSidebarRightDidMove, &DYFSOriginalSidebarRightMove);
    }

    cls = NSClassFromString(kDYFSClassSettings);
    if (cls && !DYFSInstalledNativeSettingsSwitch) {
        DYFSInstalledNativeSettingsSwitch = DYFSInstallHook(cls, @selector(viewDidAppear:),
                    (IMP)DYFSNativeSettingsDidAppear, &DYFSOriginalNativeSettingsDidAppear);
    }

    // Re-scan every pass: the sidebar may not exist yet on early attempts.
    DYFSSettingsEntryVisible = NO;
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        DYFSScanForSettingsEntry(window, 0);
        if (DYFSSettingsEntryVisible) break;
    }
}
