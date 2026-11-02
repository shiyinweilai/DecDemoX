//
//  ViewController.h
//  TXAV1Dec
//

#import <UIKit/UIKit.h>

/**
 * 解码性能测试主界面。
 *
 * 界面采用单页纵向流式布局：设备信息 → 码流选择 → 测试参数 → 结果面板 → 报告。
 * 所有视图均由代码构建，不依赖 storyboard，便于后续增删指标而不必同步维护 xib。
 */
@interface ViewController : UIViewController

/// 由启动参数触发：同步码流后自动跑一轮最小配置测试，并打印结果到控制台。
/// 用于开发期在真机上验证端到端链路，正常使用时不会走到。
- (void)runHeadlessSelfTest;

@end
