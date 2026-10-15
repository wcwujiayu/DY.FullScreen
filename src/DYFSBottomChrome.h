//
//  DYFSBottomChrome.h
//  DY.FullScreen
//
//  底部栏清理：全局 TabBar 背景、各页面自带的贴底黑条、互动右栏纯黑底。
//  0.5.7 从 DYFSTransparency.m 拆出，只负责「底栏」这一类目标。
//

#import <UIKit/UIKit.h>

// root：触发点视图；reference：参照系（通常是窗口）。
void DYFSBottomChromeApply(UIView *root, UIView *reference);
