//
//  ViewController.mm
//  TXAV1Dec
//

#import "ViewController.h"
#import "BenchEngine.h"
#import "BenchSystemMetrics.h"
#import "BenchTheme.h"
#import "BenchComponents.h"

#pragma mark - 码流选择行

/**
 * 「标题 + 当前选择 + 上下箭头」的一行，点击弹出多选列表。
 *
 * 码流是枚举而非自由输入，且要支持多选批量测试，所以用按钮式行
 * 代替输入框：点击区域覆盖整行，命中更容易。
 */
@interface BenchStreamPickerRow : UIView

@property (nonatomic, readonly) UIButton *button;

- (instancetype)initWithTitle:(NSString *)title;

- (void)updateWithSelectedNames:(NSArray<NSString *> *)names;

@end

@implementation BenchStreamPickerRow {
    UILabel *_titleLabel;
    UILabel *_valueLabel;
}

- (instancetype)initWithTitle:(NSString *)title {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = title;
    _titleLabel.font = [BenchTheme captionFont];
    _titleLabel.textColor = [BenchTheme secondaryText];

    _valueLabel = [[UILabel alloc] init];
    _valueLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    _valueLabel.textColor = [BenchTheme primaryText];
    _valueLabel.numberOfLines = 1;
    _valueLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [_valueLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow
                                                forAxis:UILayoutConstraintAxisHorizontal];

    UIImageView *chevron = [[UIImageView alloc] initWithImage:
                            [UIImage systemImageNamed:@"chevron.up.chevron.down"]];
    chevron.tintColor = [BenchTheme secondaryText];
    chevron.contentMode = UIViewContentModeScaleAspectFit;
    [chevron.widthAnchor constraintEqualToConstant:13].active = YES;
    [chevron.heightAnchor constraintEqualToConstant:13].active = YES;
    [chevron setContentHuggingPriority:UILayoutPriorityRequired
                               forAxis:UILayoutConstraintAxisHorizontal];

    UIView *spacer = [[UIView alloc] init];
    [spacer setContentHuggingPriority:UILayoutPriorityDefaultLow - 1
                              forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[
        _valueLabel, spacer, chevron
    ]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 6;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, row]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6;
    stack.userInteractionEnabled = NO;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:stack];

    _button = [UIButton buttonWithType:UIButtonTypeSystem];
    _button.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_button];

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_button.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_button.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_button.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_button.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    return self;
}

- (void)updateWithSelectedNames:(NSArray<NSString *> *)names {
    if (names.count == 0) {
        _valueLabel.text = @"未选择码流";
        _valueLabel.textColor = [BenchTheme secondaryText];
    } else if (names.count == 1) {
        _valueLabel.text = names.firstObject;
        _valueLabel.textColor = [BenchTheme primaryText];
    } else {
        // 多选时只显示首个文件名加数量，避免长列表撑破一行
        _valueLabel.text = [NSString stringWithFormat:@"%@ 等 %lu 个",
                            names.firstObject, (unsigned long)names.count];
        _valueLabel.textColor = [BenchTheme primaryText];
    }
}

@end

#pragma mark - 单码流结果

/** 一个码流的完整测试结果，多码流批量测试后用于横向对比 */
@interface BenchStreamResult : NSObject

@property (nonatomic, strong) BenchStream *stream;
@property (nonatomic, strong) BenchRunConfig *config;
@property (nonatomic, strong) NSArray<BenchRoundMetrics *> *rounds;
@property (nonatomic, strong) BenchSummary *summary;

- (NSString *)displayName;

@end

@implementation BenchStreamResult

- (NSString *)displayName {
    NSString *name = self.stream.name ?: self.config.streamName ?: @"未知码流";
    // 对比表列头空间有限，去掉扩展名让列宽更可控
    return name.stringByDeletingPathExtension.length > 0
        ? name.stringByDeletingPathExtension : name;
}

@end

#pragma mark - 控制器

@interface ViewController () <UITextFieldDelegate>

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *rootStack;

// 设备信息
@property (nonatomic, strong) UILabel *deviceNameLabel;
@property (nonatomic, strong) UILabel *deviceDetailLabel;

// 参数（码流选择已并入此卡片，不再单独占一张卡）
@property (nonatomic, strong) BenchCardView *configCard;
@property (nonatomic, strong) BenchDisclosureRow *targetRow;
@property (nonatomic, strong) UIStackView *targetDetailStack;
@property (nonatomic, assign) BOOL targetExpanded;
@property (nonatomic, strong) BenchStreamPickerRow *streamPickerRow;
@property (nonatomic, strong) BenchCompactField *framesField;
@property (nonatomic, strong) BenchCompactField *roundsField;
@property (nonatomic, strong) BenchCompactField *warmupField;
@property (nonatomic, strong) BenchCompactField *skipField;
@property (nonatomic, strong) UITextField *decoderField;
@property (nonatomic, strong) BenchSegmentRow *threadSegment;
@property (nonatomic, strong) BenchSegmentRow *affinitySegment;

// 操作
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *stageLabel;

// 结果
@property (nonatomic, strong) BenchCardView *resultCard;
@property (nonatomic, strong) UILabel *resultStreamLabel;
@property (nonatomic, strong) BenchMetricTile *fpsTile;
@property (nonatomic, strong) BenchMetricTile *mspfTile;
@property (nonatomic, strong) BenchMetricTile *efficiencyTile;
@property (nonatomic, strong) BenchMetricTile *cpuTile;
@property (nonatomic, strong) BenchMetricTile *memoryTile;
@property (nonatomic, strong) BenchMetricTile *p95Tile;
@property (nonatomic, strong) UIStackView *singleResultStack;
@property (nonatomic, strong) BenchComparisonView *comparisonView;
@property (nonatomic, strong) UILabel *stabilityLabel;
@property (nonatomic, strong) UILabel *detailLabel;
@property (nonatomic, strong) UIButton *reportCopyButton;
@property (nonatomic, copy) NSString *reportText;

// 数据
@property (nonatomic, strong) NSArray<BenchStream *> *streams;
@property (nonatomic, strong) NSMutableArray<BenchStream *> *selectedStreams;
@property (nonatomic, strong) BenchEngine *engine;

// 批量测试状态
@property (nonatomic, strong) NSMutableArray<BenchStreamResult *> *batchResults;
@property (nonatomic, strong) NSMutableArray<BenchStream *> *pendingStreams;
@property (nonatomic, strong) NSMutableArray<NSString *> *failedStreamNames;
@property (nonatomic, assign) NSUInteger batchTotal;
@property (nonatomic, assign) BOOL batchCancelled;
@property (nonatomic, strong) BenchRunConfig *lastConfig;

@end

@implementation ViewController

