//
//  BenchComponents.h
//  TXAV1Dec
//
//  可复用的界面组件。抽出来的目的是让主界面的组装代码只关心结构，
//  不必重复写圆角、描边、字体这些细节。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 卡片容器

/** 带标题的卡片容器，内容通过 contentView 添加 */
@interface BenchCardView : UIView

@property (nonatomic, readonly) UILabel *titleLabel;
@property (nonatomic, readonly) UIView *contentView;

- (instancetype)initWithTitle:(nullable NSString *)title;
- (instancetype)initWithTitle:(nullable NSString *)title
                     subtitle:(nullable NSString *)subtitle;

/**
 * 在标题行右侧放入一个控件（如「刷新」按钮）。
 *
 * 放在标题同一行可以省掉一整行垂直空间，紧凑布局里很关键。
 * 卡片没有标题时该方法不生效。
 */
- (void)insertHeaderAccessory:(UIView *)accessory;

@end

#pragma mark - 折叠入口

/**
 * 可折叠区块的头部：左侧标题，右侧摘要 + 指示箭头。
 *
 * 用途是把「测试对象」这类低频修改、但需要随时看一眼当前值的配置收进一行。
 * 收起态本身就要有信息量：摘要显示当前解码器与码流数，用户不展开也知道在测什么，
 * 避免折叠后还要点开确认。
 */
@interface BenchDisclosureRow : UIView

@property (nonatomic, readonly) UIButton *button;

- (instancetype)initWithTitle:(NSString *)title;

/** 右侧摘要文本，收起时代表当前配置，例如 "av1d 1.4.1 · 1 个码流" */
- (void)setSummary:(nullable NSString *)summary;

- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated;

@end

#pragma mark - 指标块

/** 单个指标展示块：上方标题，下方数值 + 单位 */
@interface BenchMetricTile : UIView

@property (nonatomic, readonly) UILabel *valueLabel;
@property (nonatomic, readonly) UILabel *unitLabel;
@property (nonatomic, readonly) UILabel *captionLabel;

- (instancetype)initWithCaption:(NSString *)caption;

/**
 * 指定数值字号。
 *
 * 一行放三个指标时每格宽度只有约 100pt，用默认 26pt 字号的数值会被压缩，
 * 因此紧凑排布时传入更小的字号。
 */
- (instancetype)initWithCaption:(NSString *)caption valueFontSize:(CGFloat)fontSize;

- (void)setValue:(NSString *)value unit:(nullable NSString *)unit;
- (void)setValue:(NSString *)value
            unit:(nullable NSString *)unit
        emphasis:(BOOL)emphasis;

/**
 * 设置数值下方的补充说明，例如「= 2.3 核」或「越低越好」。
 *
 * 指标格空间有限，主数值只能放一位有效信息；口径换算、优劣方向这类
 * 说明放这一行，既不打乱栅格，也不用让用户去翻文档。
 */
- (void)setFootnote:(nullable NSString *)footnote;

@end

#pragma mark - 参数行

/**
 * 一行「标签 + 输入框 + 单位」。
 *
 * 用 UITextField 而不是 UIStepper：测试帧数、轮次这些数值跨度大，
 * 手动输入比反复点击步进器更快。
 */
@interface BenchFieldRow : UIView

@property (nonatomic, readonly) UITextField *textField;
@property (nonatomic, readonly) UILabel *titleLabel;

- (instancetype)initWithTitle:(NSString *)title
                unit:(nullable NSString *)unit
              keyboard:(UIKeyboardType)keyboard;

/** 读取整数值，非法或为空时返回 fallback */
- (NSInteger)integerValueWithFallback:(NSInteger)fallback;

@end

#pragma mark - 紧凑输入格

/**
 * 「小标题 + 输入框」竖向排列的紧凑输入格。
 *
 * 与 BenchFieldRow 的区别：FieldRow 是整行「标题－输入框－单位」，
 * 一行只能放一个参数；本组件把标题压到输入框上方，于是可以一行并排 4 个，
 * 在手机上显著缩短表单高度。
 */
@interface BenchCompactField : UIView

@property (nonatomic, readonly) UITextField *textField;
@property (nonatomic, readonly) UILabel *captionLabel;

- (instancetype)initWithCaption:(NSString *)caption
                      unitSuffix:(nullable NSString *)unitSuffix
                       keyboard:(UIKeyboardType)keyboard;

/** 读取整数值，非法或为空时返回 fallback */
- (NSInteger)integerValueWithFallback:(NSInteger)fallback;

@end

#pragma mark - 单选分段行

/** 标签 + 分段控件，用于枚举型配置 */
@interface BenchSegmentRow : UIView

@property (nonatomic, readonly) UISegmentedControl *segmentedControl;
@property (nonatomic, readonly) UILabel *titleLabel;

- (instancetype)initWithTitle:(NSString *)title items:(NSArray<NSString *> *)items;

@end

#pragma mark - 多码流对比

/**
 * 多码流横向对比表。
 *
 * 批量测试多个码流后，把关键指标按行排成一张紧凑表，便于一眼看出
 * 哪个码流更吃力、哪个解码器更省 CPU。列数自适应：码流少时不留空列。
 */
@interface BenchComparisonView : UIView

/**
 * 刷新对比内容。
 *
 * @param headers   列标题（每个码流一列）
 * @param rowTitles 行名（每个指标一行）
 * @param values    与 rowTitles 对应的各列数值文本
 */
- (void)reloadWithHeaders:(NSArray<NSString *> *)headers
                rowTitles:(NSArray<NSString *> *)rowTitles
                   values:(NSArray<NSArray<NSString *> *> *)values;

@end

#pragma mark - 次要按钮

/** 描边样式的次要按钮，用于「复制报告」这类非主操作 */
@interface BenchSecondaryButton : UIButton

+ (instancetype)buttonWithTitle:(NSString *)title;

/** 更小内边距的版本，用于卡片表头内这类空间紧张的位置 */
+ (instancetype)compactButtonWithTitle:(NSString *)title;

@end

NS_ASSUME_NONNULL_END
