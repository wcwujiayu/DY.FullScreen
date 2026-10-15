//
//  DYFSSettings.m
//  DY.FullScreen
//
//  设置入口：抖音原生「设置」页里的「DY.FullScreen」入口行，
//  点击进入二级页（全屏开关唯一 + 运行诊断按钮）；
//  再点运行诊断进入诊断详情（无开关，含关键尺寸）。
//

#import "DYFSSettings.h"
#import "DYFSCommon.h"
#import "DYFSContext.h"
#import "DYFSTapDiagnostic.h"
#import <objc/message.h>

static IMP DYFSOriginalNativeSettingsDidAppear = NULL;
static IMP DYFSOriginalNativeSettingsDidLoad = NULL;

static NSString * const kDYFSTapDiagKey = @"DYFSTapDiagnosticEnabled";

// 下面的 UI 类与函数定义在文件后半部分，先声明。
static NSString *DYFSStatusText(void);
static void DYFSOpenSettings(id sender);
static void DYFSOpenDiagnostics(id sender);

static NSString * const kDYFSEntryIdentifier = @"com.dy.fullscreen.entry";

#pragma mark - 二级页（全屏开关唯一）

@interface DYFSSettingsViewController : UIViewController
@property(nonatomic, strong) UISwitch *enabledSwitch;
@property(nonatomic, strong) UISwitch *tapDiagSwitch;
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

    UILabel *descriptionLabel = [[UILabel alloc] init];
    descriptionLabel.text = @"首页视频与图集全屏、底栏透明设置。适配抖音 40.7.0。";
    descriptionLabel.font = [UIFont systemFontOfSize:14];
    descriptionLabel.textColor = UIColor.secondaryLabelColor;
    descriptionLabel.numberOfLines = 0;

    UILabel *switchTitle = [[UILabel alloc] init];
    switchTitle.text = @"全屏开关";
    switchTitle.font = [UIFont systemFontOfSize:16];
    switchTitle.textColor = UIColor.labelColor;

    self.enabledSwitch = [[UISwitch alloc] init];
    self.enabledSwitch.on = DYFSIsEnabled();
    [self.enabledSwitch addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];

    UIStackView *switchRow = [[UIStackView alloc] initWithArrangedSubviews:@[switchTitle, self.enabledSwitch]];
    switchRow.axis = UILayoutConstraintAxisHorizontal;
    switchRow.alignment = UIStackViewAlignmentCenter;
    switchRow.distribution = UIStackViewDistributionEqualSpacing;

    // 点击诊断开关：定位「我-喜欢 / 收藏」宫格「点 N 打开 N+1」。
    UILabel *tapDiagTitle = [[UILabel alloc] init];
    tapDiagTitle.text = @"点击诊断（定位宫格错位）";
    tapDiagTitle.font = [UIFont systemFontOfSize:16];
    tapDiagTitle.textColor = UIColor.labelColor;
    tapDiagTitle.numberOfLines = 0;

    self.tapDiagSwitch = [[UISwitch alloc] init];
    self.tapDiagSwitch.on = [[NSUserDefaults standardUserDefaults] boolForKey:kDYFSTapDiagKey];
    DYFSTapDiagnosticSetEnabled(self.tapDiagSwitch.on);
    [self.tapDiagSwitch addTarget:self action:@selector(tapDiagChanged:) forControlEvents:UIControlEventValueChanged];

    UIStackView *tapDiagRow = [[UIStackView alloc] initWithArrangedSubviews:@[tapDiagTitle, self.tapDiagSwitch]];
    tapDiagRow.axis = UILayoutConstraintAxisHorizontal;
    tapDiagRow.alignment = UIStackViewAlignmentCenter;
    tapDiagRow.distribution = UIStackViewDistributionEqualSpacing;

    UILabel *tapDiagHint = [[UILabel alloc] init];
    tapDiagHint.text = @"开启后，在「我-喜欢 / 收藏」宫格点任意视频，屏幕顶部会显示点的 item 序号与详情实际加载的作品，用来判断错位发生在点击还是加载。";
    tapDiagHint.font = [UIFont systemFontOfSize:12];
    tapDiagHint.textColor = UIColor.tertiaryLabelColor;
    tapDiagHint.numberOfLines = 0;

    UIButton *diagnosticsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [diagnosticsButton setTitle:@"运行诊断" forState:UIControlStateNormal];
    diagnosticsButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [diagnosticsButton addTarget:self action:@selector(openDiagnosticsTapped) forControlEvents:UIControlEventTouchUpInside];

    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [closeButton setTitle:@"完成" forState:UIControlStateNormal];
    closeButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [closeButton addTarget:self action:@selector(closeSettings) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        titleLabel, descriptionLabel, switchRow, tapDiagRow, tapDiagHint, diagnosticsButton, closeButton
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
    self.preferredContentSize = CGSizeMake(360, 520);
}