#pragma mark - 生命周期

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [BenchTheme background];
    self.title = @"解码性能测试";

    self.engine = [[BenchEngine alloc] init];
    self.streams = @[];
    self.selectedStreams = [NSMutableArray array];
    self.batchResults = [NSMutableArray array];
    self.pendingStreams = [NSMutableArray array];
    self.failedStreamNames = [NSMutableArray array];

    [self buildScrollHierarchy];
    [self buildDeviceHeader];
    [self buildConfigCard];
    [self buildActionArea];
    [self buildResultCard];

    [self applyDefaultConfigValues];
    [self setupNavigationBar];
    [self reloadStreams];

    if ([[NSProcessInfo processInfo].arguments containsObject:@"--selftest"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self runHeadlessSelfTest];
        });
    }

    if ([[NSProcessInfo processInfo].arguments containsObject:@"--ui-shot"]) {
        // 截图时机交给自测收尾统一触发：自测要跑几十秒，
        // 用固定延时截图很可能拍到结果还没渲染出来的中间态。
        BOOL alsoRun = [[NSProcessInfo processInfo].arguments containsObject:@"--selftest"];
        BOOL expand = [[NSProcessInfo processInfo].arguments containsObject:@"--expand-target"];
        if (expand) {
            // 展开态用于核对折叠区内容：收起态只能看到摘要，
            // 选择器和输入框是否真的可交互必须展开后才能验证。
            [self applyTargetExpanded:YES];
        }
        if (!alsoRun) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [self capturePageSnapshotNamed:expand ? @"shot_expanded" : @"shot_top"];
            });
        }
    }

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                         action:@selector(dismissKeyboard)];
    tap.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tap];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    // 基线必须在「界面已完成一次真实布局与渲染」之后取：
    // viewDidLoad 时只是建好了视图对象，CoreAnimation 的渲染缓冲、
    // 字体位图缓存、图层后备存储都还没分配，此时取的基线会偏低，
    // 那部分增长之后会被误算进解码器净内存。
    // 同时它又必须早于任何解码，所以放在首次显示时，且只记录一次。
    [BenchSystemMetrics captureIdleBaselineIfNeeded];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - 构建骨架

- (void)buildScrollHierarchy {
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:self.scrollView];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.rootStack = [[UIStackView alloc] init];
    self.rootStack.axis = UILayoutConstraintAxisVertical;
    self.rootStack.spacing = 10;
    self.rootStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.rootStack];

    const CGFloat pad = [BenchTheme screenPadding];
    [NSLayoutConstraint activateConstraints:@[
        [self.rootStack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor
                                                 constant:10],
        [self.rootStack.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor
                                                     constant:pad],
        [self.rootStack.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor
                                                      constant:-pad],
        [self.rootStack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor
                                                    constant:-pad],
        [self.rootStack.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor
                                                   constant:-pad * 2],
    ]];
}

- (void)setupNavigationBar {
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithTransparentBackground];
    appearance.backgroundColor = [BenchTheme background];
    appearance.shadowColor = [UIColor clearColor];
    appearance.titleTextAttributes = @{
        NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold],
        NSForegroundColorAttributeName: [BenchTheme primaryText],
    };
    self.navigationController.navigationBar.standardAppearance = appearance;
    self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
    self.navigationController.navigationBar.tintColor = [BenchTheme accent];
}

#pragma mark - 设备信息

- (void)buildDeviceHeader {
    self.deviceNameLabel = [[UILabel alloc] init];
    self.deviceNameLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.deviceNameLabel.textColor = [BenchTheme primaryText];
    self.deviceNameLabel.adjustsFontSizeToFitWidth = YES;
    self.deviceNameLabel.minimumScaleFactor = 0.8;

    self.deviceDetailLabel = [[UILabel alloc] init];
    self.deviceDetailLabel.font = [BenchTheme captionFont];
    self.deviceDetailLabel.textColor = [BenchTheme secondaryText];
    self.deviceDetailLabel.numberOfLines = 1;
    self.deviceDetailLabel.adjustsFontSizeToFitWidth = YES;
    self.deviceDetailLabel.minimumScaleFactor = 0.7;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.deviceNameLabel, self.deviceDetailLabel
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 3;
    [self.rootStack addArrangedSubview:stack];

    [self updateDeviceInfo];
}

- (void)updateDeviceInfo {
    self.deviceNameLabel.text = [NSString stringWithFormat:@"%@ · %@",
                                 [BenchSystemMetrics deviceName],
                                 [BenchSystemMetrics machineIdentifier]];

    // 大小核拓扑写进页头：CPU 按核心数折算时，需要知道分母是几个核
    self.deviceDetailLabel.text = [NSString stringWithFormat:
                                   @"%@ · 内存 %.0f GB · %@",
                                   [BenchSystemMetrics coreTopologyDescription],
                                   (double)[NSProcessInfo processInfo].physicalMemory / (1024.0 * 1024.0 * 1024.0),
                                   [BenchSystemMetrics thermalStateDescription]];
}

#pragma mark - 参数配置（含码流选择）

