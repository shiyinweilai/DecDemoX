//
//  BenchComponents.m
//  TXAV1Dec
//

#import "BenchComponents.h"
#import "BenchTheme.h"

#pragma mark - BenchCardView

@interface BenchCardView ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIStackView *rootStack;
@property (nonatomic, strong) UIStackView *headerStack;
@end

@implementation BenchCardView

- (instancetype)initWithTitle:(NSString *)title {
    return [self initWithTitle:title subtitle:nil];
}

- (instancetype)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;

    [BenchTheme applyCardStyleToView:self];

    _rootStack = [[UIStackView alloc] init];
    _rootStack.axis = UILayoutConstraintAxisVertical;
    _rootStack.spacing = 12;
    _rootStack.alignment = UIStackViewAlignmentFill;
    _rootStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_rootStack];

    const CGFloat pad = [BenchTheme cardPadding];
    [NSLayoutConstraint activateConstraints:@[
        [_rootStack.topAnchor constraintEqualToAnchor:self.topAnchor constant:pad],
        [_rootStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:pad],
        [_rootStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-pad],
        [_rootStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-pad],
    ]];

    if (title.length > 0) {
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.text = title;
        _titleLabel.font = [BenchTheme sectionFont];
        _titleLabel.textColor = [BenchTheme secondaryText];
        // 中文标题用系统大写会显得怪异，这里只做字重强调，不做大小写转换
        [_titleLabel setContentHuggingPriority:UILayoutPriorityDefaultHigh
                                       forAxis:UILayoutConstraintAxisHorizontal];

        _headerStack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel]];
        _headerStack.axis = UILayoutConstraintAxisHorizontal;
        _headerStack.alignment = UIStackViewAlignmentCenter;
        _headerStack.spacing = 8;
        [_rootStack addArrangedSubview:_headerStack];
    }

    if (subtitle.length > 0) {
        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.text = subtitle;
        _subtitleLabel.font = [BenchTheme captionFont];
        _subtitleLabel.textColor = [BenchTheme secondaryText];
        _subtitleLabel.numberOfLines = 0;
        [_rootStack addArrangedSubview:_subtitleLabel];
    }

    _contentView = [[UIView alloc] init];
    [_rootStack addArrangedSubview:_contentView];

    return self;
}

- (void)insertHeaderAccessory:(UIView *)accessory {
    if (!self.headerStack || !accessory) return;

    // 用弹性占位把附属控件推到最右侧，标题保持左对齐
    UIView *spacer = [[UIView alloc] init];
    [spacer setContentHuggingPriority:UILayoutPriorityDefaultLow - 1
                              forAxis:UILayoutConstraintAxisHorizontal];
    [spacer setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                            forAxis:UILayoutConstraintAxisHorizontal];

    [self.headerStack addArrangedSubview:spacer];
    [self.headerStack addArrangedSubview:accessory];
}

@end

#pragma mark - BenchMetricTile

@interface BenchMetricTile ()
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UILabel *unitLabel;
@property (nonatomic, strong) UILabel *captionLabel;
@property (nonatomic, strong) UILabel *footnoteLabel;
@property (nonatomic, strong) UIStackView *valueStack;
@end

@implementation BenchMetricTile

- (instancetype)initWithCaption:(NSString *)caption {
    return [self initWithCaption:caption valueFontSize:26.0];
}

