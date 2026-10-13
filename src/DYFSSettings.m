//
//  DYFSSettings.m
//  DY.FullScreen
//
//  设置入口：侧边栏按钮、插件自身的诊断面板、注入抖音原生设置的开关。
//

#import "DYFSSettings.h"
#import "DYFSCommon.h"
#import "DYFSContext.h"
#import <objc/message.h>

static IMP DYFSOriginalNativeSettingsDidAppear = NULL;

// 下面的 UI 类会用到这两个函数，而它们定义在文件后半部分，需要先声明。
static NSString *DYFSStatusText(void);
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
    titleLabel.text = @"DY.FullScreen";
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


static NSString *DYFSStatusText(void) {
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"未知";
    return [NSString stringWithFormat:
        @"抖音版本：%@\n全屏开关：%@\n首页视频列表 Hook：%@\n互动控制器 Hook：%@\n互动层调整次数：%lu\n播放器画面调整次数：%lu\n底栏透明 Hook：%lu/2\n原生设置页开关 Hook：%@\n原生设置页全屏开关：%@\n当前首页 Tab 选中：%@\n底栏背景已隐藏：%@\n底栏布局处理次数：%lu\n视频列表布局调整次数：%lu\n\n设置项名称为“视频全屏启动”，位于抖音「设置」页内。普通视频与图集全屏独立调整。评论页面底部输入栏背景透明处理次数：%lu。",
        version, DYFSIsEnabled() ? @"开启" : @"关闭",
        DYFSInstalledFeed ? @"已安装" : @"未找到类",
        DYFSInstalledInteractionController ? @"已安装" : @"未找到类",
        (unsigned long)DYFSInteractionContainerAdjustCount,
        (unsigned long)DYFSPlayerContentAdjustCount,
        (unsigned long)DYFSTabBarHookCount(),
        DYFSInstalledNativeSettingsSwitch ? @"已安装" : @"未找到 AWESettingsTableViewController",
        DYFSNativeSettingsRowAdded ? @"已插入" : @"尚未插入（请打开一次抖音设置）",
        DYFSLastHomeTabSelected ? @"是" : @"否",
        DYFSLastTabBackgroundHidden ? @"是" : @"否",
        (unsigned long)DYFSTabBarApplyCount,
        (unsigned long)DYFSLayoutFixCount,
        (unsigned long)DYFSCommentBarTransparencyApplyCount];
}

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





static NSString * const kDYFSDiagnosticsIdentifier = @"com.dy.fullscreen.diagnostics";

// 尝试给设置项挂点击回调。抖音各版本的 AWESettingItemModel 属性名不一样，
// 逐个试，成功即止；都失败也不影响开关本身，只是诊断行点不开。
static BOOL DYFSAttachRowAction(id item, void (^action)(void)) {
    NSArray<NSString *> *candidates = @[@"actionBlock", @"cellClickBlock", @"clickBlock",
                                        @"didSelectBlock", @"selectBlock", @"tapBlock",
                                        @"block", @"eventBlock"];
    for (NSString *key in candidates) {
        if (DYFSSafeSetValueForKey(item, [action copy], key)) {
            DYFSLog([NSString stringWithFormat:@"diagnostics row action attached via %@", key]);
            return YES;
        }
    }
    DYFSLog(@"diagnostics row action not attached (unknown AWESettingItemModel key)");
    return NO;
}