- (void)buildConfigCard {
    // 码流选择并入本卡片：原来单独一张卡片要多占一圈内边距和一条标题行
    BenchCardView *card = [[BenchCardView alloc] initWithTitle:@"测试配置"];
    self.configCard = card;

    // 码流与解码器是「每轮只改一次、但必须能一眼看到当前值」的配置，
    // 收进一个折叠区：默认收起占一行，展开后才显示选择器与输入框。
    self.targetRow = [[BenchDisclosureRow alloc] initWithTitle:@"测试对象"];
    [self.targetRow.button addTarget:self
                              action:@selector(targetRowTapped)
                    forControlEvents:UIControlEventTouchUpInside];

    self.streamPickerRow = [[BenchStreamPickerRow alloc] initWithTitle:@"测试码流（可多选）"];
    [self.streamPickerRow.button addTarget:self
                                    action:@selector(streamPickerTapped)
                          forControlEvents:UIControlEventTouchUpInside];

    // 被测解码器名：横向对比必须知道这组数字属于哪个版本。
    // 说明文字不能省：占位符在填入内容后消失，之后就看不出这栏是什么了。
    UILabel *decoderCaption = [[UILabel alloc] init];
    decoderCaption.text = @"被测解码器版本";
    decoderCaption.font = [BenchTheme captionFont];
    decoderCaption.textColor = [BenchTheme secondaryText];

    self.decoderField = [[UITextField alloc] init];
    self.decoderField.placeholder = @"如 av1d 1.4.1";
    self.decoderField.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    self.decoderField.textColor = [BenchTheme primaryText];
    self.decoderField.backgroundColor = [BenchTheme accentSoft];
    self.decoderField.layer.cornerRadius = 8;
    self.decoderField.layer.cornerCurve = kCACornerCurveContinuous;
    self.decoderField.returnKeyType = UIReturnKeyDone;
    self.decoderField.delegate = self;
    UIView *decoderPad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 34)];
    self.decoderField.leftView = decoderPad;
    self.decoderField.leftViewMode = UITextFieldViewModeAlways;
    [self.decoderField.heightAnchor constraintEqualToConstant:36].active = YES;

    UIStackView *targetDetail = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.streamPickerRow, decoderCaption, self.decoderField
    ]];
    targetDetail.axis = UILayoutConstraintAxisVertical;
    targetDetail.spacing = 8;
    // 收起时整体隐藏，展开时才占位
    targetDetail.hidden = YES;
    self.targetDetailStack = targetDetail;

    UIStackView *targetBlock = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.targetRow, targetDetail
    ]];
    targetBlock.axis = UILayoutConstraintAxisVertical;
    targetBlock.spacing = 10;

    self.framesField = [[BenchCompactField alloc] initWithCaption:@"每轮帧数"
                                                      unitSuffix:nil
                                                        keyboard:UIKeyboardTypeNumberPad];
    self.framesField.textField.placeholder = @"0=全部";
    self.roundsField = [[BenchCompactField alloc] initWithCaption:@"测量轮次"
                                                      unitSuffix:nil
                                                        keyboard:UIKeyboardTypeNumberPad];
    self.warmupField = [[BenchCompactField alloc] initWithCaption:@"预热轮次"
                                                      unitSuffix:nil
                                                        keyboard:UIKeyboardTypeNumberPad];
    self.skipField = [[BenchCompactField alloc] initWithCaption:@"跳过包数"
                                                    unitSuffix:nil
                                                      keyboard:UIKeyboardTypeNumberPad];

    UIStackView *numbersRow = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.framesField, self.roundsField, self.warmupField, self.skipField
    ]];
    numbersRow.axis = UILayoutConstraintAxisHorizontal;
    numbersRow.distribution = UIStackViewDistributionFillEqually;
    numbersRow.alignment = UIStackViewAlignmentTop;
    numbersRow.spacing = 8;

    self.threadSegment = [[BenchSegmentRow alloc] initWithTitle:@"解码线程"
                                                          items:@[@"自动", @"1", @"2", @"4", @"8"]];

    // 核调度只保留三项：L2 亲和按 task 分组，全 App 只有一个 tag 时等于没有约束，
    // 实测无差异，留着只会让人以为它有用。
    self.affinitySegment = [[BenchSegmentRow alloc] initWithTitle:@"核调度偏好"
                                                            items:@[@"不干预", @"性能核", @"能效核"]];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        targetBlock, numbersRow, self.threadSegment, self.affinitySegment
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card.contentView addSubview:stack];
    [self pinEdgesOfView:stack toView:card.contentView];

    for (BenchCompactField *field in @[self.framesField, self.roundsField,
                                       self.warmupField, self.skipField]) {
        field.textField.delegate = self;
    }

    [self.rootStack addArrangedSubview:card];
}

- (void)applyDefaultConfigValues {
    BenchRunConfig *defaults = [[BenchRunConfig alloc] init];
    self.framesField.textField.text = [NSString stringWithFormat:@"%lu",
                                       (unsigned long)defaults.limitFrames];
    self.roundsField.textField.text = [NSString stringWithFormat:@"%lu",
                                       (unsigned long)defaults.rounds];
    self.warmupField.textField.text = [NSString stringWithFormat:@"%lu",
                                       (unsigned long)defaults.warmupRounds];
    self.skipField.textField.text = @"0";
}

#pragma mark - 码流选择

- (void)reloadStreams {
    const NSUInteger copied = [BenchStreamLibrary syncBundledStreams];
    if (copied > 0) {
        NSLog(@"[Bench] 已同步 %lu 个内置码流", (unsigned long)copied);
    }

    self.streams = [BenchStreamLibrary availableStreams];

    // 保留仍然存在的选择，丢弃已被删除的文件
    NSMutableArray<BenchStream *> *kept = [NSMutableArray array];
    for (BenchStream *old in self.selectedStreams) {
        for (BenchStream *stream in self.streams) {
            if ([stream.path isEqualToString:old.path]) {
                [kept addObject:stream];
                break;
            }
        }
    }
    // 首次进入且没有任何选择时，默认选中第一个，省去一次点击
    if (kept.count == 0 && self.streams.count > 0) {
        [kept addObject:self.streams.firstObject];
    }
    self.selectedStreams = kept;

    [self refreshStreamPickerDisplay];
    [self updateStartButtonState];
}

- (void)refreshStreamPickerDisplay {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (BenchStream *stream in self.selectedStreams) {
        [names addObject:stream.name];
    }
    [self.streamPickerRow updateWithSelectedNames:names];
    [self refreshTargetSummary];
}

/**
 * 折叠区的摘要：收起时它是唯一可见信息，必须能独立说明「在测什么」。
 *
 * 内容按重要性拼：解码器版本 → 码流数量 → 选中文件名。
 * 解码器名没填时明确显示「未标注」，避免看起来像漏了。
 */
- (void)refreshTargetSummary {
    NSString *decoder = self.decoderField.text.length > 0
        ? self.decoderField.text
        : @"解码器未标注";

    NSString *streamPart;
    if (self.selectedStreams.count == 0) {
        streamPart = @"未选码流";
    } else if (self.selectedStreams.count == 1) {
        streamPart = self.selectedStreams.firstObject.name;
    } else {
        streamPart = [NSString stringWithFormat:@"%lu 个码流",
                      (unsigned long)self.selectedStreams.count];
    }

    [self.targetRow setSummary:[NSString stringWithFormat:@"%@ · %@", decoder, streamPart]];
}

- (void)targetRowTapped {
    [self dismissKeyboard];
    [self applyTargetExpanded:!self.targetExpanded];
}

/**
 * 展开/收起测试对象区。
 *
 * 方法名不能叫 setTargetExpanded:——那正是 targetExpanded 属性的 setter，
 * 方法体内再写 self.targetExpanded = expanded 就会调回自己，形成无限递归，
 * 几毫秒内栈溢出（实测表现为 signal 11）。这里用明确的动作名避开冲突。
 */
- (void)applyTargetExpanded:(BOOL)expanded {
    self.targetExpanded = expanded;
    [self.targetRow setExpanded:expanded animated:YES];

    // 用 arrangedSubviews 的 hidden 折叠：设 hidden 后 UIStackView 会自动收回高度，
    // 比改约束简单，也不会残留空隙。不用 UIView 动画包住，因为该方法可能在
    // 界面首次布局之前被调用（启动参数路径），此时动画事务会持有未布局视图。
    self.targetDetailStack.hidden = !expanded;
    [self.targetDetailStack.superview setNeedsLayout];
}

