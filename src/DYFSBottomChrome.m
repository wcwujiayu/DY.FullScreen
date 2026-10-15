//
//  DYFSBottomChrome.m
//  DY.FullScreen
//
//  底部栏相关的背景清理。分三块：
//   1. 全局底栏 AWENormalModeTabBar（直接按类名命中，不依赖几何搜索）
//   2. 互动右栏里的纯黑背景（DYYY 同款写法）
//   3. 各页面自带的贴底黑条（个人主页 / 详情页 / 聊天分享）
//  原则：只动背景，文字、图标、点击区域一律不动。
//

#import "DYFSBottomChrome.h"
#import "DYFSCommon.h"
#import "DYFSContext.h"

#pragma mark - 全局底栏

// 直接定位全局底栏（AWENormalModeTabBar），隐藏其背景与分割线。
// 复刻 DYYY 的已验证写法（DYYY.xm 15236）：不再依赖几何搜索，直接按类与
// skinContainerView 处理，因此能稳定命中抖音 40.7.0 的底栏结构。
static void DYFSClearTabBarBackgrounds(UIView *root) {
    if (!root) return;
    // 子类感知查找：exact 类名匹配（DYFSFindSubviewOfClass）会漏掉被继承的底栏类。
    UIView *tabBar = nil;
    Class tabBarClass = NSClassFromString(kDYFSClassTabBar);
    if (tabBarClass) {
        NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:root];
        while (pending.count > 0) {
            UIView *view = pending.lastObject;
            [pending removeLastObject];
            if ([view isKindOfClass:tabBarClass]) { tabBar = view; break; }
            [pending addObjectsFromArray:view.subviews];
        }
    }
    if (!tabBar) tabBar = DYFSFindSubviewOfClass(root, kDYFSClassTabBar, 0);
    if (!tabBar) return;

    id skin = DYFSSafeValueForKey(tabBar, @"skinContainerView");
    if ([skin isKindOfClass:UIView.class]) ((UIView *)skin).hidden = YES;

    Class generalBtn = NSClassFromString(kDYFSClassTabBarGeneralButton);
    Class plusBtn = NSClassFromString(kDYFSClassTabBarPlusButton);
    Class barBg = NSClassFromString(kDYFSClassBarBackground);
    CGFloat tabH = CGRectGetHeight(tabBar.bounds);

    for (UIView *sub in [tabBar.subviews copy]) {
        if (generalBtn && [sub isKindOfClass:generalBtn]) continue;
        if (plusBtn && [sub isKindOfClass:plusBtn]) continue;

        BOOL isBackground = (barBg && [sub isKindOfClass:barBg]) ||
            ([sub isMemberOfClass:UIView.class] && tabH > 0 &&
             fabs(CGRectGetHeight(sub.bounds) - tabH) < 1.0);
        if (isBackground) {
            DYFSBackupAppearance(sub);
            sub.hidden = YES;
            sub.backgroundColor = UIColor.clearColor;
        }
        // 细分割线
        if (CGRectGetHeight(sub.bounds) > 0 && CGRectGetHeight(sub.bounds) < 1.0 &&
            CGRectGetWidth(sub.bounds) > 300.0) {
            DYFSBackupAppearance(sub);
            sub.hidden = YES;
        }
    }
}

// 复刻 DYYY（DYYY.xm 15953）：点赞 / 评论 / 分享右栏里纯黑背景直接隐藏。
static void DYFSApplyInteractionTransparency(UIView *root) {
    if (!root) return;
    UIViewController *vc = DYFSFindViewController(root);
    Class cls = NSClassFromString(kDYFSClassPlayInteraction);
    if (!cls || ![vc isKindOfClass:cls]) return;
    for (UIView *sub in [root.subviews copy]) {
        if ([sub isKindOfClass:[UIView class]] && sub.backgroundColor &&
            CGColorEqualToColor(sub.backgroundColor.CGColor, [UIColor blackColor].CGColor)) {
            // 不要隐藏包含视频文案/描述的子视图（例如底部文案容器）。
            if (DYFSIsCaptionDescriptionView(sub) || DYFSSubtreeHasCaptionDescription(sub, 0)) continue;
            DYFSBackupAppearance(sub);
            sub.hidden = YES;
        }
    }
}

#pragma mark - 贴底黑条

// DYYY 同款思路（DYYY.xm 15982）：贴底、深色纯背景的视图直接隐藏。
// 之前只清 backgroundColor，对毛玻璃和重新绘制的背景无效，
// 这里补一条按视觉特征处理的兜底路径。
static void DYFSHideDarkBottomChrome(UIView *root, UIView *reference) {
    if (!root || !reference) return;
    CGFloat refW = CGRectGetWidth(reference.bounds), refH = CGRectGetHeight(reference.bounds);
    if (refW < 100.0 || refH < 200.0) return;
    CGFloat limitY = refH * 0.72;          // 只处理底部区域

    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:root];
    NSUInteger visited = 0;
    while (pending.count > 0 && visited < 400) {
        visited++;
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        [pending addObjectsFromArray:view.subviews];
        if (view.hidden || view.alpha <= 0.01) continue;
        // 有文字、有控件、含视频文案/描述的容器一律保留，只清背景
        if (DYFSSubtreeHasText(view, 0) || DYFSSubtreeHasControl(view, 0) ||
            DYFSSubtreeHasCaptionDescription(view, 0)) continue;

        CGRect rect = [view convertRect:view.bounds toView:reference];
        if (CGRectGetMinY(rect) < limitY) continue;
        CGFloat w = CGRectGetWidth(rect), h = CGRectGetHeight(rect);
        if (w < refW * 0.5 || h < 20.0 || h > refH * 0.3) continue;

        if (DYFSIsNamedChrome(view) || DYFSIsDarkBackgroundView(view) ||
            [view isKindOfClass:UIVisualEffectView.class]) {
            DYFSBackupAppearance(view);
            view.hidden = YES;
        }
    }
}

