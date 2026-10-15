//
//  DYFSCommon.m
//  DY.FullScreen
//
//  Shared constants, runtime helpers and cross-module state.
//

#import "DYFSCommon.h"
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>

// 抖音私有类名集中清单（改版时只需改这里）
NSString * const kDYFSClassFeedTableView = @"AWEFeedTableView";
NSString * const kDYFSClassStoryContainer = @"AWEStoryContainerCollectionView";
NSString * const kDYFSClassPlayInteraction = @"AWEPlayInteractionViewController";
NSString * const kDYFSClassPlayVideoA = @"AWEAwemePlayVideoViewController";
NSString * const kDYFSClassPlayVideoB = @"AWEDPlayerFeedPlayerViewController";
NSString * const kDYFSClassPlayVideoC = @"AWEDPlayerViewController_Merge";
NSString * const kDYFSClassInteractionProgress = @"AWEPlayInteractionProgressContainerView";
NSString * const kDYFSClassPlayerProgress = @"AWEDPlayerProgressContainerView";
NSString * const kDYFSClassTabBar = @"AWENormalModeTabBar";
NSString * const kDYFSClassTabBarGeneralButton = @"AWENormalModeTabBarGeneralButton";
NSString * const kDYFSClassTabBarGeneralPlusButton = @"AWENormalModeTabBarGeneralPlusButton";
NSString * const kDYFSClassTabBarPlusButton = @"AWENormalModeTabBarPlusButton";
NSString * const kDYFSClassSettings = @"AWESettingsTableViewController";
NSString * const kDYFSClassSettingItemModel = @"AWESettingItemModel";
NSString * const kDYFSClassSettingSectionModel = @"AWESettingSectionModel";
NSString * const kDYFSClassBarBackground = @"_UIBarBackground";
NSString * const kDYFSClassDetailTable = @"AWEAwemeDetailTableViewController";
NSString * const kDYFSClassDetailCell = @"AWEAwemeDetailCellViewController";
NSString * const kDYFSClassMixPanel = @"AWEMixVideoPanelDetailTableViewController";
NSString * const kDYFSClassElementStack = @"AWEElementStackView";

const NSUInteger kDYFSMaxInstallAttempts = 60;
const NSTimeInterval kDYFSInstallRetryInterval = 1.0;

NSString * const DYFSBundleID = @"com.ss.iphone.ugc.Aweme";
NSString * const DYFSTestedVersion = @"40.7.0";
NSString * const DYFSEnabledKey = @"com.dy.fullscreen.enabled";
NSString * const DYFSSettingsTitle = @"视频全屏启动";

BOOL DYFSInstalledFeed = NO;
BOOL DYFSInstalledStory = NO;
BOOL DYFSInstalledInteractionController = NO;
BOOL DYFSInstalledElementStack = NO;
BOOL DYFSInstalledPlayerContentA = NO;
BOOL DYFSInstalledPlayerContentB = NO;
BOOL DYFSInstalledPlayerContentC = NO;
BOOL DYFSInstalledTabBarLayout = NO;
BOOL DYFSInstalledTabBarHidden = NO;
BOOL DYFSInstalledTabBarDidMove = NO;
BOOL DYFSInstalledTabBarDidAddSubview = NO;
BOOL DYFSInstalledInteractionProgress = NO;
BOOL DYFSInstalledPlayerProgress = NO;
BOOL DYFSInstalledDetailTable = NO;
BOOL DYFSInstalledDetailCell = NO;
BOOL DYFSInstalledMixPanelDetail = NO;
BOOL DYFSInstalledNativeSettingsSwitch = NO;
BOOL DYFSNativeSettingsRowAdded = NO;
BOOL DYFSStartupRelayoutScheduled = NO;
BOOL DYFSSchedulePending = NO;
NSUInteger DYFSInstallAttempts = 0;
BOOL DYFSVersionMismatch = NO;
NSString *DYFSLastInstallSummary = @"尚未检测";

