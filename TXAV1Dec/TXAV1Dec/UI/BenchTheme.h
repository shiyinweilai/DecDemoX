//
//  BenchTheme.h
//  TXAV1Dec
//
//  统一视觉令牌：颜色、字体、间距。集中定义避免各页面散落魔法数字。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface BenchTheme : NSObject

// 颜色
+ (UIColor *)background;       ///< 页面底色
+ (UIColor *)cardBackground;   ///< 卡片底色
+ (UIColor *)cardBorder;       ///< 卡片描边
+ (UIColor *)primaryText;      ///< 主文字
+ (UIColor *)secondaryText;    ///< 次要文字
+ (UIColor *)accent;           ///< 强调色（按钮、关键指标）
+ (UIColor *)accentSoft;       ///< 强调色淡背景
+ (UIColor *)success;
+ (UIColor *)warning;
+ (UIColor *)danger;
+ (UIColor *)separator;

// 字体
+ (UIFont *)titleFont;         ///< 页面大标题
+ (UIFont *)sectionFont;        ///< 卡片标题
+ (UIFont *)metricFont;         ///< 关键数值（等宽，避免数字跳动时宽度变化）
+ (UIFont *)bodyFont;
+ (UIFont *)captionFont;       ///< 说明文字
+ (UIFont *)monoFontOfSize:(CGFloat)size;

// 间距
+ (CGFloat)screenPadding;
+ (CGFloat)cardPadding;
+ (CGFloat)cardCornerRadius;

/** 给视图应用标准卡片样式（底色 + 圆角 + 细描边） */
+ (void)applyCardStyleToView:(UIView *)view;

@end

NS_ASSUME_NONNULL_END
