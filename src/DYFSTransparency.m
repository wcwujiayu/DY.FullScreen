//
//  DYFSTransparency.m
//  DY.FullScreen
//
//  定位策略与旧版（0.3.x）的区别：
//  1. 底部 dock 不再依赖 CommentInputContainerView 等私有类名（个人主页里类名
//     经常不同），改为几何特征匹配：宽度 >= 70% 父宽、高度 36~170、贴近底部。
//  2. 背景判定放宽：覆盖率阈值 60% x 50%（旧版 82% x 68%），并接受 UIImageView
//     / 渐变层 / 任意命名，避免误判漏网。
//  3. 只动背景，文字、图标、交互一律保留。
//

#import "DYFSTransparency.h"
#import "DYFSCommon.h"
#import "DYFSContext.h"
#import <QuartzCore/QuartzCore.h>

static const NSUInteger kDYFSTransparencyMaxDepth = 10;

#pragma mark - 视图探测

static NSString *DYFSTextForView(UIView *view) {
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
static BOOL DYFSIsCaptionDescriptionView(UIView *view) {
    if (!view) return NO;
    NSString *name = NSStringFromClass(view.class);
    return [name containsString:@"Description"] ||
        [name containsString:@"Caption"] ||
        [name containsString:@"DescLabel"] ||
        [name containsString:@"ContentText"];
}

// 判断以 view 为根的子树是否包含文案/描述视图（用于保护容器不被整层隐藏）。
static BOOL DYFSSubtreeHasCaptionDescription(UIView *view, NSUInteger depth) {
    if (!view || depth > 8) return NO;
    if (DYFSIsCaptionDescriptionView(view)) return YES;
    for (UIView *sub in view.subviews) {
        if (DYFSSubtreeHasCaptionDescription(sub, depth + 1)) return YES;
    }
    return NO;
}

static BOOL DYFSSubtreeHasText(UIView *view, NSUInteger depth) {
    if (!view || depth > 8) return NO;
    if ([DYFSTextForView(view) length] > 0) return YES;
    for (UIView *sub in view.subviews) {
        if (DYFSSubtreeHasText(sub, depth + 1)) return YES;
    }
    return NO;
}

static BOOL DYFSSubtreeHasControl(UIView *view, NSUInteger depth) {
    if (!view || depth > 8) return NO;
    if ([view isKindOfClass:UIControl.class]) return YES;
    NSString *name = NSStringFromClass(view.class);
    if ([name containsString:@"Button"]) return YES;
    for (UIView *sub in view.subviews) {
        if (DYFSSubtreeHasControl(sub, depth + 1)) return YES;
    }
    return NO;
}

#pragma mark - 背景清除

static BOOL DYFSIsNamedChrome(UIView *view) {
    NSString *name = NSStringFromClass(view.class);
    return [name containsString:@"EffectView"] ||
        [view isKindOfClass:UIVisualEffectView.class] ||
        [name containsString:@"Background"] || [name containsString:@"Backdrop"] ||
        [name containsString:@"Blur"] || [name containsString:@"BackPlate"] ||
        [name containsString:@"Material"] || [name isEqualToString:@"_UIBarBackground"];
}

static BOOL DYFSIsPlainBacking(UIView *view) {
    return DYFSIsNamedChrome(view) ||
        [view isMemberOfClass:UIView.class] ||
        [view isKindOfClass:UIImageView.class];
}

static void DYFSClearOwnBackground(UIView *view) {
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

// 递归清除目标子树的背景。文字颜色、alpha、图标、交互都不改。
static void DYFSClearChromeTree(UIView *view, NSUInteger depth) {
    if (!view || depth > kDYFSTransparencyMaxDepth) return;
    // 保护视频文案/描述 label，避免文字被误清。
    if (DYFSIsCaptionDescriptionView(view)) return;
    DYFSClearOwnBackground(view);
    for (UIView *sub in [view.subviews copy]) {
        DYFSClearChromeTree(sub, depth + 1);
    }
}

// 隐藏与目标区域重叠、且不含文字/控件的独立背景兄弟层
static void DYFSHideOverlappingChrome(UIView *anchor, UIView *root) {
    if (!anchor || !root || anchor == root) return;
    CGRect anchorRect = [anchor convertRect:anchor.bounds toView:root];
    CGFloat aw = CGRectGetWidth(anchorRect), ah = CGRectGetHeight(anchorRect);
    if (aw < 24 || ah < 14) return;

    UIView *cursor = anchor;
    for (NSUInteger depth = 0; cursor && cursor != root && depth < 8; depth++, cursor = cursor.superview) {
        UIView *parent = cursor.superview;
        if (!parent) break;
        for (UIView *sibling in [parent.subviews copy]) {
            if (sibling == cursor || sibling.hidden || DYFSSubtreeHasControl(sibling, 0)) continue;
            if (!DYFSIsPlainBacking(sibling)) continue;
            if (DYFSSubtreeHasText(sibling, 0)) continue;
            CGRect rect = [sibling convertRect:sibling.bounds toView:root];
            CGFloat sh = CGRectGetHeight(rect);
            if (sh < ah * 0.5 || sh > MAX(ah * 2.5, ah + 60.0)) continue;
            CGRect inter = CGRectIntersection(rect, anchorRect);
            CGFloat ratio = CGRectGetWidth(inter) * CGRectGetHeight(inter) / MAX(1.0, aw * ah);
            if (ratio < 0.6) continue;
            sibling.hidden = YES;
        }
    }
}


// DYYY 同款思路（DYYY.xm 15982）：贴底、深色纯背景的视图直接隐藏。
// 之前只清 backgroundColor，对毛玻璃和重新绘制的背景无效，
// 这里补一条按视觉特征处理的兜底路径。
static BOOL DYFSIsDarkBackgroundView(UIView *view) {
    UIColor *color = view.backgroundColor;
    if (!color) return NO;
    CGFloat r = 0, g = 0, b = 0, a = 0, white = 0;
    BOOL ok = [color getRed:&r green:&g blue:&b alpha:&a];
    if (!ok && [color getWhite:&white alpha:&a]) { r = g = b = white; ok = YES; }
    if (!ok || a <= 0.01) return NO;
    CGFloat luminance = 0.299 * r + 0.587 * g + 0.114 * b;
    return luminance < 0.3;
}

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

#pragma mark - 目标定位

// 视频底部的信息 / 评论 dock：宽、矮、贴底（对应「我-作品」「我-喜欢」的底栏）
// reference 传窗口：root 常常是整张 feed 列表（高度可达数千），
// 用它自己的坐标系算「距离底部」会让所有候选都被过滤掉，这是之前完全没效果的原因。
static UIView *DYFSFindBottomDock(UIView *root, UIView *reference) {
    if (!root) return nil;
    UIView *ref = reference ?: root;
    CGFloat refW = CGRectGetWidth(ref.bounds), refH = CGRectGetHeight(ref.bounds);
    if (refW < 100.0 || refH < 200.0) return nil;

    UIView *best = nil;
    CGFloat bestScore = -CGFLOAT_MAX;
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:root];
    NSUInteger visited = 0;
    while (pending.count > 0 && visited < 400) {
        visited++;
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        [pending addObjectsFromArray:view.subviews];
        if (view.hidden || view.alpha <= 0.01) continue;

        CGRect rect = [view convertRect:view.bounds toView:ref];
        CGFloat w = CGRectGetWidth(rect), h = CGRectGetHeight(rect);
        CGFloat bottomGap = refH - CGRectGetMaxY(rect);
        if (w < refW * 0.7 || h < 36.0 || h > 170.0 || bottomGap < -6.0 || bottomGap > 200.0) continue;

        CGFloat score = w / MAX(1.0, refW) * 3.0 - fabs(h - 60.0) / 100.0 - fabs(bottomGap) / 200.0;
        if (score > bestScore) { bestScore = score; best = view; }
    }
    return best;
}

static BOOL DYFSIsSearchPillText(NSString *text) {
    if (text.length == 0) return NO;
    return [text containsString:@"相关搜索"] ||
        [text containsString:@"合集"] ||
        [text containsString:@"视频合集"] ||
        [text containsString:@"大家都在搜"];
}

// 「相关搜索」/「合集」胶囊卡片：先按文字定位 label，再向上找尺寸合理的卡片容器
static void DYFSApplyCardTransparency(UIView *root, UIView *reference) {
    if (!root) return;
    UIView *ref = reference ?: root;
    CGFloat refW = CGRectGetWidth(ref.bounds), refH = CGRectGetHeight(ref.bounds);
    if (refW < 100.0 || refH < 160.0) return;

    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:root];
    NSUInteger visited = 0;
    while (pending.count > 0 && visited < 600) {
        visited++;
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        [pending addObjectsFromArray:view.subviews];
        if (view.hidden || view.alpha <= 0.01) continue;
        if (![view isKindOfClass:UILabel.class]) continue;
        if (!DYFSIsSearchPillText(DYFSTextForView(view))) continue;

        for (UIView *candidate = view.superview; candidate && candidate != root; candidate = candidate.superview) {
            CGRect rect = [candidate convertRect:candidate.bounds toView:ref];
            CGFloat w = CGRectGetWidth(rect), h = CGRectGetHeight(rect);
            CGFloat minY = CGRectGetMinY(rect);
            if (w < MAX(80.0, refW * 0.25) || w > refW * 1.01) {
                DYFSNoteCardMiss(w, h, refW);
                continue;
            }
            if (h < 22.0 || h > 220.0 || minY < 0) {
                DYFSNoteCardMiss(w, h, refW);
                continue;
            }

            DYFSClearChromeTree(candidate, 0);
            DYFSHideOverlappingChrome(candidate, ref);
            break;
        }
    }
}