- (void)streamPickerTapped {
    [self dismissKeyboard];
    if (self.engine.isRunning) return;

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"选择测试码流"
                                                                  message:@"可多选，批量测试会依次跑完每个码流"
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    if (self.streams.count == 0) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"未找到码流文件"
                                                  style:UIAlertActionStyleCancel
                                                handler:nil]];
    }

    // 每个码流一个可切换的动作，勾选态用前缀符号表达，
    // 比自建多选列表更省代码，也天然支持码流数量变化。
    for (BenchStream *stream in self.streams) {
        const BOOL selected = [self.selectedStreams containsObject:stream];
        NSString *title = [NSString stringWithFormat:@"%@ %@  ·  %@",
                           selected ? @"✓" : @"　",
                           stream.name,
                           stream.sizeDescription];
        __weak typeof(self) weakSelf = self;
        [sheet addAction:[UIAlertAction actionWithTitle:title
                                                 style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction *action) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [self toggleStream:stream];
        }]];
    }

    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"全选"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.selectedStreams = [self.streams mutableCopy];
        [self refreshStreamPickerDisplay];
        [self updateStartButtonState];
    }]];

    [sheet addAction:[UIAlertAction actionWithTitle:@"完成"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    // iPad 上 action sheet 必须有锚点，否则会崩
    if (sheet.popoverPresentationController) {
        sheet.popoverPresentationController.sourceView = self.streamPickerRow;
        sheet.popoverPresentationController.sourceRect = self.streamPickerRow.bounds;
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)toggleStream:(BenchStream *)stream {
    NSUInteger index = NSNotFound;
    for (NSUInteger i = 0; i < self.selectedStreams.count; i++) {
        if ([self.selectedStreams[i].path isEqualToString:stream.path]) {
            index = i;
            break;
        }
    }
    if (index == NSNotFound) {
        [self.selectedStreams addObject:stream];
    } else {
        [self.selectedStreams removeObjectAtIndex:index];
    }
    [self refreshStreamPickerDisplay];
    [self updateStartButtonState];

    // 选择变化后重新弹出，让用户能连续勾选多个而不必反复点开
    if (self.presentedViewController) {
        [self dismissViewControllerAnimated:NO completion:^{
            [self streamPickerTapped];
        }];
    }
}

- (void)refreshStreamsTapped {
    [self reloadStreams];
}

#pragma mark - 操作区

- (void)buildActionArea {
    self.startButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
    config.title = @"开始测试";
    config.baseBackgroundColor = [BenchTheme accent];
    config.baseForegroundColor = [UIColor whiteColor];
    config.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    config.contentInsets = NSDirectionalEdgeInsetsMake(12, 20, 12, 20);
    self.startButton.configuration = config;
    [self.startButton addTarget:self
                         action:@selector(startButtonTapped)
               forControlEvents:UIControlEventTouchUpInside];
    [self.startButton.heightAnchor constraintEqualToConstant:46].active = YES;

    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.progressTintColor = [BenchTheme accent];
    self.progressView.trackTintColor = [BenchTheme accentSoft];
    self.progressView.hidden = YES;

    self.stageLabel = [[UILabel alloc] init];
    self.stageLabel.font = [BenchTheme captionFont];
    self.stageLabel.textColor = [BenchTheme secondaryText];
    self.stageLabel.textAlignment = NSTextAlignmentCenter;
    self.stageLabel.text = @"";
    self.stageLabel.hidden = YES;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.startButton, self.progressView, self.stageLabel
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    [self.rootStack addArrangedSubview:stack];
}

- (void)startButtonTapped {
    [self dismissKeyboard];

    if (self.engine.isRunning) {
        self.batchCancelled = YES;
        [self.engine cancel];
        self.startButton.enabled = NO;
        self.stageLabel.text = @"正在停止…";
        return;
    }

    if (self.selectedStreams.count == 0) {
        [self showAlertWithTitle:@"没有选择码流"
                         message:@"请点开「测试码流」选择至少一个码流。"];
        return;
    }

    // 每次开跑前清空上一轮，避免新旧结果混在一起
    [self.batchResults removeAllObjects];
    [self.failedStreamNames removeAllObjects];
    self.reportText = nil;
    self.reportCopyButton.enabled = NO;
    self.resultCard.hidden = YES;
    self.batchCancelled = NO;
    self.batchTotal = self.selectedStreams.count;
    self.pendingStreams = [self.selectedStreams mutableCopy];

    [self setRunningUI:YES];
    [self runNextStreamInBatch];
}

/// 取出待测队列里的下一个码流开跑；队列空则收尾
- (void)runNextStreamInBatch {
    if (self.batchCancelled || self.pendingStreams.count == 0) {
        [self finishBatch];
        return;
    }

    BenchStream *stream = self.pendingStreams.firstObject;
    [self.pendingStreams removeObjectAtIndex:0];

    const NSUInteger overallIndex = self.batchTotal - self.pendingStreams.count;
    NSString *prefix = self.batchTotal > 1
        ? [NSString stringWithFormat:@"[%lu/%lu] ",
           (unsigned long)overallIndex, (unsigned long)self.batchTotal]
        : @"";

    BenchRunConfig *config = [self buildConfigForStream:stream];
    self.lastConfig = config;

    __weak typeof(self) weakSelf = self;
    [self.engine startWithConfig:config
                       onProgress:^(NSString *stage, double fraction) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.stageLabel.text = [NSString stringWithFormat:@"%@%@", prefix, stage];
        // 进度按「已完成码流数 + 当前码流进度」折算，批量时才是真实总进度
        const double overall = (double)(overallIndex - 1) + fraction;
        [self.progressView setProgress:(float)(overall / (double)self.batchTotal)
                              animated:YES];
    }
                     onCompletion:^(NSArray<BenchRoundMetrics *> *rounds, NSString *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        if (error) {
            // 单个码流失败不该中断整批，记录后继续下一个
            [self.failedStreamNames addObject:[NSString stringWithFormat:@"%@: %@",
                                               stream.name, error]];
        } else if (rounds.count > 0) {
            BenchStreamResult *result = [[BenchStreamResult alloc] init];
            result.stream = stream;
            result.config = config;
            result.rounds = rounds;
            result.summary = [BenchSummary summaryWithRounds:rounds];
            [self.batchResults addObject:result];
        }

        [self runNextStreamInBatch];
    }];
}

- (BenchRunConfig *)buildConfigForStream:(BenchStream *)stream {
    BenchRunConfig *config = [[BenchRunConfig alloc] init];
    config.streamPath = stream.path;
    config.streamName = stream.name;
    config.limitFrames = (NSUInteger)[self.framesField integerValueWithFallback:200];
    config.rounds = (NSUInteger)[self.roundsField integerValueWithFallback:3];
    config.warmupRounds = (NSUInteger)[self.warmupField integerValueWithFallback:1];
    config.skipFrames = (NSUInteger)MAX([self.skipField integerValueWithFallback:0], 0);
    config.threads = [self threadCountFromSegment];
    config.schedulePolicy = [self schedulePolicyFromSegment];
    config.decoderName = self.decoderField.text.length > 0 ? self.decoderField.text : nil;

    // 输入 0 表示跑满整个码流
    if (self.framesField.textField.text.integerValue == 0) {
        config.limitFrames = 0;
    }
    return config;
}

- (NSInteger)threadCountFromSegment {
    NSInteger index = self.threadSegment.segmentedControl.selectedSegmentIndex;
    NSArray<NSNumber *> *mapping = @[@0, @1, @2, @4, @8];
    if (index < 0 || index >= (NSInteger)mapping.count) return 0;
    return mapping[index].integerValue;
}

- (BenchSchedulePolicy)schedulePolicyFromSegment {
    // 分段控件只有三项：不干预 / 性能核 / 能效核
    switch (self.affinitySegment.segmentedControl.selectedSegmentIndex) {
        case 1: return BenchSchedulePolicyPerformance;
        case 2: return BenchSchedulePolicyEfficiency;
        default: return BenchSchedulePolicyDefault;
    }
}

- (void)finishBatch {
    [self setRunningUI:NO];

    if (self.batchResults.count == 0) {
        self.stageLabel.hidden = NO;
        if (self.failedStreamNames.count > 0) {
            self.stageLabel.text = @"测试失败";
            [self showAlertWithTitle:@"测试失败"
                             message:[self.failedStreamNames componentsJoinedByString:@"\n"]];
        } else {
            self.stageLabel.text = self.batchCancelled ? @"已取消" : @"没有产生有效结果";
        }
        return;
    }

    [self presentBatchResults];
    [self reportHapticFeedback];
}

- (void)setRunningUI:(BOOL)running {
    self.startButton.enabled = YES;
    UIButtonConfiguration *config = self.startButton.configuration;
    config.title = running ? @"停止测试" : @"开始测试";
    config.baseBackgroundColor = running ? [BenchTheme danger] : [BenchTheme accent];
    self.startButton.configuration = config;

    self.progressView.hidden = !running;
    self.stageLabel.hidden = !running;
    if (running) {
        [self.progressView setProgress:0 animated:NO];
        self.stageLabel.text = @"准备中…";
    }

    for (BenchCompactField *field in @[self.framesField, self.roundsField,
                                       self.warmupField, self.skipField]) {
        field.textField.enabled = !running;
    }
    self.threadSegment.segmentedControl.enabled = !running;
    self.affinitySegment.segmentedControl.enabled = !running;
    self.decoderField.enabled = !running;
    self.streamPickerRow.button.enabled = !running;
    self.reportCopyButton.enabled = !running && self.reportText.length > 0;
}

- (void)updateStartButtonState {
    if (self.engine.isRunning) return;
    const BOOL hasStream = self.selectedStreams.count > 0;
    self.startButton.enabled = hasStream;
    UIButtonConfiguration *config = self.startButton.configuration;
    config.baseBackgroundColor = hasStream ? [BenchTheme accent] : [UIColor tertiaryLabelColor];
    self.startButton.configuration = config;
}

#pragma mark - 结果展示

- (void)buildResultCard {
    BenchCardView *card = [[BenchCardView alloc] initWithTitle:nil];
    self.resultCard = card;
    card.hidden = YES;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"测试结果";
    titleLabel.font = [BenchTheme sectionFont];
    titleLabel.textColor = [BenchTheme secondaryText];

    self.reportCopyButton = [BenchSecondaryButton compactButtonWithTitle:@"复制报告"];
    [self.reportCopyButton addTarget:self
                              action:@selector(copyReportTapped)
                    forControlEvents:UIControlEventTouchUpInside];
    [self.reportCopyButton setContentHuggingPriority:UILayoutPriorityRequired
                                            forAxis:UILayoutConstraintAxisHorizontal];
    self.reportCopyButton.enabled = NO;

    UIStackView *headerRow = [[UIStackView alloc] initWithArrangedSubviews:@[
        titleLabel, [UIView new], self.reportCopyButton
    ]];
    headerRow.axis = UILayoutConstraintAxisHorizontal;
    headerRow.alignment = UIStackViewAlignmentCenter;
    headerRow.spacing = 8;

    // 当前码流名：批量测试时需要知道下面这组数字属于哪个码流
    self.resultStreamLabel = [[UILabel alloc] init];
    self.resultStreamLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.resultStreamLabel.textColor = [BenchTheme primaryText];
    self.resultStreamLabel.numberOfLines = 1;
    self.resultStreamLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;

    const CGFloat tileFont = 20.0;
    // 六个格子按「用户最关心」排序：帧率、单帧耗时、每帧 CPU 成本、
    // CPU 占用、解码器净内存、P95。前两项判断快不快，后四项判断贵不贵、稳不稳。
    self.fpsTile = [[BenchMetricTile alloc] initWithCaption:@"解码帧率" valueFontSize:tileFont];
    self.mspfTile = [[BenchMetricTile alloc] initWithCaption:@"单帧耗时" valueFontSize:tileFont];
    self.efficiencyTile = [[BenchMetricTile alloc] initWithCaption:@"每帧 CPU 成本" valueFontSize:tileFont];
    self.cpuTile = [[BenchMetricTile alloc] initWithCaption:@"CPU 占用" valueFontSize:tileFont];
    self.memoryTile = [[BenchMetricTile alloc] initWithCaption:@"解码器净内存" valueFontSize:tileFont];
    self.p95Tile = [[BenchMetricTile alloc] initWithCaption:@"P95 单帧" valueFontSize:tileFont];

    [self.efficiencyTile setFootnote:@"越低越好"];
    [self.memoryTile setFootnote:@"峰值 - 基线"];

    UIStackView *row1 = [self metricRowWithViews:@[self.fpsTile, self.mspfTile, self.efficiencyTile]];
    UIStackView *row2 = [self metricRowWithViews:@[self.cpuTile, self.memoryTile, self.p95Tile]];

    self.stabilityLabel = [[UILabel alloc] init];
    self.stabilityLabel.font = [BenchTheme captionFont];
    self.stabilityLabel.textColor = [BenchTheme secondaryText];
    self.stabilityLabel.numberOfLines = 0;

    self.detailLabel = [[UILabel alloc] init];
    self.detailLabel.font = [BenchTheme monoFontOfSize:10];
    self.detailLabel.textColor = [BenchTheme secondaryText];
    self.detailLabel.numberOfLines = 0;

    self.singleResultStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.resultStreamLabel, row1, row2, self.stabilityLabel, self.detailLabel
    ]];
    self.singleResultStack.axis = UILayoutConstraintAxisVertical;
    self.singleResultStack.spacing = 10;

    self.comparisonView = [[BenchComparisonView alloc] initWithFrame:CGRectZero];
    self.comparisonView.hidden = YES;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        headerRow, self.singleResultStack, self.comparisonView
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card.contentView addSubview:stack];
    [self pinEdgesOfView:stack toView:card.contentView];

    [self.rootStack addArrangedSubview:card];
}

