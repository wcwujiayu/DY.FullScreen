//
//  DYFSSettings.h
//  DY.FullScreen
//
//  设置入口：抖音原生「设置」页的 DY.FullScreen 入口行，以及二级页与诊断详情。
//

#import <UIKit/UIKit.h>

void DYFSNativeSettingsDidAppear(id self, SEL cmd, BOOL animated);

void DYFSSettingsInstallHooks(void);