- (void)enabledChanged:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:DYFSEnabledKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    DYFSLog(sender.isOn ? @"homepage full-screen enabled" : @"homepage full-screen disabled");
    DYFSRequestRelayout();
}

- (void)tapDiagChanged:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:kDYFSTapDiagKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    DYFSTapDiagnosticSetEnabled(sender.isOn);
    DYFSLog(sender.isOn ? @"tap diagnostic enabled" : @"tap diagnostic disabled");
}

- (void)openDiagnosticsTapped {
    DYFSOpenDiagnostics(nil);
}

- (void)closeSettings {
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end

#pragma mark - 诊断详情（无开关）

@interface DYFSDiagnosticsViewController : UIViewController
@end

@implementation DYFSDiagnosticsViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"运行诊断";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"运行诊断";
    titleLabel.font = [UIFont boldSystemFontOfSize:22];
    titleLabel.textColor = UIColor.labelColor;

    UILabel *statusLabel = [[UILabel alloc] init];
    statusLabel.font = [UIFont systemFontOfSize:13];
    statusLabel.textColor = UIColor.secondaryLabelColor;
    statusLabel.numberOfLines = 0;
    statusLabel.lineBreakMode = NSLineBreakByWordWrapping;
    statusLabel.text = DYFSStatusText();

    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [closeButton setTitle:@"完成" forState:UIControlStateNormal];
    closeButton.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [closeButton addTarget:self action:@selector(closeDiagnostics) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, statusLabel, closeButton]];
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
    self.preferredContentSize = CGSizeMake(360, 500);
}

- (void)closeDiagnostics {
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end

#pragma mark - 诊断文本（含 6 个关键尺寸）

static UIWindow *DYFSKeyWindow(void) {
    UIWindow *window = nil;
    NSArray<UIWindow *> *windows = UIApplication.sharedApplication.windows;
    for (UIWindow *w in windows) {
        if (w.isKeyWindow) { window = w; break; }
    }
    if (!window) window = windows.firstObject;
    return window;
}

// 收集某类视图的所有实例的上边 y 与高度。
static void DYFSCollectFrames(UIView *root, NSString *className,
                              NSMutableArray<NSNumber *> *outYs, NSMutableArray<NSNumber *> *outHs) {
    if (!root) return;
    if ([NSStringFromClass(root.class) isEqualToString:className]) {
        [outYs addObject:@(CGRectGetMinY(root.frame))];
        [outHs addObject:@(CGRectGetHeight(root.frame))];
    }
    for (UIView *sub in root.subviews) {
        DYFSCollectFrames(sub, className, outYs, outHs);
    }
}

static NSString *DYFSStatusText(void) {
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"未知";

    // —— 6 个关键尺寸：只有在视频/文章详情页才有意义 ——
    UIWindow *window = DYFSKeyWindow();
    CGFloat winH = window ? CGRectGetHeight(window.bounds) : 0.0;
    CGFloat tabH = DYFSBottomTabBarHeight(window);

    UIView *table = DYFSFindSubviewOfClass(window, @"AWEAwemeDetailTableView", 0);
    UIView *inter = DYFSFindSubviewOfClass(window, @"AWEPlayInteractionViewController", 0);

    NSMutableArray<NSNumber *> *cellYs = [NSMutableArray array];
    NSMutableArray<NSNumber *> *cellHs = [NSMutableArray array];
    DYFSCollectFrames(window, @"AWEAwemeDetailTableViewCell", cellYs, cellHs);
    [cellYs sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"self" ascending:YES]]];

    CGFloat cellH = cellHs.count ? [cellHs.firstObject doubleValue] : 0.0;
    CGFloat cellGap = 0.0;
    if (cellYs.count >= 2) {
        cellGap = [cellYs[1] doubleValue] - [cellYs[0] doubleValue];
    }
    CGFloat tableH = table ? CGRectGetHeight(table.bounds) : 0.0;
    CGFloat interH = inter ? CGRectGetHeight(inter.bounds) : 0.0;

    NSString *(^fmt)(CGFloat) = ^NSString *(CGFloat v) {
        return v > 0.5 ? [NSString stringWithFormat:@"%.0f", v] : @"不适用";
    };

    NSString *metrics = [NSString stringWithFormat:
        @"窗口高 winH：       %@\n"
        @"底栏高 tabH：       %@\n"
        @"详情表格可视高：     %@\n"
        @"cell 高度：         %@\n"
        @"cell 相邻间距：      %@\n"
        @"互动层高度：         %@\n"
        @"(显示「不适用」表示当前不在视频/文章详情页)",
        fmt(winH), fmt(tabH), fmt(tableH), fmt(cellH), fmt(cellGap), fmt(interH)];

    return [NSString stringWithFormat:
        @"抖音版本：%@\n全屏开关：%@\n\n"
        @"— 关键尺寸（当前页面）—\n%@\n\n"
        @"首页视频列表 Hook：%@\n互动控制器 Hook：%@\n"
        @"互动层调整次数：%lu\n播放器画面调整次数：%lu\n"
        @"底栏透明 Hook：%lu/2\n原生设置页入口 Hook：%@\n"
        @"原生设置页入口：%@\n当前首页 Tab 选中：%@\n"
        @"底栏背景已隐藏：%@\n底栏布局处理次数：%lu\n"
        @"视频列表布局调整次数：%lu\n\n"
        @"设置入口为「DY.FullScreen」，位于抖音「设置」页内，点进去是二级页（全屏开关唯一）。",
        version, DYFSIsEnabled() ? @"开启" : @"关闭", metrics,
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
        (unsigned long)DYFSLayoutFixCount];
}