- (UIStackView *)metricRowWithViews:(NSArray<UIView *> *)views {
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:views];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.alignment = UIStackViewAlignmentTop;
    row.spacing = 12;
    return row;
}

/// 批量结果统一在这里渲染：单码流显示详细指标，多码流额外附对比表
- (void)presentBatchResults {
    BenchStreamResult *primary = self.batchResults.lastObject;

    if (self.batchResults.count == 1) {
        [self presentSingleResult:primary];
        self.comparisonView.hidden = YES;
    } else {
        // 多码流时，主指标区展示最后一个码流，并明确标注是哪个，
        // 避免用户把某一行的数字误当成整体汇总
        [self presentSingleResult:primary];
        [self presentComparison];
        self.comparisonView.hidden = NO;
    }

    self.reportText = [self buildBatchReportText];
    self.reportCopyButton.enabled = YES;
    self.resultCard.hidden = NO;
}

- (void)presentSingleResult:(BenchStreamResult *)result {
    BenchSummary *summary = result.summary;
    BenchRoundMetrics *last = result.rounds.lastObject;

    self.resultStreamLabel.text = result.displayName;

    if (summary.scoredCount == 0) {
        self.stabilityLabel.text = @"仅有预热轮，未产生有效统计";
        for (BenchMetricTile *tile in @[self.fpsTile, self.mspfTile, self.efficiencyTile,
                                        self.cpuTile, self.memoryTile, self.p95Tile]) {
            [tile setValue:@"--" unit:nil];
        }
        return;
    }

    [self.fpsTile setValue:[NSString stringWithFormat:@"%.2f", summary.decodeFPS]
                      unit:@"fps"
                  emphasis:YES];
    if (summary.speedRatio > 0) {
        [self.fpsTile setFootnote:[NSString stringWithFormat:@"%.2fx 源帧率", summary.speedRatio]];
    }

    [self.mspfTile setValue:[NSString stringWithFormat:@"%.3f", summary.avgFrameMs]
                       unit:@"ms"];

    // 每帧 CPU 成本：数值极小，用 4 位有效小数才看得出解码器之间的差别
    [self.efficiencyTile setValue:[NSString stringWithFormat:@"%.4f", summary.cpuSecondsPerFrame]
                             unit:@"核·秒"];

    // CPU 主值用单核百分比（100% = 占满 1 核），这是 Instruments、Android top
    // 都用惯的口径，也是「占比」语义下分辨率最高的表述。
    // 整机占比只放脚注：6 核设备上 0.77 核 = 12.8%，保留一位小数后
    // 相邻两档解码器的差异会被直接抹平（12.8% vs 12.8%），看不出优化效果。
    [self.cpuTile setValue:[NSString stringWithFormat:@"%.0f", summary.avgCPUPercent]
                      unit:@"%"];
    [self.cpuTile setFootnote:[NSString stringWithFormat:@"%.2f 核 · 整机 %.1f%%",
                               summary.avgCPUCores, summary.cpuSharePercent]];

    // 净内存才是解码器自己的开销，绝对值放脚注
    [self.memoryTile setValue:[NSString stringWithFormat:@"%.1f", summary.footprintDeltaMB]
                         unit:@"MB"];
    [self.memoryTile setFootnote:[NSString stringWithFormat:@"峰值 %.0f MB",
                                  summary.peakFootprintMB]];

    [self.p95Tile setValue:[NSString stringWithFormat:@"%.2f", last.p95FrameMs]
                      unit:@"ms"];

    // 稳定性与口径说明放正文，指标格放不下的信息都在这里
    self.stabilityLabel.text = [NSString stringWithFormat:
        @"%lu 轮 · 轮间标准差 %.3f ms (%.1f%%) · 最快 %.3f / 最慢 %.3f ms",
        (unsigned long)summary.scoredCount,
        summary.stddevFrameMs,
        summary.fluctuationPercent,
        summary.minAvgFrameMs,
        summary.maxAvgFrameMs];

    if (last) {
        self.detailLabel.text = [NSString stringWithFormat:
            @"%@ · 源帧率 %.2f fps · 解码 %lu/%lu 帧 · demux %.1f ms · decode %.1f ms · "
            @"峰值线程 %ld · resident 峰 %.0f MB",
            last.resolutionDescription,
            last.sourceFPS,
            (unsigned long)last.decodedFrames,
            (unsigned long)last.totalFrames,
            last.demuxMs,
            last.decodeMs,
            (long)last.peakThreadCount,
            summary.peakResidentMB];
    }
}

