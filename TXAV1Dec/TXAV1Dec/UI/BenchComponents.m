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

    // 圆角与描边必须写在 configuration.background 上，不能用 layer.cornerRadius。
    // 用 configuration 的按钮在状态变化（按下、菜单弹出）时会带着 background
    // 重新渲染一遍，届时的圆角取的是 background.cornerRadius；layer 上的值
    // 会被盖掉，表现为按下瞬间变直角、松手后又变回圆角。
    // background 的 cornerRadius 内部就是连续曲率的圆角，与原来的
    // kCACornerCurveContinuous 一致；描边色也会跟随浅深色模式，
    // 而 layer.borderColor 存的是固定 CGColor，切换模式时不会变。
    config.background.backgroundColor = [UIColor clearColor];
    config.background.cornerRadius = 8;
    config.background.strokeColor = [BenchTheme accent];
    config.background.strokeWidth = 1.0;
    button.configuration = config;

    button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    return button;
}

+ (instancetype)compactButtonWithTitle:(NSString *)title {
    BenchSecondaryButton *button = [BenchSecondaryButton buttonWithTitle:title];
    UIButtonConfiguration *config = button.configuration;
    config.contentInsets = NSDirectionalEdgeInsetsMake(3, 10, 3, 10);
    // 圆角同样只改 background，与上面的原因相同
    config.background.cornerRadius = 7;
    button.configuration = config;
    button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    return button;
}

@end

#pragma mark - BenchMultiSelectItem

@implementation BenchMultiSelectItem

+ (instancetype)itemWithTitle:(NSString *)title detail:(NSString *)detail {
    BenchMultiSelectItem *item = [[BenchMultiSelectItem alloc] init];
    item.title = title;
    item.detail = detail;
    item.selected = NO;
    item.enabled = YES;
    return item;
}

@end

#pragma mark - BenchMultiSelectRow

/**
 * 浮层里的一行。
 *
 * 用 UIControl 而不是「视图 + 手势」：UIControl 自带高亮态与点击消抖，
 * 手指按下时立刻给出底色反馈。面板不再自动开合后，用户唯一的即时反馈
 * 就是这一行的视觉变化，所以按下态必须做。
 */
@interface BenchMultiSelectRow : UIControl

@property (nonatomic, strong) UILabel *checkLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *detailLabel;

- (void)configureWithItem:(BenchMultiSelectItem *)item;

@end

@implementation BenchMultiSelectRow {
    /// 方形勾选框的底框，选中时填色
    UIView *_box;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    // 用「方形底框 + 对勾」而不是单个字符：
    // 字符勾选在未选中时位置上什么都没有，用户看不出这里可以勾，
    // 也难以判断当前到底选中了几项。空方框把「可勾选」这件事显式画出来。
    _box = [[UIView alloc] init];
    _box.translatesAutoresizingMaskIntoConstraints = NO;
    _box.layer.cornerRadius = 5;
    _box.layer.borderWidth = 1.5;
    _box.userInteractionEnabled = NO;
    [_box.widthAnchor constraintEqualToConstant:22].active = YES;
    [_box.heightAnchor constraintEqualToConstant:22].active = YES;

    _checkLabel = [[UILabel alloc] init];
    _checkLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    _checkLabel.textAlignment = NSTextAlignmentCenter;
    _checkLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_box addSubview:_checkLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_checkLabel.centerXAnchor constraintEqualToAnchor:_box.centerXAnchor],
        [_checkLabel.centerYAnchor constraintEqualToAnchor:_box.centerYAnchor],
    ]];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    _titleLabel.textColor = [BenchTheme primaryText];
    _titleLabel.numberOfLines = 1;
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    // 名称吃掉剩余宽度，把时间戳推到右边；时间戳不参与拉伸
    [_titleLabel setContentHuggingPriority:UILayoutPriorityDefaultLow - 1
                                   forAxis:UILayoutConstraintAxisHorizontal];
    [_titleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                                 forAxis:UILayoutConstraintAxisHorizontal];

    _detailLabel = [[UILabel alloc] init];
    _detailLabel.font = [BenchTheme captionFont];
    _detailLabel.textColor = [BenchTheme secondaryText];
    _detailLabel.numberOfLines = 1;
    _detailLabel.textAlignment = NSTextAlignmentRight;
    [_detailLabel setContentHuggingPriority:UILayoutPriorityRequired
                                    forAxis:UILayoutConstraintAxisHorizontal];
    // 优先级高于名称（DefaultLow）所以正常情况不会被压扁，
    // 但不设成 required：不可用版本的错误文本可能很长，
    // 必争会导致与名称之间的约束冲突，界面上表现为布局告警与错位。
    [_detailLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh + 1
                                                  forAxis:UILayoutConstraintAxisHorizontal];

    // 名称与时间戳同一行：两行文字会把每行行高翻倍，选项一多就得滚动；
    // 时间戳是次要信息，放右端同一水平线上既能读到，又只占一份行高。
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[_box, _titleLabel, _detailLabel]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12;
    [row setCustomSpacing:8 afterView:_titleLabel];
    // 内部不接手势，点击统一交给外层 UIControl
    row.userInteractionEnabled = NO;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:row];

    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:self.topAnchor constant:6],
        [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-6],
        [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
        [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
    ]];

    return self;
}

