//
// DYLiveFeedFullscreen.h
// DY.FullScreen
//

#import <UIKit/UIKit.h>


@interface DYLiveFeedFullscreen : NSObject


+ (instancetype)sharedInstance;


- (BOOL)isLiveFeedView:(UIView *)view;


- (void)processLiveFeedView:(UIView *)view;


@end