/// 多码流对比表：行是指标，列是码流
- (void)presentComparison {
    NSMutableArray<NSString *> *headers = [NSMutableArray array];
    NSMutableArray<NSString *> *fps = [NSMutableArray array];
    NSMutableArray<NSString *> *mspf = [NSMutableArray array];
    NSMutableArray<NSString *> *efficiency = [NSMutableArray array];
    NSMutableArray<NSString *> *cpu = [NSMutableArray array];
    NSMutableArray<NSString *> *memory = [NSMutableArray array];
    NSMutableArray<NSString *> *p95 = [NSMutableArray array];

    for (BenchStreamResult *result in self.batchResults) {
        [headers addObject:result.displayName];
        BenchSummary *s = result.summary;
        if (s.scoredCount == 0) {
            for (NSMutableArray *column in @[fps, mspf, efficiency, cpu, memory, p95]) {
                [column addObject:@"--"];
            }
            continue;
        }
        [fps addObject:[NSString stringWithFormat:@"%.1f", s.decodeFPS]];
        [mspf addObject:[NSString stringWithFormat:@"%.2f", s.avgFrameMs]];
        [efficiency addObject:[NSString stringWithFormat:@"%.4f", s.cpuSecondsPerFrame]];
        [cpu addObject:[NSString stringWithFormat:@"%.1f", s.avgCPUPercent]];
        [memory addObject:[NSString stringWithFormat:@"%.1f", s.footprintDeltaMB]];
        [p95 addObject:[NSString stringWithFormat:@"%.2f",
                        result.rounds.lastObject.p95FrameMs]];
    }

    [self.comparisonView reloadWithHeaders:headers
                                 rowTitles:@[@"fps", @"ms/f", @"核·秒/帧", @"CPU%", @"净内存", @"P95"]
                                    values:@[fps, mspf, efficiency, cpu, memory, p95]];}

