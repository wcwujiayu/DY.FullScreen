//
//  DYFSLayout.m
//  DY.FullScreen
//
//  所有高度补偿统一收敛到全局 -setFrame: 兜底（pre 式）：
//  在抖音把 frame 写进去之前就改好，视图第一次布局即为目标尺寸，
//  不再有"先按旧高度渲染一帧再被拉高"的启动跳动。
//  layoutSubviews hook 只保留透明化触发职责。
//

#import "DYFSLayout.h"
#import "DYFSCommon.h"
#import "DYFSContext.h"
#import "DYFSTransparency.h"
#import <objc/message.h>
#import <math.h>

static IMP DYFSOriginalFeedLayout = NULL;
static IMP DYFSOriginalStoryLayout = NULL;
static IMP DYFSOriginalInteractionControllerLayout = NULL;
static IMP DYFSOriginalSetFrame = NULL;

CGFloat DYFSBottomTabBarHeight(UIView *view) {
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

#pragma mark - 透明化触发

// 这些 hook 不再参与尺寸修正，只为透明化提供布局时机。

void DYFSFeedTableLayout(id self, SEL cmd) {
    if (DYFSOriginalFeedLayout) ((void (*)(id, SEL))DYFSOriginalFeedLayout)(self, cmd);
    if (!DYFSIsEnabled()) return;
    DYFSTransparencyApplyInView((UIView *)self);
}

void DYFSStoryContainerLayout(id self, SEL cmd) {
    if (DYFSOriginalStoryLayout) {
        ((void (*)(id, SEL))DYFSOriginalStoryLayout)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;
    DYFSTransparencyApplyInView((UIView *)self);
}

void DYFSInteractionControllerLayout(id self, SEL cmd) {
    if (DYFSOriginalInteractionControllerLayout) {
        ((void (*)(id, SEL))DYFSOriginalInteractionControllerLayout)(self, cmd);
    }
    if (!DYFSIsEnabled()) return;
    UIViewController *controller = (UIViewController *)self;
    DYFSTransparencyApplyInView(controller.view);
    if (controller.view.superview) DYFSTransparencyApplyInView(controller.view.superview);
}

#pragma mark - 全局 -setFrame: 兜底（唯一的尺寸修正入口）

static BOOL DYFSIsPlayerViewController(UIViewController *vc) {
    if (!vc) return NO;
    static Class playClassA, playClassB, playClassC;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        playClassA = NSClassFromString(kDYFSClassPlayVideoA);
        playClassB = NSClassFromString(kDYFSClassPlayVideoB);
        playClassC = NSClassFromString(kDYFSClassPlayVideoC);
    });
    return (playClassA && [vc isKindOfClass:playClassA]) ||
           (playClassB && [vc isKindOfClass:playClassB]) ||
           (playClassC && [vc isKindOfClass:playClassC]);
}