- (instancetype)initWithCaption:(NSString *)caption valueFontSize:(CGFloat)fontSize {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;

    _captionLabel = [[UILabel alloc] init];
    _captionLabel.text = caption;
    _captionLabel.font = [BenchTheme captionFont];
    _captionLabel.textColor = [BenchTheme secondaryText];
    _captionLabel.numberOfLines = 1;
    _captionLabel.adjustsFontSizeToFitWidth = YES;
    _captionLabel.minimumScaleFactor = 0.8;

    _valueLabel = [[UILabel alloc] init];
    // 等宽数字，数值刷新时宽度不跳动
    _valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:fontSize
                                                       weight:UIFontWeightSemibold];
    _valueLabel.textColor = [BenchTheme primaryText];
    _valueLabel.text = @"--";
    // 单行 + 缩字：极端数值（如 12345.6）也不能换行破坏栅格
    _valueLabel.numberOfLines = 1;
    _valueLabel.adjustsFontSizeToFitWidth = YES;
    _valueLabel.minimumScaleFactor = 0.6;

    _unitLabel = [[UILabel alloc] init];
    _unitLabel.font = [BenchTheme captionFont];
    _unitLabel.textColor = [BenchTheme secondaryText];
    _unitLabel.text = @"";

    // 脚注默认隐藏，只有需要解释口径时才显示，避免空行撑高栅格。
    // 字号跟随 captionFont 派生而不是写死 10pt：放大整体字号时这里也要跟着放大，
    // 否则「口径说明」反而成了整屏最小的字。允许两行，变长后换行而非缩字。
    _footnoteLabel = [[UILabel alloc] init];
    _footnoteLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    _footnoteLabel.textColor = [BenchTheme secondaryText];
    _footnoteLabel.numberOfLines = 2;
    _footnoteLabel.adjustsFontSizeToFitWidth = YES;
    _footnoteLabel.minimumScaleFactor = 0.8;
    _footnoteLabel.hidden = YES;

    _valueStack = [[UIStackView alloc] initWithArrangedSubviews:@[_valueLabel, _unitLabel]];
    _valueStack.axis = UILayoutConstraintAxisHorizontal;
    _valueStack.spacing = 4;
    // 基线对齐让数值和单位底部一致，比默认的居中对齐更协调
    _valueStack.alignment = UIStackViewAlignmentFirstBaseline;
    _valueStack.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        _captionLabel, _valueStack, _footnoteLabel
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 4;
    stack.alignment = UIStackViewAlignmentLeading;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    return self;
}

- (UILabel *)valueLabel { return _valueLabel; }
- (UILabel *)unitLabel { return _unitLabel; }
- (UILabel *)captionLabel { return _captionLabel; }

- (void)setValue:(NSString *)value unit:(NSString *)unit {
    [self setValue:value unit:unit emphasis:NO];
}

- (void)setValue:(NSString *)value unit:(NSString *)unit emphasis:(BOOL)emphasis {
    self.valueLabel.text = value ?: @"--";
    self.unitLabel.text = unit ?: @"";
    self.valueLabel.textColor = emphasis ? [BenchTheme accent] : [BenchTheme primaryText];
    // 单字符单位（%、x）在 4pt 间距下会显得脱离数值，收紧到 2pt
    self.valueStack.spacing = (unit.length == 1) ? 2.0 : 4.0;
}

- (void)setFootnote:(NSString *)footnote {
    self.footnoteLabel.text = footnote;
    self.footnoteLabel.hidden = (footnote.length == 0);
}

@end

#pragma mark - BenchDisclosureRow

@interface BenchDisclosureRow ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *summaryLabel;
@property (nonatomic, strong) UIImageView *chevronView;
@end

@implementation BenchDisclosureRow

- (instancetype)initWithTitle:(NSString *)title {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = title;
    _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _titleLabel.textColor = [BenchTheme primaryText];
    [_titleLabel setContentHuggingPriority:UILayoutPriorityRequired
                                   forAxis:UILayoutConstraintAxisHorizontal];

    _summaryLabel = [[UILabel alloc] init];
    _summaryLabel.font = [BenchTheme captionFont];
    _summaryLabel.textColor = [BenchTheme secondaryText];
    _summaryLabel.textAlignment = NSTextAlignmentRight;
    _summaryLabel.numberOfLines = 1;
    _summaryLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    // 摘要比标题更容易被压缩：空间不足时先截断摘要，保证标题完整可读
    [_summaryLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                                   forAxis:UILayoutConstraintAxisHorizontal];

    _chevronView = [[UIImageView alloc] initWithImage:
                    [UIImage systemImageNamed:@"chevron.down"]];
    _chevronView.tintColor = [BenchTheme secondaryText];
    _chevronView.contentMode = UIViewContentModeScaleAspectFit;
    [_chevronView.widthAnchor constraintEqualToConstant:12].active = YES;
    [_chevronView.heightAnchor constraintEqualToConstant:12].active = YES;
    [_chevronView setContentHuggingPriority:UILayoutPriorityRequired
                                    forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[
        _titleLabel, _summaryLabel, _chevronView
    ]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 8;
    row.userInteractionEnabled = NO;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:row];

    // 整行都是点按热区，而不是只有箭头可点
    _button = [UIButton buttonWithType:UIButtonTypeSystem];
    _button.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_button];

    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:self.topAnchor constant:2],
        [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-2],
        [_button.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_button.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_button.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_button.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    return self;
}

