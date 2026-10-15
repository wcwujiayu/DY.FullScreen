//
//  DYFSCardTransparency.h
//  DY.FullScreen
//
//  卡片去灰底：「相关搜索」/「合集」胶囊卡片，以及视频底部的信息 dock。
//  0.5.7 从 DYFSTransparency.m 拆出，只负责「卡片」这一类目标。
//

#import <UIKit/UIKit.h>

// root：触发点视图；reference：参照系（通常是窗口）。
void DYFSCardTransparencyApply(UIView *root, UIView *reference);