static void DYFSUIViewSetFrame(id self, SEL cmd, CGRect frame) {
    if (!DYFSOriginalSetFrame) return;

    if (!DYFSIsEnabled() || ![self isKindOfClass:UIView.class]) {
        ((void (*)(id, SEL, CGRect))DYFSOriginalSetFrame)(self, cmd, frame);
        return;
    }

    UIView *view = (UIView *)self;
    UIView *superview = view.superview;
    if (!superview) {
        ((void (*)(id, SEL, CGRect))DYFSOriginalSetFrame)(self, cmd, frame);
        return;
    }

    CGFloat superH = CGRectGetHeight(superview.frame);
    CGFloat height = CGRectGetHeight(frame);
    if (superH <= 0 || height <= 0) {
        ((void (*)(id, SEL, CGRect))DYFSOriginalSetFrame)(self, cmd, frame);
        return;
    }

    NSString *className = NSStringFromClass(view.class);

    // 1) 首页视频列表：撑满父容器。
    //    作者主页有自己的分页容器，强改会让上下两条视频叠在一起，必须排除。
    if ([className isEqualToString:kDYFSClassFeedTableView]) {
        if (height < superH - 0.5 && !DYFSInProfileContext(view)) {
            frame.origin.y = 0.0;
            frame.size.height = superH;
        }
        ((void (*)(id, SEL, CGRect))DYFSOriginalSetFrame)(self, cmd, frame);
        return;
    }

    // 2) 全宽视图：互动层与播放器内容视图。
    //    先用屏宽粗筛，命中才回溯响应链，控制开销。
    CGFloat screenWidth = UIScreen.mainScreen.bounds.size.width;
    if (CGRectGetWidth(frame) >= screenWidth - 1.0) {
        UIViewController *vc = DYFSFindViewController(view);
        NSString *vcName = vc ? NSStringFromClass(vc.class) : @"";
        CGFloat tabBarHeight = DYFSBottomTabBarHeight(view);

        // 2a) 互动层：高度固定为「父容器 - 底栏」，
        //     个人主页 / 直播间 / 推流预览保持抖音原生高度。
        if ([vcName containsString:kDYFSClassPlayInteraction]) {
            CGFloat targetH = superH - tabBarHeight;
            if (targetH > 0 && fabs(height - targetH) > 0.5 &&
                !DYFSInProfileContext(view) &&
                !DYFSIsActualLiveRoomContext(view) &&
                !DYFSIsLivePreStreamContext(view) &&
                !DYFSIsLivePreStreamPlayer(vc) &&
                DYFSIsFeedCellInteractionController(vc)) {
                frame.size.height = targetH;
            }
            ((void (*)(id, SEL, CGRect))DYFSOriginalSetFrame)(self, cmd, frame);
            return;
        }

        // 2b) 播放器内容视图（含信息流直播卡片的视频）：
        //     差一个底栏 → 补满；差两个底栏 → 补到差一个底栏。
        //     只改高度，origin 完全不动。
        if (DYFSIsPlayerViewController(vc) &&
            frame.origin.x == 0 && frame.origin.y == 0 && height < superH &&
            !DYFSIsActualLiveRoomContext(view)) {
            CGFloat diff = superH - height;
            CGFloat tolerance = MAX(1.0, tabBarHeight * 0.03);
            if (fabs(diff - tabBarHeight) <= tolerance) {
                frame.size.height = superH;
            } else if (tabBarHeight > 0 && fabs(diff - tabBarHeight * 2.0) <= tolerance) {
                frame.size.height = superH - tabBarHeight;
            }
            ((void (*)(id, SEL, CGRect))DYFSOriginalSetFrame)(self, cmd, frame);
            return;
        }
    }

    ((void (*)(id, SEL, CGRect))DYFSOriginalSetFrame)(self, cmd, frame);
}

#pragma mark - 安装

void DYFSLayoutInstallHooks(void) {
    // feed / story / interaction 仅作为透明化的布局触发点。
    Class cls = NSClassFromString(kDYFSClassFeedTableView);
    if (!DYFSInstalledFeed && cls) {
        DYFSInstalledFeed = DYFSInstallHook(cls, @selector(layoutSubviews),
                                            (IMP)DYFSFeedTableLayout, &DYFSOriginalFeedLayout);
    }

    cls = NSClassFromString(kDYFSClassStoryContainer);
    if (!DYFSInstalledStory && cls) {
        DYFSInstalledStory = DYFSInstallHook(cls, @selector(layoutSubviews),
                    (IMP)DYFSStoryContainerLayout, &DYFSOriginalStoryLayout);
    }

    cls = NSClassFromString(kDYFSClassPlayInteraction);
    if (!DYFSInstalledInteractionController && cls) {
        DYFSInstalledInteractionController = DYFSInstallHook(cls, @selector(viewDidLayoutSubviews),
                    (IMP)DYFSInteractionControllerLayout, &DYFSOriginalInteractionControllerLayout);
    }

    // 全局兜底：装在 UIView 上，覆盖直播卡片等一切内容。
    // pre 式修正：抖音写入 frame 之前就把高度改对，因此不会出现启动跳动。
    if (!DYFSInstalledSetFrameHook) {
        DYFSInstalledSetFrameHook = DYFSInstallHook(UIView.class, @selector(setFrame:),
                                                    (IMP)DYFSUIViewSetFrame, &DYFSOriginalSetFrame);
    }
}