#pragma mark - 入口

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

static void DYFSTransparencyApplyNow(UIView *root) {
    if (!root || !DYFSIsEnabled()) return;
    // 普通聊天会话窗口整个跳过：底部输入栏的毛玻璃会被兜底逻辑当成
    // 「贴底深色条」隐藏掉，表现为底栏透明一块。
    if (DYFSIsChatConversationContext(root)) return;

    // 「贴底」必须以窗口为参照：root 往往是整张 feed 列表，高度可达数千。
    UIWindow *window = root.window;
    if (!window) window = UIApplication.sharedApplication.windows.firstObject;
    UIView *reference = window ?: root;

    // 已验证写法：直接命中全局底栏与互动右栏，不依赖几何搜索。
    DYFSClearTabBarBackgrounds(reference);
    DYFSApplyInteractionTransparency(root);

    UIView *dock = DYFSFindBottomDock(root, reference);
    if (dock) {
        DYFSClearChromeTree(dock, 0);
        DYFSHideOverlappingChrome(dock, reference);
    }
    DYFSApplyCardTransparency(root, reference);
    // 个人主页 / 详情页自己的贴底黑条（与首页底栏不是同一个类）。
    // 只在个人主页与详情页跑：首页信息流里同样贴底的容器（文章类视频的
    // 「阅读文章」条等）不该被动到。
    if (DYFSInProfileContext(root) || DYFSIsDetailVideoContext(root) || DYFSIsIMDetailContext(root)) {
        DYFSClearBottomBarChrome(reference);
    }
    // 兜底：单独存在的深色背景条（不成组的 pill 也能覆盖到）
    DYFSHideDarkBottomChrome(root, reference);
}

