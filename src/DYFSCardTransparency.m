//
//  DYFSCardTransparency.m
//  DY.FullScreen
//
//  「相关搜索」/「合集」胶囊卡片的去灰底，以及视频底部信息 dock 的背景清理。
//  原则：只动背景，文字、图标、点击区域一律不动。
//

#import "DYFSCardTransparency.h"
#import "DYFSCommon.h"

static const NSUInteger kDYFSCardMaxDepth = 10;

// 递归清除目标子树的背景。文字颜色、alpha、图标、交互都不改。
static void DYFSClearChromeTree(UIView *view, NSUInteger depth) {
    if (!view || depth > kDYFSCardMaxDepth) return;
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

void DYFSCardTransparencyApply(UIView *root, UIView *reference) {
    if (!root) return;
    UIView *ref = reference ?: root;
    UIView *dock = DYFSFindBottomDock(root, ref);
    if (dock) {
        DYFSClearChromeTree(dock, 0);
        DYFSHideOverlappingChrome(dock, ref);
    }
    DYFSApplyCardTransparency(root, ref);
}