- (void)setSummary:(NSString *)summary {
    self.summaryLabel.text = summary;
}

- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated {
    // 箭头方向是唯一的状态提示。这里不做转场动画：
    // 该方法可能在界面首次布局之前被调用，跨溶解动画会持有可能尚未完成
    // 布局的视图，实测在启动路径上会崩。状态切换本身就是瞬时的，无动画也无损体验。
    self.chevronView.image = [UIImage systemImageNamed:expanded ? @"chevron.up" : @"chevron.down"];
}

@end

#pragma mark - BenchFieldRow

@interface BenchFieldRow ()
@property (nonatomic, strong) UITextField *textField;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *unitLabel;
@end

@implementation BenchFieldRow

- (instancetype)initWithTitle:(NSString *)title
                         unit:(NSString *)unit
                     keyboard:(UIKeyboardType)keyboard {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = title;
    _titleLabel.font = [BenchTheme bodyFont];
    _titleLabel.textColor = [BenchTheme primaryText];
    [_titleLabel setContentHuggingPriority:UILayoutPriorityDefaultHigh
                                   forAxis:UILayoutConstraintAxisHorizontal];

    _textField = [[UITextField alloc] init];
    _textField.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightMedium];
    _textField.textColor = [BenchTheme primaryText];
    _textField.backgroundColor = [BenchTheme accentSoft];
    _textField.layer.cornerRadius = 8;
    _textField.layer.cornerCurve = kCACornerCurveContinuous;
    _textField.textAlignment = NSTextAlignmentCenter;
    _textField.keyboardType = keyboard;
    _textField.returnKeyType = UIReturnKeyDone;
    // 输入框宽度固定，避免不同位数导致整行宽度跳动
    [_textField.widthAnchor constraintEqualToConstant:88].active = YES;
    [_textField.heightAnchor constraintEqualToConstant:34].active = YES;
    // 内边距：UITextField 没有原生 padding，用左侧空白视图模拟
    UIView *leftPad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 34)];
    _textField.leftView = leftPad;
    _textField.leftViewMode = UITextFieldViewModeAlways;
    UIView *rightPad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 34)];
    _textField.rightView = rightPad;
    _textField.rightViewMode = UITextFieldViewModeAlways;

    _unitLabel = [[UILabel alloc] init];
    _unitLabel.font = [BenchTheme captionFont];
    _unitLabel.textColor = [BenchTheme secondaryText];
    _unitLabel.text = unit ?: @"";

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _textField, _unitLabel]];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.spacing = 10;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    return self;
}

- (UITextField *)textField { return _textField; }
- (UILabel *)titleLabel { return _titleLabel; }

- (NSInteger)integerValueWithFallback:(NSInteger)fallback {
    NSString *text = [self.textField.text stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) return fallback;
    NSInteger value = [text integerValue];
    return value > 0 ? value : fallback;
}

@end

#pragma mark - BenchCompactField

@interface BenchCompactField ()
@property (nonatomic, strong) UITextField *textField;
@property (nonatomic, strong) UILabel *captionLabel;
@end

@implementation BenchCompactField

- (instancetype)initWithCaption:(NSString *)caption
                     unitSuffix:(NSString *)unitSuffix
                       keyboard:(UIKeyboardType)keyboard {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;

    _captionLabel = [[UILabel alloc] init];
    _captionLabel.text = caption;
    _captionLabel.font = [BenchTheme captionFont];
    _captionLabel.textColor = [BenchTheme secondaryText];
    _captionLabel.numberOfLines = 1;
    _captionLabel.adjustsFontSizeToFitWidth = YES;
    _captionLabel.minimumScaleFactor = 0.75;

    _textField = [[UITextField alloc] init];
    _textField.font = [UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightMedium];
    _textField.textColor = [BenchTheme primaryText];
    _textField.backgroundColor = [BenchTheme accentSoft];
    _textField.layer.cornerRadius = 8;
    _textField.layer.cornerCurve = kCACornerCurveContinuous;
    _textField.textAlignment = NSTextAlignmentCenter;
    _textField.keyboardType = keyboard;
    _textField.returnKeyType = UIReturnKeyDone;
    // 高度略低于整行版本，压缩纵向占用
    [_textField.heightAnchor constraintEqualToConstant:32].active = YES;

    UIView *leftPad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 6, 32)];
    _textField.leftView = leftPad;
    _textField.leftViewMode = UITextFieldViewModeAlways;
    UIView *rightPad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 6, 32)];
    _textField.rightView = rightPad;
    _textField.rightViewMode = UITextFieldViewModeAlways;

    NSMutableArray<UIView *> *captionViews = [NSMutableArray arrayWithObject:_captionLabel];
    if (unitSuffix.length > 0) {
        UILabel *unitLabel = [[UILabel alloc] init];
        unitLabel.text = unitSuffix;
        unitLabel.font = [BenchTheme captionFont];
        unitLabel.textColor = [BenchTheme secondaryText];
        [unitLabel setContentCompressionResistancePriority:UILayoutPriorityRequired
                                                   forAxis:UILayoutConstraintAxisHorizontal];
        [captionViews addObject:unitLabel];
    }

    UIStackView *captionStack = [[UIStackView alloc] initWithArrangedSubviews:captionViews];
    captionStack.axis = UILayoutConstraintAxisHorizontal;
    captionStack.spacing = 4;
    captionStack.alignment = UIStackViewAlignmentCenter;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[captionStack, _textField]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    return self;
}