void DYFSTransparencyApplyInView(UIView *root) {
    if (!root) return;

    // 关掉开关：把之前改过的视图一次性还原，避免必须重启抖音才恢复。
    static BOOL lastEnabled = YES;
    if (!DYFSIsEnabled()) {
        if (lastEnabled) {
            DYFSRestoreAllAppearance();
            lastEnabled = NO;
        }
        return;
    }
    lastEnabled = YES;

    // 节流：共有 9 个触发点会调用这里，同一帧内合并成一次，
    // 否则一次滑动会跑很多遍全树遍历。
    //
    // 注意这里必须同步执行。之前用 dispatch_async 延到下一帧，会让
    // "尺寸补高"和"背景透明"分两帧完成，肉眼就能看到
    // 先黑底 → 再拉伸 → 最后才透明 的跳变。
    static BOOL running = NO;
    static NSMutableArray<UIView *> *pending = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ pending = [NSMutableArray array]; });

    if (![pending containsObject:root]) [pending addObject:root];
    // 正在处理时直接返回：本次请求已入队，由当前这轮一起处理，
    // 同时天然阻断递归重入。
    if (running) return;

    running = YES;
    while (pending.count > 0) {
        UIView *first = pending.firstObject;
        [pending removeObjectAtIndex:0];
        DYFSTransparencyApplyNow(first);
    }
    running = NO;
}