#pragma mark - 打开入口 / 诊断

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

static void DYFSOpenDiagnostics(id sender) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *senderView = [sender isKindOfClass:UIView.class] ? (UIView *)sender : nil;
        UIViewController *target = senderView ? DYFSFindViewController(senderView) : nil;
        if (!target) target = DYFSActiveTopViewController();
        if (!target) {
            DYFSLog(@"cannot present diagnostics: no visible view controller");
            return;
        }
        if ([target isKindOfClass:DYFSDiagnosticsViewController.class]) return;
        DYFSDiagnosticsViewController *diag = [[DYFSDiagnosticsViewController alloc] init];
        diag.modalPresentationStyle = UIModalPresentationPageSheet;
        [target presentViewController:diag animated:YES completion:nil];
    });
}

#pragma mark - 原生设置页入口行

// 尝试给设置项挂点击回调。AWESettingItemModel 的属性名随抖音版本变化，逐个试。
static BOOL DYFSAttachRowAction(id item, void (^action)(void)) {
    NSArray<NSString *> *candidates = @[@"cellTappedBlock", @"actionBlock", @"cellClickBlock",
                                        @"clickBlock", @"didSelectBlock", @"selectBlock",
                                        @"tapBlock", @"block", @"eventBlock"];
    for (NSString *key in candidates) {
        if (DYFSSafeSetValueForKey(item, [action copy], key)) {
            DYFSLog([NSString stringWithFormat:@"entry row action attached via %@", key]);
            return YES;
        }
    }
    DYFSLog(@"entry row action not attached (unknown AWESettingItemModel key)");
    return NO;
}

// 入口行：点击进入二级页。
static id DYFSMakeEntryItem(Class itemClass) {
    id item = [[itemClass alloc] init];
    DYFSSafeSetValueForKey(item, kDYFSEntryIdentifier, @"identifier");
    DYFSSafeSetValueForKey(item, DYFSSettingsTitle, @"title");
    DYFSSafeSetValueForKey(item, @"全屏与底栏透明", @"subTitle");
    DYFSSafeSetValueForKey(item, @"视频与图集全屏、底栏透明设置", @"detail");
    // cellType 20 = 可点击的普通行（DYYY 同款）；colorStyle 2 与抖音原生一致。
    DYFSSafeSetValueForKey(item, @20, @"cellType");
    DYFSSafeSetValueForKey(item, @2, @"colorStyle");
    DYFSSafeSetValueForKey(item, @YES, @"isEnable");
    DYFSAttachRowAction(item, ^{
        DYFSOpenSettings(nil);
    });
    return item;
}

