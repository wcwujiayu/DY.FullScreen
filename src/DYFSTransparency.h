//
//  DYFSTransparency.h
//  DY.FullScreen
//
//  视频底部信息/评论 dock 与「相关搜索」/「合集」胶囊卡片的背景透明化。
//

#import <UIKit/UIKit.h>

/// 在 root 视图树中定位并透明化目标区域。
/// 只清除背景（backgroundColor / layer / 渐变），不动文字、透明度、图标与交互。
void DYFSTransparencyApplyInView(UIView *root);