// 含文字/控件的贴底条（评论条、操作栏）：只把里面的深色背景层层清掉，
// 白底与彩色元素保留，文字与按钮照旧可点。
static void DYFSClearDarkChromeTree(UIView *view, NSUInteger depth) {
    if (!view || depth > 8) return;
    for (UIView *sub in [view.subviews copy]) {
        if (sub.hidden || sub.alpha <= 0.01) continue;
        // 视频文案/描述容器：只保留，不进入背景清理。
        if (DYFSIsCaptionDescriptionView(sub) || DYFSSubtreeHasCaptionDescription(sub, 0)) continue;
        // 含文字/控件的容器也要清掉自身的渐变/图片子层（例如评论输入胶囊、
        // 聊天分享底栏胶囊的深色底），否则只递归子视图会漏掉容器自己画的那一层黑底。
        // 控件与图标图不在此列，避免误清按钮/表情图等可见内容。
        if (![sub isKindOfClass:UIControl.class] && ![sub isKindOfClass:UIImageView.class]) {
            DYFSClearOwnBackground(sub);
        }
        BOOL isPlain = !DYFSSubtreeHasText(sub, 0) && !DYFSSubtreeHasControl(sub, 0);
        BOOL isEffect = [sub isKindOfClass:UIVisualEffectView.class];
        if (isPlain && (DYFSIsDarkBackgroundView(sub) || DYFSIsNamedChrome(sub) || isEffect)) {
            if (isEffect || DYFSIsNamedChrome(sub)) { DYFSBackupAppearance(sub); sub.hidden = YES; }
            DYFSBottomChromeHideCount++;
            continue;
        }
        DYFSClearDarkChromeTree(sub, depth + 1);
    }
}

// 「我-作品 / 我-喜欢 / 收藏」以及视频详情页底部的那条黑条并不是全局底栏
// (AWENormalModeTabBar)，而是各页面自带的贴底容器，因此按几何特征统一处理：
// 贴底、铺满宽、高度 20~170。
//   · 不含文字与控件的（纯背景条）→ 直接隐藏并清底；
//   · 含文字或控件的（评论条、操作栏）→ 只清背景，按钮与文字全部保留可点。
static void DYFSClearBottomBarChrome(UIView *reference) {
    if (!reference) return;
    CGFloat refW = CGRectGetWidth(reference.bounds), refH = CGRectGetHeight(reference.bounds);
    if (refW < 100.0 || refH < 200.0) return;

    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:reference];
    NSUInteger visited = 0;
    while (pending.count > 0 && visited < 600) {
        visited++;
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        [pending addObjectsFromArray:view.subviews];
        if (view == reference || view.hidden || view.alpha <= 0.01) continue;
        // 保护视频文案/描述容器，不能被当成贴底黑条处理。
        if (DYFSIsCaptionDescriptionView(view) || DYFSSubtreeHasCaptionDescription(view, 0)) continue;

        CGRect rect = [view convertRect:view.bounds toView:reference];
        CGFloat w = CGRectGetWidth(rect), h = CGRectGetHeight(rect);
        if (w < refW * 0.9 || h < 20.0 || h > 170.0) continue;
        if (CGRectGetMinY(rect) < refH - 220.0) continue;   // 只看底部区域
        // 接近底部即可：聊天分享 / 作品页的底栏胶囊不一定完全贴底（下方还有输入条）。
        if (CGRectGetMaxY(rect) < refH - 130.0) continue;

        // 聊天输入栏与 IM 详情同处一个 window，按视图自身上下文排除（否则返回聊天底栏已透明）
        if (DYFSIsChatConversationContext(view)) continue;

        if (DYFSSubtreeHasText(view, 0) || DYFSSubtreeHasControl(view, 0)) {
            DYFSClearOwnBackground(view);
            DYFSClearDarkChromeTree(view, 0);
            continue;
        }
        DYFSClearOwnBackground(view);
        DYFSBackupAppearance(view);
        view.hidden = YES;
        DYFSBottomChromeHideCount++;
    }
}

#pragma mark - 入口

void DYFSBottomChromeApply(UIView *root, UIView *reference) {
    if (!root) return;
    UIView *ref = reference ?: root;

    // 已验证写法：直接命中全局底栏与互动右栏，不依赖几何搜索。
    DYFSClearTabBarBackgrounds(ref);
    DYFSApplyInteractionTransparency(root);

    // 个人主页 / 详情页自己的贴底黑条（与首页底栏不是同一个类）。
    // 只在个人主页与详情页跑：首页信息流里同样贴底的容器（文章类视频的
    // 「阅读文章」条等）不该被动到。
    if (DYFSInProfileContext(root) || DYFSIsDetailVideoContext(root) || DYFSIsIMDetailContext(root)) {
        DYFSClearBottomBarChrome(ref);
    }
    // 兜底：单独存在的深色背景条（不成组的 pill 也能覆盖到）
    DYFSHideDarkBottomChrome(root, ref);
}