/// 批量测试的报告文本：每个码流一段，末尾附对比表
- (NSString *)buildBatchReportText {
    NSMutableString *text = [NSMutableString string];

    if (self.batchResults.count == 1) {
        BenchStreamResult *result = self.batchResults.firstObject;
        [text appendString:[result.summary textReportWithConfig:result.config]];
    } else {
        [text appendFormat:@"===== txav1d 多码流对比测试 (%lu 个) =====\n",
            (unsigned long)self.batchResults.count];
        [text appendFormat:@"设备      : %@ (%@)\n",
            [BenchSystemMetrics deviceName], [BenchSystemMetrics machineIdentifier]];
        [text appendFormat:@"CPU       : %@\n", [BenchSystemMetrics coreTopologyDescription]];
        [text appendFormat:@"热状态    : %@\n", [BenchSystemMetrics thermalStateDescription]];
        [text appendFormat:@"时间      : %@\n",
            [NSDateFormatter localizedStringFromDate:[NSDate date]
                                           dateStyle:NSDateFormatterMediumStyle
                                           timeStyle:NSDateFormatterMediumStyle]];

        // 参数对所有码流一致，只写一次
        BenchStreamResult *first = self.batchResults.firstObject;
        BenchRunConfig *cfg = first.config;
        [text appendFormat:@"每轮帧数  : %@\n",
            cfg.limitFrames > 0 ? [NSString stringWithFormat:@"%lu", (unsigned long)cfg.limitFrames] : @"全部"];
        [text appendFormat:@"轮次      : %lu 正式 + %lu 预热\n",
            (unsigned long)cfg.rounds, (unsigned long)cfg.warmupRounds];
        [text appendFormat:@"线程数    : %@\n",
            cfg.threads > 0 ? [NSString stringWithFormat:@"%ld", (long)cfg.threads] : @"自动"];
        [text appendFormat:@"调度偏好  : %@ —— %@\n",
            [BenchSystemMetrics schedulePolicyName:cfg.schedulePolicy],
            [BenchSystemMetrics schedulePolicyNote:cfg.schedulePolicy]];

        [text appendString:@"\n---------- 对比 ----------\n"];
        // 不能用 %-22s：中文是多字节 UTF-8，按字节数补齐会让列宽错位甚至截断成乱码。
        // 这里统一按字符数右侧补空格。
        void (^appendPadded)(NSString *, NSUInteger) = ^(NSString *value, NSUInteger width) {
            NSUInteger length = value.length;
            if (length >= width) {
                [text appendString:value];
                return;
            }
            [text appendString:value];
            [text appendString:[@"" stringByPaddingToLength:(width - length)
                                                withString:@" "
                                           startingAtIndex:0]];
        };

        appendPadded(@"码流", 22);
        appendPadded(@"fps", 9);
        appendPadded(@"ms/f", 9);
        appendPadded(@"核·秒/帧", 12);
        appendPadded(@"CPU%", 8);
        appendPadded(@"净内存MB", 11);
        appendPadded(@"P95ms", 8);
        [text appendString:@"\n"];

        for (BenchStreamResult *result in self.batchResults) {
            BenchSummary *s = result.summary;
            if (s.scoredCount == 0) continue;
            appendPadded(result.displayName, 22);
            appendPadded([NSString stringWithFormat:@"%.2f", s.decodeFPS], 9);
            appendPadded([NSString stringWithFormat:@"%.3f", s.avgFrameMs], 9);
            appendPadded([NSString stringWithFormat:@"%.5f", s.cpuSecondsPerFrame], 12);
            appendPadded([NSString stringWithFormat:@"%.1f", s.avgCPUPercent], 8);
            appendPadded([NSString stringWithFormat:@"%.1f", s.footprintDeltaMB], 11);
            appendPadded([NSString stringWithFormat:@"%.2f",
                          result.rounds.lastObject.p95FrameMs], 8);
            [text appendString:@"\n"];
        }

        [text appendString:@"\n（核·秒/帧 = 每帧消耗的核心·秒数，越低越高效，可直接跨码流比较）\n"];

        [text appendString:@"\n---------- 逐码流明细 ----------\n"];
        for (BenchStreamResult *result in self.batchResults) {
            [text appendFormat:@"\n--- %@ ---\n", result.displayName];
            BenchSummary *s = result.summary;
            [text appendFormat:@"单帧 %.4f ms  P95 %.4f ms  fps %.2f  %@\n",
                s.avgFrameMs,
                result.rounds.lastObject.p95FrameMs,
                s.decodeFPS,
                result.rounds.lastObject.resolutionDescription];
            [text appendFormat:@"CPU %.1f%% 单核口径 = %.2f 核 = 整机 %.1f%%\n",
                s.avgCPUPercent, s.avgCPUCores, s.cpuSharePercent];
            [text appendFormat:@"每帧 CPU 成本 %.5f 核·秒\n", s.cpuSecondsPerFrame];
            [text appendFormat:@"净内存 %.1f MB（峰值 %.1f MB，resident 峰 %.1f MB）\n",
                s.footprintDeltaMB, s.peakFootprintMB, s.peakResidentMB];
        }
    }

    if (self.failedStreamNames.count > 0) {
        [text appendString:@"\n---------- 失败 ----------\n"];
        for (NSString *failure in self.failedStreamNames) {
            [text appendFormat:@"%@\n", failure];
        }
    }

    return text;
}

- (void)reportHapticFeedback {
    UINotificationFeedbackGenerator *generator = [[UINotificationFeedbackGenerator alloc] init];
    [generator notificationOccurred:UINotificationFeedbackTypeSuccess];
}

#pragma mark - 复制

- (void)copyReportTapped {
    if (self.reportText.length == 0) return;
    UIPasteboard.generalPasteboard.string = self.reportText;

    UINotificationFeedbackGenerator *generator = [[UINotificationFeedbackGenerator alloc] init];
    [generator notificationOccurred:UINotificationFeedbackTypeSuccess];

    UIButtonConfiguration *config = self.reportCopyButton.configuration;
    config.title = @"已复制";
    self.reportCopyButton.configuration = config;

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        UIButtonConfiguration *restored = self.reportCopyButton.configuration;
        restored.title = @"复制报告";
        self.reportCopyButton.configuration = restored;
    });
}

#pragma mark - UITextFieldDelegate

- (void)textFieldDidEndEditing:(UITextField *)textField {
    // 解码器名是折叠区摘要的一部分，改完要立刻反映到收起态
    if (textField == self.decoderField) {
        [self refreshTargetSummary];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];
}

#pragma mark - 自测

- (void)capturePageSnapshotNamed:(NSString *)name {
    [self.view layoutIfNeeded];
    [self.scrollView layoutIfNeeded];
    [self.rootStack layoutIfNeeded];

    // 高度取 rootStack 的实际 frame：它被约束在 scrollView 的内容区里，
    // frame 高度就等于内容总高。不能用 systemLayoutSizeFitting——
    // rootStack 的高度依赖祖先（scrollView.contentLayoutGuide）的约束，
    // 脱离层级单独测量会返回接近 0 的值，于是截图被压成一屏。
    const CGFloat width = MAX(self.scrollView.bounds.size.width,
                              self.rootStack.frame.size.width);
    const CGFloat contentHeight = MAX(self.rootStack.frame.size.height,
                                      self.scrollView.contentSize.height);
    CGSize fullSize = CGSizeMake(width, MAX(contentHeight + 20.0, self.scrollView.bounds.size.height));

    // renderInContext 画的是「传入图层及其子图层」。传 self.view 或 scrollView 时，
    // 其图层边界只有一屏高，滚动内容会被裁掉；而 rootStack 的边界恰好等于内容全高，
    // 直接画它就能拿到完整整页，且不会受祖先图层裁剪影响。
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 2.0;

    NSData *png;
    if (self.targetExpanded) {
        // 展开态含可见的 UITextField，对它做 renderInContext 离屏绘制会崩
        // （signal 11，实测仅在文本框可见时触发）。整段离屏绘制都必须跳过，
        // 改走窗口快照：系统合成路径安全，但只能拿到当前视口。
        UIWindow *window = self.view.window;
        UIGraphicsImageRenderer *snapRenderer =
            [[UIGraphicsImageRenderer alloc] initWithSize:window.bounds.size format:format];
        UIImage *snapshot = [snapRenderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
        }];
        png = UIImagePNGRepresentation(snapshot);
    } else {
        UIGraphicsImageRenderer *renderer =
            [[UIGraphicsImageRenderer alloc] initWithSize:fullSize format:format];

        UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            CGContextRef cg = ctx.CGContext;
            // 铺页面背景色，避免透明区域在 PNG 里变黑
            CGContextSetFillColorWithColor(cg, [BenchTheme background].CGColor);
            CGContextFillRect(cg, CGRectMake(0, 0, fullSize.width, fullSize.height));
            [self.rootStack.layer renderInContext:cg];
        }];
        png = UIImagePNGRepresentation(image);
    }
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                         NSUserDomainMask, YES);
    NSString *path = [paths.firstObject stringByAppendingPathComponent:
                      [name stringByAppendingPathExtension:@"png"]];
    [png writeToFile:path atomically:YES];
    NSLog(@"[UIShot] %@ 已写入 %@ (%@)", name, path,
          [NSByteCountFormatter stringFromByteCount:(long long)png.length
                                         countStyle:NSByteCountFormatterCountStyleFile]);
}