// 诊断行：点击后弹出内置诊断面板（Hook 安装状态 + 各类命中次数）。
static id DYFSMakeDiagnosticsItem(Class itemClass) {
    id item = [[itemClass alloc] init];
    DYFSSafeSetValueForKey(item, kDYFSDiagnosticsIdentifier, @"identifier");
    DYFSSafeSetValueForKey(item, @"运行诊断", @"title");
    DYFSSafeSetValueForKey(item, @"DY.FullScreen", @"subTitle");
    DYFSSafeSetValueForKey(item, @"查看 Hook 安装状态与命中次数", @"detail");
    DYFSSafeSetValueForKey(item, @1, @"cellType");
    DYFSSafeSetValueForKey(item, @0, @"colorStyle");
    DYFSSafeSetValueForKey(item, @YES, @"isEnable");
    DYFSAttachRowAction(item, ^{
        DYFSOpenSettings(nil);
    });
    return item;
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
    NSString *switchIdentifier = DYFSEnabledKey;
    NSString *diagIdentifier = kDYFSDiagnosticsIdentifier;

    // 已经插过的话只刷新文案，不重复插入。
    BOOL foundSwitch = NO, foundDiag = NO;
    for (id section in sections) {
        id rawItems = DYFSSafeValueForKey(section, @"itemArray");
        if (![rawItems isKindOfClass:NSArray.class]) continue;
        for (id item in (NSArray *)rawItems) {
            NSString *identifier = DYFSSafeValueForKey(item, @"identifier");
            if ([identifier isEqualToString:switchIdentifier]) {
                DYFSSafeSetValueForKey(item, @"视频全屏启动", @"title");
                DYFSSafeSetValueForKey(item, @"DY.FullScreen", @"subTitle");
                DYFSSafeSetValueForKey(item, @"", @"detail");
                DYFSSafeSetValueForKey(item, @(DYFSIsEnabled()), @"isSwitchOn");
                foundSwitch = YES;
            } else if ([identifier isEqualToString:diagIdentifier]) {
                DYFSSafeSetValueForKey(item, @"运行诊断", @"title");
                DYFSSafeSetValueForKey(item, @"DY.FullScreen", @"subTitle");
                DYFSSafeSetValueForKey(item, @"查看 Hook 安装状态与命中次数", @"detail");
                foundDiag = YES;
            }
        }
    }

    id tableView = DYFSSafeValueForKey(controller, @"tableView");
    if (foundSwitch && foundDiag) {
        if ([tableView isKindOfClass:UITableView.class]) [(UITableView *)tableView reloadData];
        DYFSNativeSettingsRowAdded = YES;
        return;
    }

    Class itemClass = NSClassFromString(@"AWESettingItemModel");
    Class sectionClass = NSClassFromString(@"AWESettingSectionModel");
    if (!itemClass || !sectionClass) {
        DYFSLog(@"native settings item/section classes not found");
        return;
    }

    NSMutableArray *items = [NSMutableArray array];
    if (!foundSwitch) {
        id item = [[itemClass alloc] init];
        DYFSSafeSetValueForKey(item, switchIdentifier, @"identifier");
        DYFSSafeSetValueForKey(item, @"视频全屏启动", @"title");
        DYFSSafeSetValueForKey(item, @"DY.FullScreen", @"subTitle");
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
        [items addObject:item];
    }
    if (!foundDiag) [items addObject:DYFSMakeDiagnosticsItem(itemClass)];

    id section = [[sectionClass alloc] init];
    DYFSSafeSetValueForKey(section, @"", @"sectionHeaderTitle");
    DYFSSafeSetValueForKey(section, @"", @"sectionFooterTitle");
    DYFSSafeSetValueForKey(section, @0, @"sectionHeaderHeight");
    DYFSSafeSetValueForKey(section, @NO, @"useNewFooterLayout");
    DYFSSafeSetValueForKey(section, @0, @"type");
    DYFSSafeSetValueForKey(section, items, @"itemArray");

    NSMutableArray *updatedSections = [sections mutableCopy];
    [updatedSections insertObject:section atIndex:0];
    if (!DYFSSafeSetValueForKey(viewModel, updatedSections, @"sectionDataArray")) {
        DYFSLog(@"failed to insert native settings section");
        return;
    }

    if ([tableView isKindOfClass:UITableView.class]) [(UITableView *)tableView reloadData];
    DYFSNativeSettingsRowAdded = YES;
    DYFSLog(@"inserted fullscreen switch + diagnostics row in native Douyin Settings");
}

static void DYFSRetryNativeSettingsSwitch(UIViewController *controller, NSUInteger attemptsLeft) {
    DYFSEnsureNativeSettingsSwitch(controller);
    if (DYFSNativeSettingsRowAdded || attemptsLeft == 0) return;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
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
        DYFSRetryNativeSettingsSwitch((UIViewController *)self, 8);
    });
}



void DYFSSettingsInstallHooks(void) {
    // 入口只保留抖音原生「设置」页里的那一行开关（DYYY 同款做法），
    // 左侧栏入口已按需求移除。
    Class cls = NSClassFromString(kDYFSClassSettings);
    if (cls && !DYFSInstalledNativeSettingsSwitch) {
        DYFSInstalledNativeSettingsSwitch = DYFSInstallHook(cls, @selector(viewDidAppear:),
                    (IMP)DYFSNativeSettingsDidAppear, &DYFSOriginalNativeSettingsDidAppear);
    }
}
