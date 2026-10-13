//
//  DYFSComment.m
//  DY.FullScreen
//
//  评论区 / 输入框透明化。这一整套是 0.3.15 独有的，
//  0.4.x 重构时被整段弄丢了，这里重新保留。
//

#import "DYFSComment.h"
#import "DYFSCommon.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>

static IMP DYFSOriginalCommentPanelLayout = NULL;
static IMP DYFSOriginalCommentInputContainerLayout = NULL;
static IMP DYFSOriginalCommentInputBackgroundLayout = NULL;
static IMP DYFSOriginalCommentInputControllerLayout = NULL;
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
    DYFSBackupAppearance(view);
    if (!view) return;
    view.backgroundColor = UIColor.clearColor;
    view.layer.backgroundColor = UIColor.clearColor.CGColor;
    view.opaque = NO;

    // Some cards use a gradient or shape sublayer instead of UIView.backgroundColor.
    // Clear only sublayers that cover most of this view; keep glyph/icon layers intact.
    CGFloat boundsWidth = CGRectGetWidth(view.bounds);
    CGFloat boundsHeight = CGRectGetHeight(view.bounds);
    for (CALayer *layer in [view.layer.sublayers copy]) {
        CGFloat width = CGRectGetWidth(layer.frame);
        CGFloat height = CGRectGetHeight(layer.frame);
        BOOL fillsView = boundsWidth > 0.0 && boundsHeight > 0.0 &&
            width >= boundsWidth * 0.82 && height >= boundsHeight * 0.68;
        if (!fillsView) continue;

        layer.backgroundColor = UIColor.clearColor.CGColor;
        if ([layer isKindOfClass:CAGradientLayer.class]) {
            ((CAGradientLayer *)layer).colors = nil;
        } else if ([layer isKindOfClass:CAShapeLayer.class]) {
            ((CAShapeLayer *)layer).fillColor = UIColor.clearColor.CGColor;
        }
    }
    // Text attributes, alpha, icons, interaction state, frame and transforms remain untouched.
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
            DYFSBackupAppearance(subview);
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

void DYFSApplyVideoDetailBottomTransparencyInView(UIView *root) {
    if (!root) return;
    static BOOL lastEnabled = YES;
    if (!DYFSIsEnabled()) {
        if (lastEnabled) {
            DYFSRestoreAllAppearance();
            lastEnabled = NO;
        }
        return;
    }
    lastEnabled = YES;
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

void DYFSCommentPanelLayout(id self, SEL cmd) {
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

void DYFSCommentInputContainerLayout(id self, SEL cmd) {
    if (DYFSOriginalCommentInputContainerLayout) {
        ((void (*)(id, SEL))DYFSOriginalCommentInputContainerLayout)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;
    UIView *view = (UIView *)self;
    DYFSClearCommentDockBackground(view, 0);
    DYFSClearOverlappingBackgroundSiblings(view, view.superview ?: view, 180.0);
    DYFSCommentBarTransparencyApplyCount++;
}

void DYFSCommentInputBackgroundLayout(id self, SEL cmd) {
    if (DYFSOriginalCommentInputBackgroundLayout) {
        ((void (*)(id, SEL))DYFSOriginalCommentInputBackgroundLayout)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;
    UIView *view = (UIView *)self;
    DYFSClearCommentDockBackground(view, 0);
    DYFSClearOverlappingBackgroundSiblings(view, view.superview ?: view, 180.0);
    DYFSCommentBarTransparencyApplyCount++;
}

void DYFSCommentInputControllerLayout(id self, SEL cmd) {
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

void DYFSCommentInstallHooks(void) {
    Class cls = NSClassFromString(kDYFSClassCommentPanel);
    if (cls && !DYFSInstalledCommentPanel) {
        DYFSInstalledCommentPanel = DYFSInstallHook(cls, @selector(viewDidLayoutSubviews),
                    (IMP)DYFSCommentPanelLayout, &DYFSOriginalCommentPanelLayout);
    }

    cls = NSClassFromString(kDYFSClassCommentInputContainer);
    if (cls && !DYFSInstalledCommentInputContainer) {
        DYFSInstalledCommentInputContainer = DYFSInstallHook(cls, @selector(layoutSubviews),
                    (IMP)DYFSCommentInputContainerLayout, &DYFSOriginalCommentInputContainerLayout);
    }

    cls = NSClassFromString(kDYFSClassCommentInputBackground);
    if (cls && !DYFSInstalledCommentInputBackground) {
        DYFSInstalledCommentInputBackground = DYFSInstallHook(cls, @selector(layoutSubviews),
                    (IMP)DYFSCommentInputBackgroundLayout, &DYFSOriginalCommentInputBackgroundLayout);
    }

    cls = NSClassFromString(kDYFSClassCommentInputController);
    if (cls && !DYFSInstalledCommentInputController) {
        DYFSInstalledCommentInputController = DYFSInstallHook(cls, @selector(viewDidLayoutSubviews),
                    (IMP)DYFSCommentInputControllerLayout, &DYFSOriginalCommentInputControllerLayout);
    }
}