- (void)runHeadlessSelfTest {
    NSMutableString *log = [NSMutableString string];
    void (^append)(NSString *, ...) = ^(NSString *format, ...) {
        va_list args;
        va_start(args, format);
        NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);
        NSLog(@"[SelfTest] %@", line);
        [log appendFormat:@"%@\n", line];
    };

    append(@"设备拓扑：%@ / %@", [BenchSystemMetrics coreTopologyDescription],
           [BenchSystemMetrics machineIdentifier]);
    append(@"可用码流 %lu 个，已选 %lu 个",
           (unsigned long)self.streams.count, (unsigned long)self.selectedStreams.count);

    // 自测默认全选，才能覆盖多码流批量与对比表路径
    if ([[NSProcessInfo processInfo].arguments containsObject:@"--all-streams"]) {
        self.selectedStreams = [self.streams mutableCopy];
        [self refreshStreamPickerDisplay];
        append(@"已全选 %lu 个码流", (unsigned long)self.selectedStreams.count);
    }

    if (self.selectedStreams.count == 0) {
        append(@"失败：没有选中码流");
        [self writeSelfTestLog:log];
        return;
    }

    // 自测按住真实路径走：直接驱动批量队列，验证多码流串联与结果渲染
    NSArray<NSString *> *args = [NSProcessInfo processInfo].arguments;
    NSUInteger framesIndex = [args indexOfObject:@"--frames"];
    NSUInteger threadsIndex = [args indexOfObject:@"--threads"];
    NSUInteger policyIndex = [args indexOfObject:@"--policy"];

    [self.batchResults removeAllObjects];
    [self.failedStreamNames removeAllObjects];
    self.batchCancelled = NO;
    self.batchTotal = self.selectedStreams.count;
    self.pendingStreams = [self.selectedStreams mutableCopy];

    // 自测固定用轻量参数，避免真机上跑太久
    self.framesField.textField.text = framesIndex != NSNotFound && framesIndex + 1 < args.count
        ? args[framesIndex + 1] : @"200";
    self.roundsField.textField.text = @"2";
    self.warmupField.textField.text = @"1";
    if (threadsIndex != NSNotFound && threadsIndex + 1 < args.count) {
        NSUInteger threads = (NSUInteger)[args[threadsIndex + 1] integerValue];
        NSArray<NSNumber *> *mapping = @[@0, @1, @2, @4, @8];
        NSUInteger segment = [mapping indexOfObject:@(threads)];
        if (segment != NSNotFound) {
            self.threadSegment.segmentedControl.selectedSegmentIndex = (NSInteger)segment;
        }
    }
    if (policyIndex != NSNotFound && policyIndex + 1 < args.count) {
        NSInteger policy = [args[policyIndex + 1] integerValue];
        if (policy >= 0 && policy <= 2) {
            self.affinitySegment.segmentedControl.selectedSegmentIndex = policy;
        }
    }

    append(@"调度策略：%@", [BenchSystemMetrics schedulePolicyName:[self schedulePolicyFromSegment]]);
    append(@"开始批量测试：%lu 个码流", (unsigned long)self.batchTotal);

    __weak typeof(self) weakSelf = self;
    // 用轮询等待批量结束，比侵入批量逻辑加回调更简单，也不影响正式代码路径
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self runNextStreamInBatch];
        [self pollSelfTestUntilFinished:log append:append];
    });
}

- (void)pollSelfTestUntilFinished:(NSMutableString *)log
                           append:(void (^)(NSString *, ...))append {
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        if (self.engine.isRunning || self.pendingStreams.count > 0) {
            [self pollSelfTestUntilFinished:log append:append];
            return;
        }

        for (BenchStreamResult *result in self.batchResults) {
            append(@"--- %@ ---", result.displayName);
            for (BenchRoundMetrics *r in result.rounds) {
                append(@"  #%lu %@ %.4f ms/f  P95 %.4f  CPU %.1f%% (%.2f 核)  "
                       @"基线 FP %.1f MB  峰值 FP %.1f MB  净 %.1f MB  RSS峰 %.1f MB  %@",
                       (unsigned long)r.index,
                       r.isWarmup ? @"[预热]" : @"[正式]",
                       r.avgFrameMs, r.p95FrameMs,
                       r.avgCPUPercent, r.avgCPUCores,
                       r.baselineFootprintMB, r.peakFootprintMB, r.footprintDeltaMB,
                       r.peakResidentMB,
                       r.resolutionDescription);
            }
        }
        for (NSString *failure in self.failedStreamNames) {
            append(@"失败：%@", failure);
        }

        [self presentBatchResults];
        append(@"报告文本：\n%@", self.reportText);

        // 结果渲染完再截图，且多等一拍让 CoreAnimation 完成一次布局
        if ([[NSProcessInfo processInfo].arguments containsObject:@"--ui-shot"]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                [self capturePageSnapshotNamed:@"shot_top"];
            });
        }

        append(@"完成");
        [self writeSelfTestLog:log];
    });
}

- (void)writeSelfTestLog:(NSString *)log {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                         NSUserDomainMask, YES);
    NSString *path = [paths.firstObject stringByAppendingPathComponent:@"selftest.log"];
    NSError *error = nil;
    if (![log writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        NSLog(@"[SelfTest] 写日志失败：%@", error.localizedDescription);
    } else {
        NSLog(@"[SelfTest] 日志已写入 %@", path);
    }
}

#pragma mark - 工具

- (void)pinEdgesOfView:(UIView *)child toView:(UIView *)parent {
    child.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [child.topAnchor constraintEqualToAnchor:parent.topAnchor],
        [child.leadingAnchor constraintEqualToAnchor:parent.leadingAnchor],
        [child.trailingAnchor constraintEqualToAnchor:parent.trailingAnchor],
        [child.bottomAnchor constraintEqualToAnchor:parent.bottomAnchor],
    ]];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end




