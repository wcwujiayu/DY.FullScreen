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

#pragma mark - 目标定位

// 视频底部的信息 / 评论 dock：宽、矮、贴底（对应「我-作品」「我-喜欢」的底栏）
static UIView *DYFSFindBottomDock(UIView *root) {
    CGFloat rootW = CGRectGetWidth(root.bounds), rootH = CGRectGetHeight(root.bounds);
    if (rootW < 100.0 || rootH < 200.0) return nil;

    UIView *best = nil;
    CGFloat bestScore = -CGFLOAT_MAX;
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:root];
    while (pending.count > 0) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        [pending addObjectsFromArray:view.subviews];
        if (view.hidden || view.alpha <= 0.01) continue;

        CGRect rect = [view convertRect:view.bounds toView:root];
        CGFloat w = CGRectGetWidth(rect), h = CGRectGetHeight(rect);
        CGFloat bottomGap = rootH - CGRectGetMaxY(rect);
        if (w < rootW * 0.7 || h < 36.0 || h > 170.0 || bottomGap < -6.0 || bottomGap > 200.0) continue;

        CGFloat score = w / MAX(1.0, rootW) * 3.0 - fabs(h - 60.0) / 100.0 - fabs(bottomGap) / 200.0;
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
static void DYFSApplyCardTransparency(UIView *root) {
    CGFloat rootW = CGRectGetWidth(root.bounds), rootH = CGRectGetHeight(root.bounds);
    if (rootW < 100.0 || rootH < 160.0) return;

    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:root];
    while (pending.count > 0) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        [pending addObjectsFromArray:view.subviews];
        if (view.hidden || view.alpha <= 0.01) continue;
        if (![view isKindOfClass:UILabel.class]) continue;
        if (!DYFSIsSearchPillText(DYFSTextForView(view))) continue;

        for (UIView *candidate = view.superview; candidate && candidate != root; candidate = candidate.superview) {
            CGRect rect = [candidate convertRect:candidate.bounds toView:root];
            CGFloat w = CGRectGetWidth(rect), h = CGRectGetHeight(rect);
            CGFloat minY = CGRectGetMinY(rect);
            if (w < MAX(80.0, rootW * 0.25) || w > rootW * 1.01) continue;
            if (h < 22.0 || h > 220.0 || minY < rootH * 0.1) continue;

            DYFSClearChromeTree(candidate, 0);
            DYFSHideOverlappingChrome(candidate, root);
            break;
        }
    }
}

#pragma mark - 入口

void DYFSTransparencyApplyInView(UIView *root) {
    if (!root || !DYFSIsEnabled()) return;
    // 直播间与开播预览保持抖音原生外观，不做透明化。
    if (DYFSIsActualLiveRoomContext(root) || DYFSIsLivePreStreamContext(root)) return;

    UIView *dock = DYFSFindBottomDock(root);
    if (dock) {
        DYFSClearChromeTree(dock, 0);
        DYFSHideOverlappingChrome(dock, root);
    }
    DYFSApplyCardTransparency(root);
}