// Adjustment counters, surfaced by the diagnostics panel in DYFSSettings.
NSUInteger DYFSLayoutFixCount = 0;
NSUInteger DYFSInteractionContainerAdjustCount = 0;
NSUInteger DYFSPlayerContentAdjustCount = 0;
NSUInteger DYFSTabBarApplyCount = 0;
NSUInteger DYFSBottomChromeHideCount = 0;
BOOL DYFSLastHomeTabSelected = NO;
BOOL DYFSLastTabBackgroundHidden = NO;

void DYFSLog(NSString *message) {
    NSLog(@"[DY.FullScreen] %@", message);
}

BOOL DYFSIsEnabled(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:DYFSEnabledKey] == nil) return YES;
    return [defaults boolForKey:DYFSEnabledKey];
}

BOOL DYFSInstallHook(Class cls, SEL selector, IMP replacement, IMP *originalOut) {
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

static void DYFSMarkNeedsLayoutRecursively(UIView *view, NSUInteger depth) {
    if (!view || depth > 32) return;
    [view setNeedsLayout];
    for (UIView *subview in [view.subviews copy]) {
        DYFSMarkNeedsLayoutRecursively(subview, depth + 1);
    }
}

void DYFSRequestRelayout(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            DYFSMarkNeedsLayoutRecursively(window, 0);
            [window layoutIfNeeded];
        }
    });
}

NSUInteger DYFSTabBarHookCount(void) {
    return (DYFSInstalledTabBarLayout ? 1 : 0) + (DYFSInstalledTabBarHidden ? 1 : 0);
}

UIViewController *DYFSFindViewController(UIView *view) {
    UIResponder *responder = view;
    for (NSUInteger depth = 0; responder && depth < 40; depth++) {
        if ([responder isKindOfClass:UIViewController.class]) return (UIViewController *)responder;
        responder = responder.nextResponder;
    }
    return nil;
}

UIViewController *DYFSActiveTopViewController(void) {
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

UIView *DYFSFindSubviewOfClass(UIView *root, NSString *className, NSUInteger depth) {
    if (!root || depth > 14) return nil;
    if ([NSStringFromClass(root.class) isEqualToString:className]) return root;
    for (UIView *subview in root.subviews) {
        UIView *match = DYFSFindSubviewOfClass(subview, className, depth + 1);
        if (match) return match;
    }
    return nil;
}

id DYFSSafeValueForKey(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

BOOL DYFSSafeSetValueForKey(id object, id value, NSString *key) {
    if (!object || key.length == 0) return NO;
    @try {
        [object setValue:value forKey:key];
        return YES;
    } @catch (NSException *exception) {
        DYFSLog([NSString stringWithFormat:@"KVC set failed for %@: %@", key, exception.reason ?: @"unknown"]);
        return NO;
    }
}

#pragma mark - 外观原值备份（关掉开关后可还原）

static char kDYFSAppearanceBackupKey;
static NSHashTable<UIView *> *DYFSBackedUpViews = nil;

static NSHashTable<UIView *> *DYFSBackedUpViewsTable(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 弱引用：view 被释放后自动消失，不会把整棵视图树钉在内存里。
        DYFSBackedUpViews = [NSHashTable weakObjectsHashTable];
    });
    return DYFSBackedUpViews;
}

