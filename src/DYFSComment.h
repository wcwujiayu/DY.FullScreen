//
//  DYFSComment.h
//  DY.FullScreen
//
//  评论区 / 输入栏透明化。
//
//  这一整套是 0.3.15 独有的功能，0.4.x 拆分重构时被整段弄丢，
//  在本次重建中重新保留。
//

#import <UIKit/UIKit.h>

/// 清理详情页 / 个人主页视频底部那条自带的贴底黑条与评论 dock 背景。
void DYFSApplyVideoDetailBottomTransparencyInView(UIView *root);

void DYFSCommentPanelLayout(id self, SEL cmd);
void DYFSCommentInputContainerLayout(id self, SEL cmd);
void DYFSCommentInputBackgroundLayout(id self, SEL cmd);
void DYFSCommentInputControllerLayout(id self, SEL cmd);

void DYFSCommentInstallHooks(void);
