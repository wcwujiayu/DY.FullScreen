//
//  DYFSTransparency.m
//  DY.FullScreen
//
//  透明化调度入口。0.5.7 起只负责：
//   · 开关状态与「关掉开关后还原」
//   · 统一节流（把同一帧内的多次请求合并成一次）
//   · 把工作分派给两个专职模块
//       - DYFSCardTransparency：相关搜索 / 合集胶囊卡片
//       - DYFSBottomChrome：全局底栏 / 贴底黑条 / 互动右栏
//
//  ⚠️ 这里的节流循环必须有处理上限。清理背景和隐藏视图都会触发布局回调，
//  回调里又会往同一个队列入队；没有上限时队列会越处理越长，把主线程堵死
//  （实测为 0x8BADF00D 看门狗杀进程，主线程栈停在 DYFSTransparencyApplyInView）。
//

#import "DYFSTransparency.h"
#import "DYFSCommon.h"
#import "DYFSContext.h"
#import "DYFSCardTransparency.h"
#import "DYFSBottomChrome.h"

// 单轮最多处理多少个 root。正常一帧内只会有 1~3 个触发点，
// 这个上限只在「改布局 → 触发布局 → 再入队」的反馈环里才会被触及。
static const NSUInteger kDYFSMaxRootsPerPass = 8;

static void DYFSTransparencyApplyNow(UIView *root) {
    if (!root || !DYFSIsEnabled()) return;
    // 普通聊天会话窗口整个跳过：底部输入栏的毛玻璃会被兜底逻辑当成
    // 「贴底深色条」隐藏掉，表现为底栏透明一块。
    if (DYFSIsChatConversationContext(root)) return;

    // 「贴底」必须以窗口为参照：root 往往是整张 feed 列表，高度可达数千。
    UIWindow *window = root.window;
    if (!window) window = UIApplication.sharedApplication.windows.firstObject;
    UIView *reference = window ?: root;

    DYFSBottomChromeApply(root, reference);
    DYFSCardTransparencyApply(root, reference);
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
    NSUInteger processed = 0;
    while (pending.count > 0 && processed < kDYFSMaxRootsPerPass) {
        processed++;
        UIView *first = pending.firstObject;
        [pending removeObjectAtIndex:0];
        DYFSTransparencyApplyNow(first);
    }
    // 处理过程中改 hidden / 清背景会触发布局回调，回调里又入队，
    // 队列可能永远排空不了。剩下的直接丢弃 —— 这些触发点每帧都会再来，
    // 丢一次不影响最终效果，但能彻底堵死"改布局→再入队"的死循环。
    if (pending.count > 0) {
        DYFSLog([NSString stringWithFormat:
                 @"transparency queue overflow: dropped %lu root(s) to avoid main-thread hang",
                 (unsigned long)pending.count]);
        [pending removeAllObjects];
    }
    running = NO;
}