- (void)configureWithItem:(BenchMultiSelectItem *)item {
    // 选中：主色填充 + 白勾；未选中：只留描边空框。
    // 两种状态的填充差异足够大，扫一眼就能数出选中了几项。
    UIColor *accent = [BenchTheme accent];
    _box.backgroundColor = item.selected ? accent : [UIColor clearColor];
    _box.layer.borderColor = (item.selected ? accent : [BenchTheme secondaryText]).CGColor;

    self.checkLabel.text = item.selected ? @"✓" : @"";
    self.checkLabel.textColor = [UIColor whiteColor];
    self.titleLabel.text = item.title;
    self.titleLabel.textColor = item.selected ? accent : [BenchTheme primaryText];
    self.detailLabel.text = item.detail;
    self.detailLabel.hidden = (item.detail.length == 0);

    // 不可用项压暗但仍留在列表里、也仍可点击：
    // 静默隐藏会让人以为构建漏了某个版本，实际是那个库有问题；
    // 若同时禁掉点击，用户点了没反应也说不清原因，所以让调用方
    // 收到回调后弹一条明确的失败说明。
    self.alpha = item.enabled ? 1.0 : 0.45;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.backgroundColor = highlighted
        ? [[BenchTheme accent] colorWithAlphaComponent:0.08]
        : [UIColor clearColor];
}

@end

#pragma mark - BenchMultiSelectPanel

@interface BenchMultiSelectPanel ()

@property (nonatomic, strong) UIView *container;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *rowsStack;
@property (nonatomic, strong) NSArray<BenchMultiSelectItem *> *items;
@property (nonatomic, strong) UIButton *extraActionButton;
@property (nonatomic, copy) void (^extraActionHandler)(void);

@end

@implementation BenchMultiSelectPanel

