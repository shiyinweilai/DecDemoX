//
//  AppDelegate.m
//  TXAV1Dec
//
//  Created by 又贵又不好用的MacBookPro on 2022/12/6.
//

#import "AppDelegate.h"

@interface AppDelegate ()

    

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // 注意：不要在这里捕获内存基线。此时进程 footprint 只有几 MB，
    // 界面、字体、UIKit 都还没加载，之后它们会长到几十 MB，
    // 那样算出的「净内存」会把界面开销全算成解码器成本。
    // 基线在界面加载完成后、首次解码之前捕获，见 ViewController。
    return YES;
}


#pragma mark - UISceneSession lifecycle


- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}


- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
    // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
}


@end
