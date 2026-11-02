//
//  BenchTheme.m
//  TXAV1Dec
//

#import "BenchTheme.h"

@implementation BenchTheme

+ (UIColor *)background {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.07 green:0.08 blue:0.10 alpha:1.0]
            : [UIColor colorWithRed:0.95 green:0.96 blue:0.97 alpha:1.0];
    }];
}

+ (UIColor *)cardBackground {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.13 green:0.14 blue:0.16 alpha:1.0]
            : [UIColor whiteColor];
    }];
}

+ (UIColor *)cardBorder {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.08]
            : [UIColor colorWithWhite:0.0 alpha:0.06];
    }];
}

+ (UIColor *)primaryText {
    return [UIColor labelColor];
}

+ (UIColor *)secondaryText {
    return [UIColor secondaryLabelColor];
}

+ (UIColor *)accent {
    // 靛蓝：在深色和浅色背景下都有足够对比度，且不刺眼
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:0.42 green:0.62 blue:1.00 alpha:1.0]
            : [UIColor colorWithRed:0.20 green:0.42 blue:0.92 alpha:1.0];
    }];
}

+ (UIColor *)accentSoft {
    return [[self accent] colorWithAlphaComponent:0.12];
}

+ (UIColor *)success {
    return [UIColor systemGreenColor];
}

+ (UIColor *)warning {
    return [UIColor systemOrangeColor];
}

+ (UIColor *)danger {
    return [UIColor systemRedColor];
}

+ (UIColor *)separator {
    return [UIColor separatorColor];
}

+ (UIFont *)titleFont {
    return [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
}

+ (UIFont *)sectionFont {
    return [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
}

+ (UIFont *)metricFont {
    // 等宽数字：数值刷新时字符宽度一致，界面不会左右抖动
    UIFont *base = [UIFont monospacedDigitSystemFontOfSize:26 weight:UIFontWeightSemibold];
    return base;
}

+ (UIFont *)bodyFont {
    return [UIFont systemFontOfSize:15 weight:UIFontWeightRegular];
}

+ (UIFont *)captionFont {
    return [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
}

+ (UIFont *)monoFontOfSize:(CGFloat)size {
    return [UIFont monospacedSystemFontOfSize:size weight:UIFontWeightRegular];
}

+ (CGFloat)screenPadding { return 16.0; }
+ (CGFloat)cardPadding { return 16.0; }
+ (CGFloat)cardCornerRadius { return 14.0; }

+ (void)applyCardStyleToView:(UIView *)view {
    view.backgroundColor = [self cardBackground];
    view.layer.cornerRadius = [self cardCornerRadius];
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
    view.layer.borderColor = [self cardBorder].CGColor;
}

@end