+ (instancetype)presentInView:(UIView *)hostView
                        title:(NSString *)title
                      message:(NSString *)message
                        items:(NSArray<BenchMultiSelectItem *> *)items {
    if (!hostView) return nil;

    BenchMultiSelectPanel *panel = [[BenchMultiSelectPanel alloc] initWithFrame:hostView.bounds];
    panel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    panel.titleLabel.text = title;
    panel.messageLabel.text = message;
    panel.messageLabel.hidden = (message.length == 0);

    [hostView addSubview:panel];
    [panel reloadWithItems:items];
    [panel animateIn];

    return panel;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    // 遮罩用 UIControl 承担「点空白关闭」，而不是加手势：
    // 手势会同时命中容器内部的行，导致点选项时面板被一起关掉。
    UIControl *dimView = [[UIControl alloc] initWithFrame:self.bounds];
    dimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    dimView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.35];
    [dimView addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:dimView];

    _container = [[UIView alloc] init];
    _container.translatesAutoresizingMaskIntoConstraints = NO;
    [BenchTheme applyCardStyleToView:_container];
    _container.backgroundColor = [BenchTheme cardBackground];
    [self addSubview:_container];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.font = [BenchTheme sectionFont];
    _titleLabel.textColor = [BenchTheme primaryText];
    _titleLabel.textAlignment = NSTextAlignmentCenter;

    _messageLabel = [[UILabel alloc] init];
    _messageLabel.font = [BenchTheme captionFont];
    _messageLabel.textColor = [BenchTheme secondaryText];
    _messageLabel.textAlignment = NSTextAlignmentCenter;
    _messageLabel.numberOfLines = 0;

    _rowsStack = [[UIStackView alloc] init];
    _rowsStack.axis = UILayoutConstraintAxisVertical;
    _rowsStack.spacing = 0;
    _rowsStack.translatesAutoresizingMaskIntoConstraints = NO;

    _scrollView = [[UIScrollView alloc] init];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.alwaysBounceVertical = NO;
    [_scrollView addSubview:_rowsStack];

    // 「全选」放进面板内部：面板不自动关闭，用户可以边看列表边决定
    // 全选还是只挑几个，这个操作天然属于面板。
    UIButton *selectAllButton = [BenchSecondaryButton compactButtonWithTitle:@"全选"];
    [selectAllButton addTarget:self
                        action:@selector(handleSelectAll)
              forControlEvents:UIControlEventTouchUpInside];
    [selectAllButton setContentHuggingPriority:UILayoutPriorityRequired
                                       forAxis:UILayoutConstraintAxisHorizontal];

    // 快捷动作默认隐藏，由 setExtraActionTitle:handler: 按需显示
    _extraActionButton = [BenchSecondaryButton compactButtonWithTitle:@""];
    _extraActionButton.hidden = YES;
    [_extraActionButton addTarget:self
                           action:@selector(handleExtraAction)
                 forControlEvents:UIControlEventTouchUpInside];
    [_extraActionButton setContentHuggingPriority:UILayoutPriorityRequired
                                          forAxis:UILayoutConstraintAxisHorizontal];

    UIButton *doneButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *doneConfig = [UIButtonConfiguration filledButtonConfiguration];
    doneConfig.title = @"完成";
    doneConfig.baseBackgroundColor = [BenchTheme accent];
    doneConfig.baseForegroundColor = [UIColor whiteColor];
    doneConfig.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    doneConfig.contentInsets = NSDirectionalEdgeInsetsMake(6, 16, 6, 16);
    doneButton.configuration = doneConfig;
    [doneButton addTarget:self action:@selector(dismiss) forControlEvents:UIControlEventTouchUpInside];
    [doneButton setContentHuggingPriority:UILayoutPriorityRequired
                                  forAxis:UILayoutConstraintAxisHorizontal];

    // 左侧放全选与快捷动作，中间弹性占位，右侧「完成」。
    // 弹性占位让「完成」始终贴在右下角，即使快捷动作不显示也不会跑位。
    UIView *footerSpacer = [[UIView alloc] init];
    [footerSpacer setContentHuggingPriority:UILayoutPriorityDefaultLow - 1
                                    forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *footer = [[UIStackView alloc] initWithArrangedSubviews:@[
        selectAllButton, _extraActionButton, footerSpacer, doneButton
    ]];
    footer.axis = UILayoutConstraintAxisHorizontal;
    footer.alignment = UIStackViewAlignmentCenter;
    footer.spacing = 10;

    UIStackView *root = [[UIStackView alloc] initWithArrangedSubviews:@[
        _titleLabel, _messageLabel, _scrollView, footer
    ]];
    root.axis = UILayoutConstraintAxisVertical;
    root.spacing = 12;
    root.alignment = UIStackViewAlignmentFill;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [_container addSubview:root];

    const CGFloat pad = 16;

    NSLayoutConstraint *centerY =
        [_container.centerYAnchor constraintEqualToAnchor:self.centerYAnchor];
    centerY.priority = UILayoutPriorityDefaultHigh;

    [NSLayoutConstraint activateConstraints:@[
        [root.topAnchor constraintEqualToAnchor:_container.topAnchor constant:pad],
        [root.leadingAnchor constraintEqualToAnchor:_container.leadingAnchor constant:pad],
        [root.trailingAnchor constraintEqualToAnchor:_container.trailingAnchor constant:-pad],
        [root.bottomAnchor constraintEqualToAnchor:_container.bottomAnchor constant:-pad],

        [_rowsStack.topAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.topAnchor],
        [_rowsStack.leadingAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.leadingAnchor],
        [_rowsStack.trailingAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.trailingAnchor],
        [_rowsStack.bottomAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.bottomAnchor],
        [_rowsStack.widthAnchor constraintEqualToAnchor:_scrollView.frameLayoutGuide.widthAnchor],

        [_container.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        // 用「不小于顶部安全距离」配合居中，而不是硬居中：
        // 内容少时垂直居中好看；内容多时贴住安全区边缘，
        // 不会被推到状态栏底下把标题压住（截图里标题被盖就是这个原因）。
        // 居中设为 high 而非 required：内容真的超高时让它让步，
        // 由上下安全区约束决定位置，不会报约束冲突。
        centerY,
        [_container.topAnchor constraintGreaterThanOrEqualToAnchor:self.safeAreaLayoutGuide.topAnchor
                                                          constant:12],
        [_container.bottomAnchor constraintLessThanOrEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor
                                                          constant:-12],
        [_container.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.leadingAnchor constant:16],
        [_container.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-16],
        [_container.widthAnchor constraintLessThanOrEqualToConstant:380],
    ]];

    // 宽度按「贴边减 32」自适应，再用 380 上限压住：
    // 手机上贴合屏幕，iPad 上不至于拉成一条细长条。
    NSLayoutConstraint *preferredWidth = [_container.widthAnchor constraintEqualToAnchor:self.widthAnchor
                                                                             constant:-32];
    preferredWidth.priority = UILayoutPriorityDefaultHigh;
    preferredWidth.active = YES;

    // 高度策略：贴合内容 + 上限封顶 + 最小高度兜底。
    //
    // 关键点是把「让面板撑满屏幕」那条约束删掉。之前有一条低优先级的
    // 「container 高度 == 屏幕高度 - 120」，本意是给高度一个确定值以避开
    // 布局告警，结果是内容只有两三行时面板仍被撑到接近全屏；容器一高，
    // 根 stack 就要填满容器，唯一能伸展的滚动视图被拉长，滚动视图又与
    // 行容器等高，多出来的高度只能分摊给各行，于是行被拉到相隔几百点。
    //
    // 现在：滚动视图高度优先贴合内容（700），这样内容少时面板紧凑；
    // 内容多时由容器上限（required）打破这条约束，剩余空间自然落到
    // 滚动视图上并进入滚动。再给滚动视图一个最小高度，避免极端情况下
    // 被标题和按钮挤成 0。
    NSLayoutConstraint *contentHeight =
        [_scrollView.heightAnchor constraintEqualToAnchor:_rowsStack.heightAnchor];
    contentHeight.priority = UILayoutPriorityDefaultHigh - 50;
    contentHeight.active = YES;

    [_scrollView.heightAnchor constraintGreaterThanOrEqualToConstant:120].active = YES;

    NSLayoutConstraint *maxHeight =
        [_container.heightAnchor constraintLessThanOrEqualToAnchor:self.heightAnchor
                                                          constant:-120];
    maxHeight.priority = UILayoutPriorityRequired;
    maxHeight.active = YES;

    return self;
}

- (void)reloadWithItems:(NSArray<BenchMultiSelectItem *> *)items {
    self.items = items;

    // 项数不变时（切换选中态是最常见的情况）只重新配置现有行，不重建视图：
    // 重建会丢高亮态、打断滚动惯性，还会让 iOS 重新做一轮布局，
    // 在常开面板里表现为每点一次就轻微抖一下。
    NSArray<UIView *> *existing = self.rowsStack.arrangedSubviews;
    if (items.count > 0 && existing.count == items.count) {
        BOOL allRows = YES;
        for (UIView *view in existing) {
            if (![view isKindOfClass:[BenchMultiSelectRow class]]) {
                allRows = NO;
                break;
            }
        }
        if (allRows) {
            for (NSInteger i = 0; i < (NSInteger)items.count; i++) {
                [(BenchMultiSelectRow *)existing[i] configureWithItem:items[i]];
            }
            return;
        }
    }

    NSMutableArray<UIView *> *newRows = [NSMutableArray array];

    if (items.count == 0) {
        UILabel *empty = [[UILabel alloc] init];
        empty.text = @"没有可选项";
        empty.font = [BenchTheme bodyFont];
        empty.textColor = [BenchTheme secondaryText];
        empty.textAlignment = NSTextAlignmentCenter;
        [empty.heightAnchor constraintEqualToConstant:80].active = YES;
        [newRows addObject:empty];
    } else {
        for (NSInteger i = 0; i < (NSInteger)items.count; i++) {
            BenchMultiSelectItem *item = items[i];
            BenchMultiSelectRow *row = [[BenchMultiSelectRow alloc] initWithFrame:CGRectZero];
            [row configureWithItem:item];
            // tag 存下标，回调只需要回传位置，面板不关心业务对象是什么
            row.tag = i;
            [row addTarget:self
                    action:@selector(handleRowTap:)
          forControlEvents:UIControlEventTouchUpInside];
            [newRows addObject:row];
        }
    }

    // 先插入新行再移除旧行：反过来的话会瞬间出现「零高度 → 恢复高度」跳变
    for (UIView *row in newRows) {
        [self.rowsStack addArrangedSubview:row];
    }
    for (UIView *row in existing) {
        [self.rowsStack removeArrangedSubview:row];
        [row removeFromSuperview];
    }
}

- (void)handleRowTap:(BenchMultiSelectRow *)row {
    // 只上报点击，既不改本地选中态也不关闭面板。
    // 选中态的唯一真值在调用方（selectedStreams / selectedDecoders）：
    // 面板若自己先改一遍，调用方 reload 时会出现两份状态互相覆盖。
    // 不可用项也照常上报，由调用方决定是提示还是忽略——
    // 面板不知道业务语义，替调用方过滤会让"点了没反应"无从解释。
    const NSInteger index = row.tag;
    if (index < 0 || index >= (NSInteger)self.items.count) return;

    // 回调会让调用方 reload 列表，也就是把这行本身从层级里摘掉。
    // 不在 touchesEnded 的派发栈内做这件事，推迟到下一次 runloop，
    // 事件派发完成后再重建，避免在行的手势处理过程中释放视图。
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (self.onToggleItem) self.onToggleItem(index);
    });
}