- (UITextField *)textField { return _textField; }
- (UILabel *)captionLabel { return _captionLabel; }

- (NSInteger)integerValueWithFallback:(NSInteger)fallback {
    NSString *text = [self.textField.text stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) return fallback;
    NSInteger value = [text integerValue];
    return value > 0 ? value : fallback;
}

@end

#pragma mark - BenchSegmentRow

@interface BenchSegmentRow ()
@property (nonatomic, strong) UISegmentedControl *segmentedControl;
@property (nonatomic, strong) UILabel *titleLabel;
@end

@implementation BenchSegmentRow

- (instancetype)initWithTitle:(NSString *)title items:(NSArray<NSString *> *)items {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = title;
    _titleLabel.font = [BenchTheme bodyFont];
    _titleLabel.textColor = [BenchTheme primaryText];

    _segmentedControl = [[UISegmentedControl alloc] initWithItems:items];
    _segmentedControl.selectedSegmentIndex = 0;
    [_segmentedControl setContentHuggingPriority:UILayoutPriorityDefaultLow
                                         forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _segmentedControl]];
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.spacing = 10;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    return self;
}

- (UISegmentedControl *)segmentedControl { return _segmentedControl; }
- (UILabel *)titleLabel { return _titleLabel; }

@end

#pragma mark - BenchComparisonView

@interface BenchComparisonView ()
@property (nonatomic, strong) UIStackView *titleColumn;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) NSLayoutConstraint *contentWidthConstraint;
@property (nonatomic, assign) NSUInteger columnCount;
@property (nonatomic, assign) NSInteger emphasizedRow;
@property (nonatomic, assign) CGFloat lastLayoutWidth;
@end

@implementation BenchComparisonView

/// 行名固定宽度：六个指标名中最长的「CPU 整机」在 14pt 下约 72pt，
/// 留到 86pt 可以完整显示而不触发缩字。
static const CGFloat kTitleColumnWidth = 86.0;

/// 单元格横向内距。列少时会等分铺满，列多时按最小列宽撑开并横向滚动。
static const CGFloat kColumnGap = 8.0;

/// 单列最小宽度。低于这个宽度时 "123.45" 这类五位数会被压缩到读不清，
/// 所以宁可滚动也不继续挤。
static const CGFloat kMinColumnWidth = 74.0;

