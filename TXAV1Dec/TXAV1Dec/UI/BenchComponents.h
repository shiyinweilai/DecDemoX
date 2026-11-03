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
 * 指标矩阵：6 行指标 × N 列对象。
 *
 * 为什么是行指标、列对象：主要指标固定只有 6 项，而被比较的对象
 * （解码器版本、码流组合）数量不定，将来可能 3~4 个甚至更多。
 * 指标做行、对象做列，新增对象只是多一列，不用重排布局；
 * 反过来做（指标横排、每个对象一组格子）在对象变多时行数会膨胀，
 * 每块格子也越来越窄，最终挤到读不出数字。
 *
 * 指标名列固定在左侧不参与横向滚动，只有数值列滚动：横向滑到第 4 列时
 * 仍能知道这一行是 fps 还是 CPU，否则数字脱离行名就没有意义。
 */
@interface BenchComparisonView : UIView

/**
 * 刷新矩阵内容。
 *
 * @param headers       列标题（每列一个对象），可用 \n 分两行显示版本与码流
 * @param rowTitles     行名（固定 6 个主要指标）
 * @param values        与 rowTitles 对应的各列数值文本，values[行][列]
 * @param emphasizedRow 需要用强调色突出的行（-1 表示不突出），一般为首行 fps
 */
- (void)reloadWithHeaders:(NSArray<NSString *> *)headers
                rowTitles:(NSArray<NSString *> *)rowTitles
                   values:(NSArray<NSArray<NSString *> *> *)values
            emphasizedRow:(NSInteger)emphasizedRow;

@end

#pragma mark - 多选浮层

/**
 * 多选浮层里的一行。
 *
 * 只承载数据，选中状态由调用方维护：码流与解码器的「真值」分别在
 * selectedStreams / selectedDecoders 里，浮层只负责渲染。这样浮层关掉、
 * 重开、或界面重建都不会让选中态与业务数据脱钩。
 */
@interface BenchMultiSelectItem : NSObject

@property (nonatomic, copy) NSString *title;
/** 右侧补充信息，例如文件大小、构建时间、不可用原因 */
@property (nonatomic, copy, nullable) NSString *detail;
@property (nonatomic, assign) BOOL selected;
/** 不可用项仍然列出并说明原因，但不可点选 */
@property (nonatomic, assign) BOOL enabled;

+ (instancetype)itemWithTitle:(NSString *)title detail:(nullable NSString *)detail;

@end

/**
 * 不会自动收起的多选浮层。
 *
 * 为什么不用 UIAlertController：action sheet 的语义是「选一项即完成」，
 * 任何一次点击都会关闭面板，且没有获得点击事件的回调。早期为了支持连续
 * 多选，只能在每次选中后立刻重新弹一个，视觉上是面板反复收回又弹出，
 * 用户会误以为面板被关掉了。
 *
 * 这里改用自建浮层，交互约定为：
 * - 点任意一行：在该行原地切换选中/取消，面板保持打开；
 * - 再点一次同一行：取消选中（复选语义，不是单选）；
 * - 点面板外的空白区域：关闭；
 * - 点「完成」：关闭。
 */
@interface BenchMultiSelectPanel : UIView

/** 点击某一行的回调，index 对应传入 items 的下标 */
@property (nonatomic, copy, nullable) void (^onToggleItem)(NSInteger index);
@property (nonatomic, copy, nullable) void (^onSelectAll)(void);
@property (nonatomic, copy, nullable) void (^onDismiss)(void);

/**
 * 可选的第三个快捷动作，例如解码器面板的「仅选最新版本」。
 *
 * 用独立入口而不是往 items 里塞一行「动作行」：动作与选项混在同一个列表里，
 * 勾选符号会和动作文字并排出现，用户很难分辨哪些行是可勾选的项。
 * 传 nil 时该按钮不显示。
 */
- (void)setExtraActionTitle:(nullable NSString *)title handler:(nullable void (^)(void))handler;

/**
 * 在 hostView（通常是窗口或控制器根视图）上弹出浮层。
 *
 * 用 addSubview 而不是 presentViewController：浮层只是配置面板，
 * 不是独立页面，关闭时也不需要处理转场，铺在窗口上最直接，
 * 也不影响控制器自身的 presentedViewController 状态。
 */
+ (nullable instancetype)presentInView:(UIView *)hostView
                                 title:(NSString *)title
                               message:(nullable NSString *)message
                                 items:(NSArray<BenchMultiSelectItem *> *)items;

/** 用新的数据重建列表，选中态变化后调用即可，不影响面板的开合状态 */
- (void)reloadWithItems:(NSArray<BenchMultiSelectItem *> *)items;

/** 关闭并移除自身 */
- (void)dismiss;

@end

#pragma mark - 次要按钮

/** 描边样式的次要按钮，用于「复制报告」这类非主操作 */
@interface BenchSecondaryButton : UIButton

+ (instancetype)buttonWithTitle:(NSString *)title;

/** 更小内边距的版本，用于卡片表头内这类空间紧张的位置 */
+ (instancetype)compactButtonWithTitle:(NSString *)title;

@end

#pragma mark - 轻提示

/**
 * 短暂浮在屏幕底部的轻提示，用于「已复制到剪贴板」这类一次性反馈。
 *
 * 为什么不用 UIAlertController：导出是低风险操作，弹窗需要用户再点一次
 * 才能消失，打断成本高于信息价值；轻提示出现后自动消失，不阻断操作。
 */
@interface BenchToastView : UIView

/// 在指定视图底部弹出一条提示，重复调用会替换掉尚未消失的旧提示
+ (void)showInView:(UIView *)hostView message:(NSString *)message;

@end

NS_ASSUME_NONNULL_END