void DYFSBackupAppearance(UIView *view) {
    if (!view) return;
    // 只备份一次：后续重复清背景不应覆盖掉最初的原值。
    if (objc_getAssociatedObject(view, &kDYFSAppearanceBackupKey)) return;

    NSMutableDictionary *backup = [NSMutableDictionary dictionary];
    backup[@"hidden"] = @(view.hidden);
    backup[@"opaque"] = @(view.opaque);
    backup[@"alpha"] = @(view.alpha);
    backup[@"backgroundColor"] = view.backgroundColor ?: (id)NSNull.null;

    if (view.layer) {
        CGColorRef layerColor = view.layer.backgroundColor;
        UIColor *layerBackground = layerColor ? [UIColor colorWithCGColor:layerColor] : nil;
        backup[@"layerBackgroundColor"] = layerBackground ?: (id)NSNull.null;
    }
    if ([view isKindOfClass:UIVisualEffectView.class]) {
        UIVisualEffect *effect = ((UIVisualEffectView *)view).effect;
        if (effect) backup[@"effect"] = effect;
    }

    // 渐变层 / 形状层：DYFSClearOwnBackground 会把它们清成透明，一并备份。
    if (view.layer && view.layer.sublayers.count > 0) {
        NSMutableArray *layerSnapshots = [NSMutableArray array];
        for (CALayer *layer in view.layer.sublayers) {
            NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
            if (layer.backgroundColor) {
                snapshot[@"backgroundColor"] = [UIColor colorWithCGColor:layer.backgroundColor];
            }
            if ([layer isKindOfClass:CAGradientLayer.class] && ((CAGradientLayer *)layer).colors) {
                snapshot[@"colors"] = ((CAGradientLayer *)layer).colors;
            }
            if ([layer isKindOfClass:CAShapeLayer.class] && ((CAShapeLayer *)layer).fillColor) {
                snapshot[@"fillColor"] = [UIColor colorWithCGColor:((CAShapeLayer *)layer).fillColor];
            }
            if (snapshot.count > 0) [layerSnapshots addObject:snapshot];
        }
        if (layerSnapshots.count > 0) backup[@"sublayers"] = layerSnapshots;
    }

    objc_setAssociatedObject(view, &kDYFSAppearanceBackupKey, backup, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [DYFSBackedUpViewsTable() addObject:view];
}

void DYFSRestoreAllAppearance(void) {
    NSHashTable<UIView *> *table = DYFSBackedUpViewsTable();
    NSArray<UIView *> *views = table.allObjects;
    if (views.count == 0) return;

    for (UIView *view in views) {
        NSDictionary *backup = objc_getAssociatedObject(view, &kDYFSAppearanceBackupKey);
        if (!backup) continue;

        id value = backup[@"hidden"];
        if (value) view.hidden = [value boolValue];
        value = backup[@"opaque"];
        if (value) view.opaque = [value boolValue];
        value = backup[@"alpha"];
        if (value) view.alpha = [value floatValue];

        value = backup[@"backgroundColor"];
        if (value) view.backgroundColor = [value isKindOfClass:NSNull.class] ? nil : (UIColor *)value;

        value = backup[@"layerBackgroundColor"];
        if (value && view.layer) {
            view.layer.backgroundColor = [value isKindOfClass:NSNull.class] ? NULL : ((UIColor *)value).CGColor;
        }

        value = backup[@"effect"];
        if (value && [view isKindOfClass:UIVisualEffectView.class]) {
            ((UIVisualEffectView *)view).effect = (UIVisualEffect *)value;
        }

        NSArray *layerSnapshots = backup[@"sublayers"];
        if (layerSnapshots && view.layer && view.layer.sublayers.count == layerSnapshots.count) {
            NSUInteger index = 0;
            for (NSDictionary *snapshot in layerSnapshots) {
                CALayer *layer = view.layer.sublayers[index++];
                id color = snapshot[@"backgroundColor"];
                if (color) layer.backgroundColor = ((UIColor *)color).CGColor;
                id colors = snapshot[@"colors"];
                if (colors && [layer isKindOfClass:CAGradientLayer.class]) {
                    ((CAGradientLayer *)layer).colors = colors;
                }
                id fillColor = snapshot[@"fillColor"];
                if (fillColor && [layer isKindOfClass:CAShapeLayer.class]) {
                    ((CAShapeLayer *)layer).fillColor = ((UIColor *)fillColor).CGColor;
                }
            }
        }

        objc_setAssociatedObject(view, &kDYFSAppearanceBackupKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    [table removeAllObjects];
    DYFSLog([NSString stringWithFormat:@"restored %lu view(s) after switch off", (unsigned long)views.count]);
}

#pragma mark - 阈值失配日志

void DYFSNoteCardMiss(CGFloat width, CGFloat height, CGFloat refWidth) {
    static NSUInteger missCount = 0;
    if (missCount >= 3) return;
    missCount++;
    DYFSLog([NSString stringWithFormat:
        @"card threshold miss (w %.0f, h %.0f, refW %.0f) - 抖音改版可能导致去灰底失效",
        width, height, refWidth]);
}

#pragma mark - 视图探测与背景清除（两个透明化模块共用）

NSString *DYFSTextForView(UIView *view) {
    if (!view) return @"";
    // YYLabel / YYText 等富文本 label 并不是 UILabel 子类，先用通用属性兜底。
    if ([view respondsToSelector:@selector(attributedText)]) {
        id attr = [view performSelector:@selector(attributedText)];
        if ([attr isKindOfClass:NSAttributedString.class] && [(NSAttributedString *)attr length] > 0) {
            return [(NSAttributedString *)attr string];
        }
    }
    if ([view respondsToSelector:@selector(text)]) {
        id text = [view performSelector:@selector(text)];
        if ([text isKindOfClass:NSString.class] && [(NSString *)text length] > 0) {
            return text;
        }
    }
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        return label.attributedText.string ?: label.text ?: @"";
    }
    if ([view isKindOfClass:UITextField.class]) {
        UITextField *field = (UITextField *)view;
        return field.placeholder ?: field.text ?: @"";
    }
    if ([view isKindOfClass:UIButton.class]) {
        return [(UIButton *)view titleForState:UIControlStateNormal] ?: @"";
    }
    return view.accessibilityLabel ?: @"";
}

// 视频文案 / 描述 label：这些视图的文字必须保留，不能被「去灰底」误清或误隐藏。
BOOL DYFSIsCaptionDescriptionView(UIView *view) {
    if (!view) return NO;
    NSString *name = NSStringFromClass(view.class);
    return [name containsString:@"Description"] ||
        [name containsString:@"Caption"] ||
        [name containsString:@"DescLabel"] ||
        [name containsString:@"ContentText"];
}

// 判断以 view 为根的子树是否包含文案/描述视图（用于保护容器不被整层隐藏）。
BOOL DYFSSubtreeHasCaptionDescription(UIView *view, NSUInteger depth) {
    if (!view || depth > 8) return NO;
    if (DYFSIsCaptionDescriptionView(view)) return YES;
    for (UIView *sub in view.subviews) {
        if (DYFSSubtreeHasCaptionDescription(sub, depth + 1)) return YES;
    }
    return NO;
}

BOOL DYFSSubtreeHasText(UIView *view, NSUInteger depth) {
    if (!view || depth > 8) return NO;
    if ([DYFSTextForView(view) length] > 0) return YES;
    for (UIView *sub in view.subviews) {
        if (DYFSSubtreeHasText(sub, depth + 1)) return YES;
    }
    return NO;
}

BOOL DYFSSubtreeHasControl(UIView *view, NSUInteger depth) {
    if (!view || depth > 8) return NO;
    if ([view isKindOfClass:UIControl.class]) return YES;
    NSString *name = NSStringFromClass(view.class);
    if ([name containsString:@"Button"]) return YES;
    for (UIView *sub in view.subviews) {
        if (DYFSSubtreeHasControl(sub, depth + 1)) return YES;
    }
    return NO;
}

BOOL DYFSIsNamedChrome(UIView *view) {
    if (!view) return NO;
    NSString *name = NSStringFromClass(view.class);
    return [name containsString:@"EffectView"] ||
        [view isKindOfClass:UIVisualEffectView.class] ||
        [name containsString:@"Background"] || [name containsString:@"Backdrop"] ||
        [name containsString:@"Blur"] || [name containsString:@"BackPlate"] ||
        [name containsString:@"Material"] || [name isEqualToString:@"_UIBarBackground"];
}

BOOL DYFSIsPlainBacking(UIView *view) {
    if (!view) return NO;
    return DYFSIsNamedChrome(view) ||
        [view isMemberOfClass:UIView.class] ||
        [view isKindOfClass:UIImageView.class];
}

// DYYY 同款思路（DYYY.xm 15982）：贴底、深色纯背景的视图直接隐藏。
// 之前只清 backgroundColor，对毛玻璃和重新绘制的背景无效，
// 这里补一条按视觉特征处理的兜底路径。
BOOL DYFSIsDarkBackgroundView(UIView *view) {
    if (!view) return NO;
    UIColor *color = view.backgroundColor;
    if (!color) return NO;
    CGFloat r = 0, g = 0, b = 0, a = 0, white = 0;
    BOOL ok = [color getRed:&r green:&g blue:&b alpha:&a];
    if (!ok && [color getWhite:&white alpha:&a]) { r = g = b = white; ok = YES; }
    if (!ok || a <= 0.01) return NO;
    CGFloat luminance = 0.299 * r + 0.587 * g + 0.114 * b;
    return luminance < 0.3;
}

// 只把「纯黑不透明」底板清成透明：改颜色，绝不改 frame，因此不会造成布局位移。
void DYFSClearOpaqueBlackBackground(UIView *view) {
    if (!view) return;
    UIColor *bg = view.backgroundColor;
    if (!bg) return;
    CGFloat r = 0, g = 0, b = 0, a = 0, white = 0;
    BOOL ok = [bg getRed:&r green:&g blue:&b alpha:&a];
    if (!ok && [bg getWhite:&white alpha:&a]) { r = g = b = white; ok = YES; }
    if (!ok || a < 0.9) return;
    if ((0.299 * r + 0.587 * g + 0.114 * b) >= 0.1) return;
    DYFSBackupAppearance(view);
    view.backgroundColor = UIColor.clearColor;
    view.layer.backgroundColor = UIColor.clearColor.CGColor;
    view.opaque = NO;
}

void DYFSClearOwnBackground(UIView *view) {
    if (!view) return;
    DYFSBackupAppearance(view);
    // 毛玻璃底栏（图 2 / 图 3 的黑色半透明）靠 effect 渲染，
    // 清 backgroundColor 无效；置 nil 后 contentView 里的内容仍然保留。
    if ([view isKindOfClass:UIVisualEffectView.class]) {
        ((UIVisualEffectView *)view).effect = nil;
        return;
    }
    view.backgroundColor = UIColor.clearColor;
    view.layer.backgroundColor = UIColor.clearColor.CGColor;
    view.opaque = NO;

    // 部分卡片用渐变/形状子层而不是 backgroundColor 铺底；
    // 只清覆盖大部分区域的子层，图标等小 layer 不受影响。
    CGFloat w = CGRectGetWidth(view.bounds), h = CGRectGetHeight(view.bounds);
    for (CALayer *layer in [view.layer.sublayers copy]) {
        CGFloat lw = CGRectGetWidth(layer.frame), lh = CGRectGetHeight(layer.frame);
        if (w <= 0 || h <= 0 || lw < w * 0.6 || lh < h * 0.5) continue;
        layer.backgroundColor = UIColor.clearColor.CGColor;
        if ([layer isKindOfClass:CAGradientLayer.class]) {
            ((CAGradientLayer *)layer).colors = nil;
        } else if ([layer isKindOfClass:CAShapeLayer.class]) {
            ((CAShapeLayer *)layer).fillColor = UIColor.clearColor.CGColor;
        }
    }
}

#pragma mark - 底栏高度实测

CGFloat DYFSBottomTabBarHeight(UIView *view) {
    // 行高 hook / 各类布局回调都会调用这里，而它原本要遍历整棵 window 树
    // （深度 14、每个节点一次 NSStringFromClass），放进高频路径会直接拖慢滑动。
    // 窗口尺寸不变时底栏高度也不会变，缓存后命中率极高，开销降到 O(1)。
    static CGFloat cachedHeight = 0.0;
    static CGFloat cachedW = -1.0, cachedH = -1.0;

    UIWindow *window = view.window;
    if (!window) window = UIApplication.sharedApplication.windows.firstObject;
    CGFloat w = window ? CGRectGetWidth(window.bounds) : 0.0;
    CGFloat h = window ? CGRectGetHeight(window.bounds) : 0.0;
    if (cachedHeight > 0.0 && fabs(cachedW - w) < 1.0 && fabs(cachedH - h) < 1.0) {
        return cachedHeight;
    }

    CGFloat result = 83.0;
    if (window) {
        UIView *tabBar = DYFSFindSubviewOfClass(window, @"AWENormalModeTabBar", 0);
        CGFloat measured = CGRectGetHeight(tabBar.bounds);
        if (tabBar && isfinite(measured) && measured >= 30.0 && measured < h) {
            result = measured;
        } else {
            result = 49.0 + MAX(0.0, window.safeAreaInsets.bottom);
        }
    }
    cachedHeight = result;
    cachedW = w;
    cachedH = h;
    return result;
}

