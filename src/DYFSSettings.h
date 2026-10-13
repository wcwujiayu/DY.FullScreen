//
//  DYFSSettings.h
//  DY.FullScreen
//
//  设置入口：侧边栏按钮、插件自身的诊断面板、注入抖音原生设置的开关。
//

#import <UIKit/UIKit.h>

void DYFSNativeSettingsDidAppear(id self, SEL cmd, BOOL animated);

void DYFSSettingsInstallHooks(void);