static const CGFloat kHeaderHeight = 46.0;
static const CGFloat kRowHeight = 40.0;

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.emphasizedRow = -1;

    // 左侧行名列：不放进滚动视图，横向滑动时保持可见。
    // 否则滑到第 4 列时数字还在、行名走了，那一列就只是六个无法解读的数字。
    _titleColumn = [[UIStackView alloc] init];
    _titleColumn.axis = UILayoutConstraintAxisVertical;
    _titleColumn.spacing = 0;
    _titleColumn.alignment = UIStackViewAlignmentFill;
    _titleColumn.translatesAutoresizingMaskIntoConstraints = NO;
    [_titleColumn.widthAnchor constraintEqualToConstant:kTitleColumnWidth].active = YES;

    _scrollView = [[UIScrollView alloc] init];
    _scrollView.showsHorizontalScrollIndicator = YES;
    _scrollView.showsVerticalScrollIndicator = NO;
    _scrollView.alwaysBounceHorizontal = YES;
    // 纵向由外层页面负责，这里只消费横向手势，避免和外层滚动互相抢
    _scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;

    _contentStack = [[UIStackView alloc] init];
    _contentStack.axis = UILayoutConstraintAxisVertical;
    _contentStack.spacing = 0;
    _contentStack.alignment = UIStackViewAlignmentFill;
    _contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    [_scrollView addSubview:_contentStack];

    id contentGuide = _scrollView.contentLayoutGuide;
    _contentWidthConstraint = [_contentStack.widthAnchor
        constraintEqualToAnchor:_scrollView.frameLayoutGuide.widthAnchor
                       constant:0];

    [NSLayoutConstraint activateConstraints:@[
        [_contentStack.topAnchor constraintEqualToAnchor:[contentGuide topAnchor]],
        [_contentStack.leadingAnchor constraintEqualToAnchor:[contentGuide leadingAnchor]],
        [_contentStack.trailingAnchor constraintEqualToAnchor:[contentGuide trailingAnchor]],
        [_contentStack.bottomAnchor constraintEqualToAnchor:[contentGuide bottomAnchor]],
        _contentWidthConstraint,
        [_scrollView.heightAnchor constraintEqualToConstant:
            kHeaderHeight + kRowHeight * 6],
        [_titleColumn.heightAnchor constraintEqualToConstant:
            kHeaderHeight + kRowHeight * 6],
    ]];

    [self addSubview:_titleColumn];
    [self addSubview:_scrollView];

    [NSLayoutConstraint activateConstraints:@[
        [_titleColumn.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_titleColumn.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_titleColumn.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:_titleColumn.trailingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_scrollView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    return self;
}

- (UILabel *)labelWithText:(NSString *)text
                      font:(UIFont *)font
                     color:(UIColor *)color
                 alignment:(NSTextAlignment)alignment {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.textAlignment = alignment;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.7;
    label.numberOfLines = 1;
    return label;
}

/// 行名左侧固定列。高度用固定常量，才能和右侧滚动区的每一行严丝合缝对齐：
/// 两侧分属不同父视图，无法互相引用高度锚点，靠等值常量是对齐的唯一可靠办法。
- (void)rebuildTitleColumnWithRowTitles:(NSArray<NSString *> *)rowTitles {
    for (UIView *view in self.titleColumn.arrangedSubviews) {
        [self.titleColumn removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    // 顶部与右侧表头等高留白，使第一个指标行与第一行数值齐平
    UIView *headerSpacer = [[UIView alloc] init];
    [headerSpacer.heightAnchor constraintEqualToConstant:kHeaderHeight].active = YES;
    [self.titleColumn addArrangedSubview:headerSpacer];

    for (NSString *title in rowTitles) {
        UILabel *label = [self labelWithText:title
                                        font:[BenchTheme captionFont]
                                       color:[BenchTheme secondaryText]
                                   alignment:NSTextAlignmentLeft];
        label.numberOfLines = 2;
        UIView *holder = [[UIView alloc] init];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [holder addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [holder.heightAnchor constraintEqualToConstant:kRowHeight],
            [label.leadingAnchor constraintEqualToAnchor:holder.leadingAnchor],
            [label.trailingAnchor constraintEqualToAnchor:holder.trailingAnchor constant:-6],
            [label.centerYAnchor constraintEqualToAnchor:holder.centerYAnchor],
        ]];
        [self.titleColumn addArrangedSubview:holder];
    }
}

- (void)reloadWithHeaders:(NSArray<NSString *> *)headers
                rowTitles:(NSArray<NSString *> *)rowTitles
                   values:(NSArray<NSArray<NSString *> *> *)values
            emphasizedRow:(NSInteger)emphasizedRow {
    for (UIView *view in self.contentStack.arrangedSubviews) {
        [self.contentStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    self.columnCount = headers.count;
    self.emphasizedRow = emphasizedRow;
    [self rebuildTitleColumnWithRowTitles:rowTitles];

    // 表头行：每个对象一列。用两行显示（版本 + 码流）而不是单行拼接，
    // 因为多版本多码流时单行会很长，等分到窄列里必然被截断，
    // 而列头被截断就分不清哪列是哪个版本。
    UIStackView *headerRow = [[UIStackView alloc] init];
    headerRow.axis = UILayoutConstraintAxisHorizontal;
    headerRow.spacing = kColumnGap;
    headerRow.distribution = UIStackViewDistributionFillEqually;
    [headerRow.heightAnchor constraintEqualToConstant:kHeaderHeight].active = YES;

    for (NSString *header in headers) {
        UILabel *label = [self labelWithText:header
                                        font:[UIFont systemFontOfSize:12 weight:UIFontWeightMedium]
                                       color:[BenchTheme secondaryText]
                                   alignment:NSTextAlignmentCenter];
        label.numberOfLines = 2;
        // 列头跟随横向滚动，用户滑到右侧时仍能看到这一列属于哪个版本
        [headerRow addArrangedSubview:label];
    }
    [self.contentStack addArrangedSubview:headerRow];

    for (NSUInteger row = 0; row < rowTitles.count; row++) {
        UIStackView *line = [[UIStackView alloc] init];
        line.axis = UILayoutConstraintAxisHorizontal;
        line.spacing = kColumnGap;
        line.distribution = UIStackViewDistributionFillEqually;
        [line.heightAnchor constraintEqualToConstant:kRowHeight].active = YES;

        NSArray<NSString *> *cells = row < values.count ? values[row] : @[];
        const BOOL emphasized = (NSInteger)row == self.emphasizedRow;
        for (NSUInteger col = 0; col < headers.count; col++) {
            NSString *text = col < cells.count ? cells[col] : @"--";
            // 首行 fps 用强调色：它是选型时最先看的数字，
            // 其余指标降为常规主文字色，避免整张表都是强调色反而没有重点。
            UILabel *label = [self labelWithText:text
                                            font:emphasized
                                                 ? [UIFont monospacedDigitSystemFontOfSize:16
                                                                                   weight:UIFontWeightSemibold]
                                                 : [BenchTheme monoFontOfSize:15]
                                           color:emphasized ? [BenchTheme accent]
                                                            : [BenchTheme primaryText]
                                       alignment:NSTextAlignmentCenter];
            [line addArrangedSubview:label];
        }
        [self.contentStack addArrangedSubview:line];

        // 行间分隔线：六行数字等宽等距排布，没有横线时视线容易串行
        if (row + 1 < rowTitles.count) {
            UIView *separator = [[UIView alloc] init];
            separator.backgroundColor = [BenchTheme separator];
            [separator.heightAnchor constraintEqualToConstant:0.5].active = YES;
            [self.contentStack addArrangedSubview:separator];
        }
    }

    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    const CGFloat available = CGRectGetWidth(self.scrollView.bounds);
    if (available <= 0 || available == self.lastLayoutWidth) return;
    self.lastLayoutWidth = available;

    const NSUInteger columns = MAX(self.columnCount, (NSUInteger)1);
    // 列少时等分铺满可视宽度（3~4 列能舒展开）；
    // 列多到每列低于最小宽度时停止压缩，改为撑开内容让用户横向滑动。
    // 直接等分会在 6 列以上时把每列压到 40pt 左右，数字必然被缩小到读不出。
    const CGFloat byEqualSplit = (available - kColumnGap * (columns - 1)) / columns;
    const CGFloat columnWidth = MAX(byEqualSplit, kMinColumnWidth);
    const CGFloat required = columnWidth * columns + kColumnGap * (columns - 1);

    self.contentWidthConstraint.constant = MAX(required - available, 0);
}

@end

#pragma mark - BenchSecondaryButton

@implementation BenchSecondaryButton

+ (instancetype)buttonWithTitle:(NSString *)title {
    BenchSecondaryButton *button = [BenchSecondaryButton buttonWithType:UIButtonTypeSystem];
    // contentEdgeInsets 在 iOS 15 起废弃，改用 configuration 设置内边距
    UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
    config.title = title;
    config.contentInsets = NSDirectionalEdgeInsetsMake(8, 14, 8, 14);
    config.baseForegroundColor = [BenchTheme accent];
    button.configuration = config;

    button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    button.layer.cornerRadius = 8;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = [BenchTheme accent].CGColor;
    return button;
}

+ (instancetype)compactButtonWithTitle:(NSString *)title {
    BenchSecondaryButton *button = [BenchSecondaryButton buttonWithTitle:title];
    UIButtonConfiguration *config = button.configuration;
    config.contentInsets = NSDirectionalEdgeInsetsMake(3, 10, 3, 10);
    button.configuration = config;
    button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    button.layer.cornerRadius = 7;
    return button;
}

@end