static void DYFSEnsureNativeSettingsEntry(UIViewController *controller) {
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

    // 已经插过的话只刷新文案，不重复插入。
    BOOL foundEntry = NO;
    for (id section in sections) {
        id rawItems = DYFSSafeValueForKey(section, @"itemArray");
        if (![rawItems isKindOfClass:NSArray.class]) continue;
        for (id item in (NSArray *)rawItems) {
            NSString *identifier = DYFSSafeValueForKey(item, @"identifier");
            if ([identifier isEqualToString:kDYFSEntryIdentifier]) {
                DYFSSafeSetValueForKey(item, @"DY.FullScreen", @"title");
                DYFSSafeSetValueForKey(item, @"全屏与底栏透明", @"subTitle");
                DYFSSafeSetValueForKey(item, @"视频与图集全屏、底栏透明设置", @"detail");
                foundEntry = YES;
            }
        }
    }

    id tableView = DYFSSafeValueForKey(controller, @"tableView");
    if (foundEntry) {
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

    id section = [[sectionClass alloc] init];
    DYFSSafeSetValueForKey(section, @"", @"sectionHeaderTitle");
    DYFSSafeSetValueForKey(section, @"", @"sectionFooterTitle");
    DYFSSafeSetValueForKey(section, @0, @"sectionHeaderHeight");
    DYFSSafeSetValueForKey(section, @NO, @"useNewFooterLayout");
    DYFSSafeSetValueForKey(section, @0, @"type");
    DYFSSafeSetValueForKey(section, @[DYFSMakeEntryItem(itemClass)], @"itemArray");

    NSMutableArray *updatedSections = [sections mutableCopy];
    [updatedSections insertObject:section atIndex:0];
    if (!DYFSSafeSetValueForKey(viewModel, updatedSections, @"sectionDataArray")) {
        DYFSLog(@"failed to insert native settings entry section");
        return;
    }

    if ([tableView isKindOfClass:UITableView.class]) [(UITableView *)tableView reloadData];
    DYFSNativeSettingsRowAdded = YES;
    DYFSLog(@"inserted DY.FullScreen entry in native Douyin Settings");
}

// 抖音的 sectionDataArray 常在 viewDidAppear 之后才填充完，所以要重试。
static void DYFSRetryNativeSettingsEntry(UIViewController *controller, NSUInteger attemptsLeft) {
    DYFSEnsureNativeSettingsEntry(controller);
    if (DYFSNativeSettingsRowAdded || attemptsLeft == 0) return;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        DYFSRetryNativeSettingsEntry(controller, attemptsLeft - 1);
    });
}

// 注入尽量提前：viewDidLoad 就试一次，能赶在首屏渲染前插好。
static void DYFSNativeSettingsDidLoad(id self, SEL cmd) {
    if (DYFSOriginalNativeSettingsDidLoad) {
        ((void (*)(id, SEL))DYFSOriginalNativeSettingsDidLoad)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;
    DYFSEnsureNativeSettingsEntry((UIViewController *)self);
}

void DYFSNativeSettingsDidAppear(id self, SEL cmd, BOOL animated) {
    if (DYFSOriginalNativeSettingsDidAppear) {
        ((void (*)(id, SEL, BOOL))DYFSOriginalNativeSettingsDidAppear)(self, cmd, animated);
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        // Re-check each time Settings opens. Douyin can populate sectionDataArray
        // after viewDidAppear, so retry briefly instead of waiting for a reopen.
        DYFSNativeSettingsRowAdded = NO;
        DYFSRetryNativeSettingsEntry((UIViewController *)self, 30);
    });
}

void DYFSSettingsInstallHooks(void) {
    // 入口只在抖音原生「设置」页里插入一行「DY.FullScreen」（点击进入二级页），
    // 二级页里才是唯一的全屏开关 + 运行诊断按钮。
    Class cls = NSClassFromString(kDYFSClassSettings);
    if (cls) {
        if (!DYFSInstalledNativeSettingsSwitch) {
            DYFSInstalledNativeSettingsSwitch = DYFSInstallHook(cls, @selector(viewDidAppear:),
                        (IMP)DYFSNativeSettingsDidAppear, &DYFSOriginalNativeSettingsDidAppear);
        }
        // viewDidLoad 提前注入，减少入口行"过一会儿才出现"的延迟。
        if (!DYFSOriginalNativeSettingsDidLoad) {
            DYFSInstallHook(cls, @selector(viewDidLoad),
                            (IMP)DYFSNativeSettingsDidLoad, &DYFSOriginalNativeSettingsDidLoad);
        }
    }
}
