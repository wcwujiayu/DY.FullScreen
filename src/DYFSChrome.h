//
//  DYFSChrome.h
//  DY.FullScreen
//
//  Chrome (background / progress bar) hooks, installed by Tweak.m.
//

#import <UIKit/UIKit.h>

void DYFSTabBarLayout(id self, SEL cmd);
void DYFSTabBarSetHidden(id self, SEL cmd, BOOL hidden);
void DYFSTabBarDidMoveToWindow(id self, SEL cmd);
void DYFSTabBarDidAddSubview(id self, SEL cmd, UIView *subview);
void DYFSInteractionProgressLayout(id self, SEL cmd);
void DYFSPlayerProgressLayout(id self, SEL cmd);
void DYFSChromeInstallHooks(void);