- (void)handleSelectAll {
    if (self.onSelectAll) self.onSelectAll();
}

- (void)setExtraActionTitle:(NSString *)title handler:(void (^)(void))handler {
    self.extraActionHandler = handler;
    self.extraActionButton.hidden = (title.length == 0 || handler == nil);
    if (title.length == 0) return;

    UIButtonConfiguration *config = self.extraActionButton.configuration;
    config.title = title;
    self.extraActionButton.configuration = config;
}

- (void)handleExtraAction {
    if (self.extraActionHandler) self.extraActionHandler();
}

- (void)animateIn {
    self.alpha = 0;
    self.container.transform = CGAffineTransformMakeScale(0.96, 0.96);
    [UIView animateWithDuration:0.18 animations:^{
        self.alpha = 1;
        self.container.transform = CGAffineTransformIdentity;
    }];
}

- (void)dismiss {
    if (self.onDismiss) self.onDismiss();
    [UIView animateWithDuration:0.15 animations:^{
        self.alpha = 0;
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];
}

@end

#pragma mark - BenchToastView

@implementation BenchToastView

/// 同屏只保留一条提示：新旧提示叠在一起既看不清，也会互相抢消失动画
static __weak BenchToastView *sCurrentToast = nil;

+ (void)showInView:(UIView *)hostView message:(NSString *)message {
    if (!hostView || message.length == 0) return;

    [sCurrentToast removeFromSuperview];

    BenchToastView *toast = [[BenchToastView alloc] initWithFrame:CGRectZero];
    toast.translatesAutoresizingMaskIntoConstraints = NO;
    toast.backgroundColor = [UIColor colorWithDynamicProvider:
        ^UIColor *(UITraitCollection *traits) {
            return traits.userInterfaceStyle == UIUserInterfaceStyleDark
                ? [UIColor colorWithWhite:0.24 alpha:0.96]
                : [UIColor colorWithWhite:0.16 alpha:0.92];
        }];
    toast.layer.cornerRadius = 10;
    toast.layer.cornerCurve = kCACornerCurveContinuous;
    toast.alpha = 0;
    // 不拦截触摸：提示浮在结果区上方，若吞掉触摸会让下面的按钮短暂失效
    toast.userInteractionEnabled = NO;

    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = message;
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    [toast addSubview:label];

    [hostView addSubview:toast];
    [NSLayoutConstraint activateConstraints:@[
        [toast.centerXAnchor constraintEqualToAnchor:hostView.centerXAnchor],
        // 贴底部安全区上方：导出按钮在页面中部偏下，提示离触发点不远，
        // 又不会被 home indicator 压住
        [toast.bottomAnchor constraintEqualToAnchor:hostView.safeAreaLayoutGuide.bottomAnchor
                                          constant:-24],
        [toast.leadingAnchor constraintGreaterThanOrEqualToAnchor:hostView.leadingAnchor
                                                        constant:24],
        [toast.trailingAnchor constraintLessThanOrEqualToAnchor:hostView.trailingAnchor
                                                      constant:-24],
        [label.topAnchor constraintEqualToAnchor:toast.topAnchor constant:10],
        [label.bottomAnchor constraintEqualToAnchor:toast.bottomAnchor constant:-10],
        [label.leadingAnchor constraintEqualToAnchor:toast.leadingAnchor constant:16],
        [label.trailingAnchor constraintEqualToAnchor:toast.trailingAnchor constant:-16],
    ]];

    sCurrentToast = toast;

    [UIView animateWithDuration:0.18 animations:^{
        toast.alpha = 1;
    }];

    // 1.6 秒足够读完一行提示；提前消失会让用户来不及确认，
    // 停留过久又会挡住下方数据。
    __weak BenchToastView *weakToast = toast;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        BenchToastView *strongToast = weakToast;
        if (!strongToast) return;
        [UIView animateWithDuration:0.22 animations:^{
            strongToast.alpha = 0;
        } completion:^(BOOL finished) {
            [strongToast removeFromSuperview];
        }];
    });
}

@end
