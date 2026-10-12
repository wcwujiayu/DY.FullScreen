//
//  DYFSSettings.h
//  DY.FullScreen
//
//  Settings entry points, installed by Tweak.m.
//

#import <UIKit/UIKit.h>

void DYFSScanForSettingsEntry(UIView *root, NSUInteger depth);
void DYFSLeftSidebarIconDidMove(id self, SEL cmd);
void DYFSLeftSidebarRightDidMove(id self, SEL cmd);
void DYFSNativeSettingsDidAppear(id self, SEL cmd, BOOL animated);
void DYFSSettingsInstallHooks(void);
