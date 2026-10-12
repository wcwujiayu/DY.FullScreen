//
// DYLiveFeedFullscreen.m
// DY.FullScreen
//

#import "DYLiveFeedFullscreen.h"


@implementation DYLiveFeedFullscreen


// 模块加载测试
+ (void)load {

    NSLog(@"DYLiveFeedFullscreen loaded");

}



+ (instancetype)sharedInstance {

    static DYLiveFeedFullscreen *manager;

    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{

        manager = [[self alloc] init];

    });

    return manager;
}



- (BOOL)isLiveFeedView:(UIView *)view {


    if (!view) {

        return NO;

    }


    NSString *className =
    NSStringFromClass([view class]);


    if ([className.lowercaseString containsString:@"live"]) {

        return YES;

    }


    return NO;
}



- (void)processLiveFeedView:(UIView *)view {


    if (![self isLiveFeedView:view]) {

        return;

    }


    // 后续接入 DYYY 信息流直播卡片全屏逻辑


}


@end
