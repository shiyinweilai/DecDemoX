//
//  ViewController.mm
//  TXAV1Dec
//

#import "ViewController.h"
#import "BenchEngine.h"
#import "BenchDecoderLoader.h"
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
    _valueLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
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

/** 一个「版本 × 码流」组合的完整测试结果，批量测试后用于横向对比 */
@interface BenchStreamResult : NSObject

@property (nonatomic, strong) BenchStream *stream;
@property (nonatomic, strong) BenchDecoder *decoder;
@property (nonatomic, strong) BenchRunConfig *config;
@property (nonatomic, strong) NSArray<BenchRoundMetrics *> *rounds;
@property (nonatomic, strong) BenchSummary *summary;

/** 码流名（不含扩展名），用于列头 */
- (NSString *)streamDisplayName;

/** 版本号，如 "1.4.3" */
- (NSString *)decoderDisplayName;

/**
 * 列头文本。
 *
 * 单码流时只需要码流名；跨版本对比时，同一码流会出现多列，
 * 必须把版本号一起放进列头，否则两列完全同名、无法分辨。
 */
- (NSString *)displayName;

@end

@implementation BenchStreamResult

- (NSString *)streamDisplayName {
    NSString *name = self.stream.name ?: self.config.streamName ?: @"未知码流";
    // 对比表列头空间有限，去掉扩展名让列宽更可控
    return name.stringByDeletingPathExtension.length > 0
        ? name.stringByDeletingPathExtension : name;
}

- (NSString *)decoderDisplayName {
    return self.decoder.version ?: @"未知版本";
}

/**
 * 组合名，单行。
 *
 * 对比表列头是单行标签（numberOfLines = 1），换行会被截断成一行半，
 * 所以这里用中点连接而不是两行。
 */
- (NSString *)displayName {
    return [NSString stringWithFormat:@"%@ · %@",
            [self decoderDisplayName], [self streamDisplayName]];
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
@property (nonatomic, strong) BenchSegmentRow *threadSegment;
@property (nonatomic, strong) BenchSegmentRow *affinitySegment;

/**
 * 命令行指定的线程数，-1 表示未指定、按界面分段控件取值。
 *
 * 界面分段只提供 0/1/2/4/8 五档，但自测需要扫 3、6、12 这类非档位值
 * 来定位线程数拐点。早期实现是把 --threads 反查成分段索引，传 6 时
 * indexOfObject 找不到就静默保持默认，表现成「命令行改不了线程」。
 * 这里用独立属性承载任意值，不复用分段控件。
 */
@property (nonatomic, assign) NSInteger threadsOverride;

// 解码器选择：与码流一样用弹出多选，版本列表来自构建产物而非硬编码
@property (nonatomic, strong) BenchStreamPickerRow *decoderPickerRow;
@property (nonatomic, strong) NSArray<BenchDecoder *> *decoders;
@property (nonatomic, strong) NSMutableArray<BenchDecoder *> *selectedDecoders;

/**
 * 当前弹出的多选面板。
 *
 * 面板改为「不自动收起」后，选中态变化不再靠「关掉再弹一个」来刷新，
 * 而是由控制器持有面板引用、原地 reload。因此这两个引用同时承担两件事：
 * 判断面板是否已经打开（避免重复叠加），以及给 toggle 回调提供刷新入口。
 * 面板关闭时通过 onDismiss 置空。
 */
@property (nonatomic, strong, nullable) BenchMultiSelectPanel *streamPanel;
@property (nonatomic, strong, nullable) BenchMultiSelectPanel *decoderPanel;

// 操作
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *stageLabel;

// 结果
@property (nonatomic, strong) BenchCardView *resultCard;

/**
 * 指标矩阵：6 行主要指标 × N 列对象。
 *
 * 主要指标固定六项（fps、单帧耗时、CPU、波动、P95、净内存），
 * 被比较的对象数量不定（版本 × 码流的组合），因此指标做行、对象做列。
 * 这样加一个版本或多勾一个码流只是多一列，布局不用重排。
 */
@property (nonatomic, strong) BenchComparisonView *matrixView;

/**
 * 波动与 P95 的口径说明，紧贴表格下方。
 *
 * 这两个指标名字本身不足以自解释：「波动」看不出是帧间抖动还是轮间离散，
 * 「P95」不写清百分位方向也会被读成「最慢的 5% 有多慢」。
 * 单独一行说明比塞进行标题更合适——行标题列只有 86pt，
 * 塞进注释必然被压缩或换行成三行，反而破坏六行的对齐。
 */
@property (nonatomic, strong) UILabel *metricLegendLabel;

/** 矩阵下方按组合罗列的次要信息，每个组合一行 */
@property (nonatomic, strong) UILabel *secondaryLabel;

@property (nonatomic, strong) UIButton *reportCopyButton;
@property (nonatomic, copy) NSString *reportText;

// 数据
@property (nonatomic, strong) NSArray<BenchStream *> *streams;
@property (nonatomic, strong) NSMutableArray<BenchStream *> *selectedStreams;
@property (nonatomic, strong) BenchEngine *engine;

// 批量测试状态
@property (nonatomic, strong) NSMutableArray<BenchStreamResult *> *batchResults;
@property (nonatomic, strong) NSMutableArray<NSString *> *failedStreamNames;
@property (nonatomic, assign) NSUInteger batchTotal;
@property (nonatomic, assign) BOOL batchCancelled;
@property (nonatomic, strong) BenchRunConfig *lastConfig;

/**
 * 待测「解码器 × 码流」组合队列。
 *
 * 多版本多码流时总轮数是两者之积，只用一个码流队列无法表达「换版本重跑
 * 同一码流」这个维度，所以把组合展开成扁平队列：每项自带解码器与码流，
 * 顺序执行即可保证同版本的各码流连续跑完，减少库加载切换带来的干扰。
 */
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *pendingCombinations;

/** 当前正在执行的组合，供阶段文案与失败信息使用 */
@property (nonatomic, strong) NSDictionary *activeCombination;

/** 本批实际参与的解码器数量，用于进度与报告标题 */
@property (nonatomic, assign) NSUInteger batchDecoderCount;
@property (nonatomic, assign) NSUInteger batchStreamCount;

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
    self.failedStreamNames = [NSMutableArray array];
    self.pendingCombinations = [NSMutableArray array];
    self.decoders = @[];
    self.selectedDecoders = [NSMutableArray array];

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
    self.deviceNameLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
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

    // 解码器版本与码流一样用弹出多选：版本列表来自 App 包内的 dylib，
    // 新增版本只需往 DecoderSDK 放目录并重新编译，界面不用改。
    self.decoderPickerRow = [[BenchStreamPickerRow alloc] initWithTitle:@"解码器版本（可多选）"];
    [self.decoderPickerRow.button addTarget:self
                                     action:@selector(decoderPickerTapped)
                           forControlEvents:UIControlEventTouchUpInside];

    UIStackView *targetDetail = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.streamPickerRow, self.decoderPickerRow
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
    [self reloadDecoders];
}

#pragma mark - 解码器选择

/**
 * 扫描 App 包内的解码器版本并刷新选择状态。
 *
 * 只做目录扫描（scanDecoders），不加载任何 dylib：版本名、构建时间都来自
 * 文件属性，界面立刻就能渲染。真正的 dlopen 推迟到点「开始测试」时，
 * 由引擎在后台队列按需加载被勾选的那几个版本。
 */
- (void)reloadDecoders {
    self.decoders = [BenchDecoderLibrary scanDecoders];

    // 默认只勾选最新版本：全选会让首次测试的耗时成倍增长，
    // 而绝大多数时候用户只是想测最新版本。这里按版本名取第一项即可，
    // 不再依赖加载结果——扫描阶段本来也还没有加载任何库。
    [self.selectedDecoders removeAllObjects];
    if (self.decoders.count > 0) {
        [self.selectedDecoders addObject:self.decoders.firstObject];
    }

    [self refreshDecoderPickerDisplay];
    [self updateStartButtonState];
}

- (void)refreshDecoderPickerDisplay {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (BenchDecoder *decoder in self.selectedDecoders) {
        [names addObject:decoder.version];
    }
    [self.decoderPickerRow updateWithSelectedNames:names];
    [self refreshTargetSummary];
}

- (void)decoderPickerTapped {
    [self dismissKeyboard];
    if (self.engine.isRunning) return;
    if (self.decoderPanel) return;

    NSArray<BenchMultiSelectItem *> *items = [self decoderPickerItems];

    __weak typeof(self) weakSelf = self;
    BenchMultiSelectPanel *panel =
        [BenchMultiSelectPanel presentInView:self.view
                                       title:@"选择解码器版本"
                                     message:self.decoders.count == 0
                                                 ? @"未找到解码器，请检查构建产物"
                                                 : @"可多选，再次点击已选项即可取消"
                                       items:items];
    self.decoderPanel = panel;

    panel.onToggleItem = ^(NSInteger index) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (index < 0 || index >= (NSInteger)self.decoders.count) return;
        BenchDecoder *decoder = self.decoders[index];
        if (decoder.isLoaded && !decoder.isUsable) {
            // 只对「已确认加载失败」的版本拦住点击：这类版本真跑不起来，
            // 让用户选上只会在开始时失败。尚未加载的版本一律允许勾选，
            // 因为加载被推迟到开跑时才发生，此刻无从判断好坏。
            [self showAlertWithTitle:[NSString stringWithFormat:@"%@ 不可用", decoder.version]
                             message:decoder.loadError ?: @"未知原因"];
            return;
        }
        [self toggleDecoder:decoder];
    };

    panel.onSelectAll = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        NSUInteger selectableCount = 0;
        for (BenchDecoder *decoder in self.decoders) {
            if (!(decoder.isLoaded && !decoder.isUsable)) selectableCount++;
        }
        const BOOL allSelected = (self.selectedDecoders.count == selectableCount && selectableCount > 0);
        [self.selectedDecoders removeAllObjects];
        if (!allSelected) {
            for (BenchDecoder *decoder in self.decoders) {
                // 已确认加载失败的版本不参与全选：它们注定跑不起来
                if (!(decoder.isLoaded && !decoder.isUsable)) [self.selectedDecoders addObject:decoder];
            }
        }
        [self refreshDecoderPickerDisplay];
        [self updateStartButtonState];
        [self.decoderPanel reloadWithItems:[self decoderPickerItems]];
    };

    // 「仅选最新版本」在对比场景很常用：全选会让耗时成倍增长，
    // 而多数时候只想先看最新版的表现，所以保留成一个独立快捷动作。
    [panel setExtraActionTitle:@"仅选最新" handler:^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self.selectedDecoders removeAllObjects];
        for (BenchDecoder *decoder in self.decoders) {
            if (!(decoder.isLoaded && !decoder.isUsable)) {
                [self.selectedDecoders addObject:decoder];
                break;
            }
        }
        [self refreshDecoderPickerDisplay];
        [self updateStartButtonState];
        [self.decoderPanel reloadWithItems:[self decoderPickerItems]];
    }];

    panel.onDismiss = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.decoderPanel = nil;
    };
}

/** 把解码器列表映射成浮层行数据，确认加载失败的版本带上原因并置灰 */
- (NSArray<BenchMultiSelectItem *> *)decoderPickerItems {
    NSMutableArray<BenchMultiSelectItem *> *items = [NSMutableArray array];
    for (BenchDecoder *decoder in self.decoders) {
        const BOOL failed = (decoder.isLoaded && !decoder.isUsable);
        NSString *detail;
        if (failed) {
            detail = decoder.loadError ?: @"不可用";
        } else {
            // 未加载也显示构建时间：这是判断「这份库是不是我刚编的那个」的依据，
            // 与是否已 dlopen 无关，扫描阶段就已经拿到了。
            detail = decoder.buildStamp.length > 0 ? decoder.buildStamp : @"待加载";
        }
        BenchMultiSelectItem *item = [BenchMultiSelectItem itemWithTitle:decoder.version detail:detail];
        item.selected = [self.selectedDecoders containsObject:decoder];
        item.enabled = !failed;
        [items addObject:item];
    }
    return items;
}

- (void)toggleDecoder:(BenchDecoder *)decoder {
    if ([self.selectedDecoders containsObject:decoder]) {
        [self.selectedDecoders removeObject:decoder];
    } else {
        [self.selectedDecoders addObject:decoder];
        // 保持与版本库一致的降序，避免用户按点击顺序得到 1.4.2、1.4.3 交替的
        // 结果列表，那种顺序会让对比表列序随点击顺序漂移。
        // 复用版本库的比较器而不是本地写一份：两处各写一份时，
        // 排序基准一旦分叉，勾选顺序与列表顺序就会不一致。
        [self.selectedDecoders sortUsingComparator:^NSComparisonResult(BenchDecoder *a, BenchDecoder *b) {
            return [BenchDecoderLibrary compareVersion:a.version with:b.version];
        }];
    }
    [self refreshDecoderPickerDisplay];
    [self updateStartButtonState];

    // 原地刷新，面板保持打开，支持连续勾选多个版本
    [self.decoderPanel reloadWithItems:[self decoderPickerItems]];
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
    NSString *decoderPart;
    if (self.selectedDecoders.count == 0) {
        decoderPart = @"未选解码器";
    } else if (self.selectedDecoders.count == 1) {
        decoderPart = self.selectedDecoders.firstObject.version;
    } else {
        // 多选时显示首尾版本号比只给数量更有信息量：
        // 一眼能看出测的是哪两个版本，而不是"3 个版本"这种无法核对的摘要。
        decoderPart = [NSString stringWithFormat:@"%@~%@ %lu 版",
                       self.selectedDecoders.lastObject.version,
                       self.selectedDecoders.firstObject.version,
                       (unsigned long)self.selectedDecoders.count];
    }

    NSString *streamPart;
    if (self.selectedStreams.count == 0) {
        streamPart = @"未选码流";
    } else if (self.selectedStreams.count == 1) {
        streamPart = self.selectedStreams.firstObject.name;
    } else {
        streamPart = [NSString stringWithFormat:@"%lu 个码流",
                      (unsigned long)self.selectedStreams.count];
    }

    [self.targetRow setSummary:[NSString stringWithFormat:@"%@ · %@", decoderPart, streamPart]];
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

    // 已经打开时不重复叠加：面板不再自动关闭，连续点触发行只会把面板
    // 叠成一层又一层，最后要连点多次空白才能全部收掉。
    if (self.streamPanel) return;

    NSArray<BenchMultiSelectItem *> *items = [self streamPickerItems];
    const BOOL empty = (self.streams.count == 0);

    __weak typeof(self) weakSelf = self;
    BenchMultiSelectPanel *panel =
        [BenchMultiSelectPanel presentInView:self.view
                                       title:@"选择测试码流"
                                     message:empty ? @"未找到码流文件，请检查 Documents/Streams"
                                                   : @"可多选，再次点击已选项即可取消"
                                       items:items];
    self.streamPanel = panel;

    panel.onToggleItem = ^(NSInteger index) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (index < 0 || index >= (NSInteger)self.streams.count) return;
        [self toggleStream:self.streams[index]];
    };

    panel.onSelectAll = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        // 已全选时再点「全选」变成全不选：面板不会自动关闭，
        // 这个按钮成了唯一的批量入口，必须能反向操作，否则清空只能逐项点。
        const BOOL allSelected = (self.selectedStreams.count == self.streams.count
                                  && self.streams.count > 0);
        [self.selectedStreams removeAllObjects];
        if (!allSelected) {
            [self.selectedStreams addObjectsFromArray:self.streams];
        }
        [self refreshStreamPickerDisplay];
        [self updateStartButtonState];
        [self.streamPanel reloadWithItems:[self streamPickerItems]];
    };

    panel.onDismiss = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.streamPanel = nil;
    };
}

/** 把当前码流列表映射成浮层行数据，选中态取自 selectedStreams */
- (NSArray<BenchMultiSelectItem *> *)streamPickerItems {
    NSMutableArray<BenchMultiSelectItem *> *items = [NSMutableArray array];
    for (BenchStream *stream in self.streams) {
        BenchMultiSelectItem *item = [BenchMultiSelectItem itemWithTitle:stream.name
                                                                  detail:stream.sizeDescription];
        item.selected = [self.selectedStreams containsObject:stream];
        [items addObject:item];
    }
    return items;
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

    // 原地刷新面板，不再关掉重开：重开会造成闪一下的观感，
    // 用户也无法连续确认自己刚才点的是哪一项。
    [self.streamPanel reloadWithItems:[self streamPickerItems]];
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

    if (self.selectedDecoders.count == 0) {
        [self showAlertWithTitle:@"没有选择解码器"
                         message:@"请点开「解码器版本」选择至少一个版本。若列表为空，说明构建产物里没有可用的解码器动态库。"];
        return;
    }

    // 每次开跑前清空上一轮，避免新旧结果混在一起
    [self.batchResults removeAllObjects];
    [self.failedStreamNames removeAllObjects];
    [self.pendingCombinations removeAllObjects];
    self.reportText = nil;
    self.reportCopyButton.enabled = NO;
    self.resultCard.hidden = YES;
    self.batchCancelled = NO;
    self.activeCombination = nil;
    self.batchDecoderCount = self.selectedDecoders.count;
    self.batchStreamCount = self.selectedStreams.count;

    // 组合展开顺序：外层版本、内层码流。这样同一版本的多个码流连续跑完，
    // 避免频繁切换库；而库切换本身也不贵（只 dlopen 一次），所以顺序影响很小。
    for (BenchDecoder *decoder in self.selectedDecoders) {
        for (BenchStream *stream in self.selectedStreams) {
            [self.pendingCombinations addObject:@{@"decoder": decoder, @"stream": stream}];
        }
    }

    self.batchTotal = self.pendingCombinations.count;

    [self setRunningUI:YES];
    [self runNextStreamInBatch];
}

/// 取出待测队列里的下一个「版本 × 码流」组合开跑；队列空则收尾
- (void)runNextStreamInBatch {
    if (self.batchCancelled || self.pendingCombinations.count == 0) {
        [self finishBatch];
        return;
    }

    NSDictionary *combination = self.pendingCombinations.firstObject;
    [self.pendingCombinations removeObjectAtIndex:0];
    self.activeCombination = combination;

    BenchDecoder *decoder = combination[@"decoder"];
    BenchStream *stream = combination[@"stream"];

    const NSUInteger overallIndex = self.batchTotal - self.pendingCombinations.count;
    // 多组合时前缀带上版本号：只给序号的话，用户看不出当前跑的是哪个版本，
    // 而多版本测试恰恰最需要这个信息。
    NSString *prefix = self.batchTotal > 1
        ? [NSString stringWithFormat:@"[%lu/%lu] %@ ",
           (unsigned long)overallIndex, (unsigned long)self.batchTotal, decoder.version]
        : @"";

    BenchRunConfig *config = [self buildConfigForStream:stream decoder:decoder];
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
            // 单个组合失败不该中断整批，记录后继续下一个。
            // 版本号必须带上：多版本测试里"某个码流失败"必须能定位到具体版本，
            // 否则两个版本一好一坏时会看不出是谁的问题。
            [self.failedStreamNames addObject:[NSString stringWithFormat:@"%@ / %@: %@",
                                               decoder.version, stream.name, error]];
        } else if (rounds.count > 0) {
            BenchStreamResult *result = [[BenchStreamResult alloc] init];
            result.stream = stream;
            result.decoder = decoder;
            result.config = config;
            result.rounds = rounds;
            result.summary = [BenchSummary summaryWithRounds:rounds];
            [self.batchResults addObject:result];
        }

        [self runNextStreamInBatch];
    }];
}

- (BenchRunConfig *)buildConfigForStream:(BenchStream *)stream
                                 decoder:(BenchDecoder *)decoder {
    BenchRunConfig *config = [[BenchRunConfig alloc] init];
    config.streamPath = stream.path;
    config.streamName = stream.name;
    config.limitFrames = (NSUInteger)[self.framesField integerValueWithFallback:200];
    config.rounds = (NSUInteger)[self.roundsField integerValueWithFallback:3];
    config.warmupRounds = (NSUInteger)[self.warmupField integerValueWithFallback:1];
    config.skipFrames = (NSUInteger)MAX([self.skipField integerValueWithFallback:0], 0);
    // 命令行给了线程数就优先用它：自测要扫非档位值（3/6/12）定位线程拐点，
    // 分段控件只能表达 0/1/2/4/8，反查索引会静默落回默认档。
    if (self.threadsOverride >= 0) {
        config.threads = self.threadsOverride;
    } else {
        config.threads = [self threadCountFromSegment];
    }
    config.schedulePolicy = [self schedulePolicyFromSegment];
    // 解码器实例与展示名一起绑定：名称取自实际加载的那个库，
    // 而不是用户填的文本，杜绝"跑 A 标 B"。
    config.decoder = decoder;
    // 这里不填 decoderName：此刻库可能还没 dlopen（加载推迟到引擎后台队列），
    // displayName 里「库自报版本与目录名不一致」这条交叉校验信息还拿不到。
    // 留空由引擎在加载成功后回填，见 BenchEngine 的 applyResolvedDecoderName。
    config.decoderName = nil;

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
    self.decoderPickerRow.button.enabled = !running;
    self.streamPickerRow.button.enabled = !running;
    self.reportCopyButton.enabled = !running && self.reportText.length > 0;

    // 开跑时收起仍打开的选择浮层：浮层是模态遮罩，不收起会盖住进度条和
    // 结果面板，而开跑后也不允许再改选择（两个触发按钮已禁用）。
    if (running) {
        [self.streamPanel dismiss];
        [self.decoderPanel dismiss];
    }
}

- (void)updateStartButtonState {
    if (self.engine.isRunning) return;
    // 解码器也必须选中：只选了码流却没选版本时按钮就该是灰的，
    // 否则点下去才弹提示，多一次无效操作。
    const BOOL ready = self.selectedStreams.count > 0 && self.selectedDecoders.count > 0;
    self.startButton.enabled = ready;
    UIButtonConfiguration *config = self.startButton.configuration;
    config.baseBackgroundColor = ready ? [BenchTheme accent] : [UIColor tertiaryLabelColor];
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
    // 主要指标区：固定六行，被比较的对象做列。
    // 单对象也用同一套矩阵，避免「一个结果用格子、多个结果用表格」导致
    // 两种视觉形态来回切换，用户每次都要重新找数字在哪。
    self.matrixView = [[BenchComparisonView alloc] initWithFrame:CGRectZero];

    // 次要信息：口径、轮次、demux/decode 拆分、分辨率、线程峰值等。
    // 这些是核对数字时才需要的，放在表格下方并按组合分组，
    // 主表保持六行干净，一眼就能比较出谁快谁省。
    self.secondaryLabel = [[UILabel alloc] init];
    self.secondaryLabel.font = [BenchTheme monoFontOfSize:12];
    self.secondaryLabel.textColor = [BenchTheme secondaryText];
    self.secondaryLabel.numberOfLines = 0;

    // 波动与 P95 的口径说明。字号比正文小一档、颜色用次要色，
    // 让它读起来像注释而不是第七个指标，避免抢走六行主表的注意力。
    self.metricLegendLabel = [[UILabel alloc] init];
    self.metricLegendLabel.font = [UIFont systemFontOfSize:11];
    self.metricLegendLabel.textColor = [BenchTheme secondaryText];
    self.metricLegendLabel.numberOfLines = 0;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        headerRow, self.matrixView, self.metricLegendLabel, self.secondaryLabel
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card.contentView addSubview:stack];
    [self pinEdgesOfView:stack toView:card.contentView];

    [self.rootStack addArrangedSubview:card];
}

/// 批量结果统一在这里渲染：主指标进矩阵，其余信息进下方明细
- (void)presentBatchResults {
    [self presentMatrix];

    self.reportText = [self buildBatchReportText];
    self.reportCopyButton.enabled = YES;
    self.resultCard.hidden = NO;
}

/**
 * 渲染六行主要指标矩阵。
 *
 * 列 = 每个「版本 × 码流」组合。列头分两行显示版本与码流：
 * 多版本多码流时组合数会到十几个，单行标题在等分列宽下必然被截断，
 * 而列头一旦看不清就分不出哪列是哪个版本。
 */
- (void)presentMatrix {
    NSMutableArray<NSString *> *headers = [NSMutableArray array];
    NSMutableArray<NSString *> *fps = [NSMutableArray array];
    NSMutableArray<NSString *> *mspf = [NSMutableArray array];
    NSMutableArray<NSString *> *cpu = [NSMutableArray array];
    NSMutableArray<NSString *> *jitter = [NSMutableArray array];
    NSMutableArray<NSString *> *p95 = [NSMutableArray array];
    NSMutableArray<NSString *> *memory = [NSMutableArray array];

    // 列头只放版本：同一轮测试的码流与参数是对齐的，码流名对每一列都一样，
    // 重复 N 遍既不提供信息，还要占掉列头一半宽度、把版本名挤小。
    // 多码流时同一版本会出现多列，此时只追加序号区分（1.4.3 / 1.4.3 #2），
    // 仍然不把码流名写进表头——条件是对齐的，具体是哪个码流由测试者自己知道。
    NSCountedSet *nameCount = [NSCountedSet set];
    for (BenchStreamResult *result in self.batchResults) {
        [nameCount addObject:result.decoderDisplayName];
    }
    NSMutableDictionary<NSString *, NSNumber *> *nameSeen = [NSMutableDictionary dictionary];

    for (BenchStreamResult *result in self.batchResults) {
        NSString *base = result.decoderDisplayName;
        NSString *header = base;
        if ([nameCount countForObject:base] > 1) {
            NSUInteger seen = ([nameSeen[base] unsignedIntegerValue] + 1);
            nameSeen[base] = @(seen);
            header = [NSString stringWithFormat:@"%@ #%lu", base, (unsigned long)seen];
        }
        [headers addObject:header];
        BenchSummary *s = result.summary;
        if (s.scoredCount == 0) {
            for (NSMutableArray *column in @[fps, mspf, cpu, jitter, p95, memory]) {
                [column addObject:@"--"];
            }
            continue;
        }
        [fps addObject:[NSString stringWithFormat:@"%.1f", s.decodeFPS]];
        [mspf addObject:[NSString stringWithFormat:@"%.2f", s.avgFrameMs]];
        // CPU 用整机占比，与报告同口径。两位小数：6 核机上整机占比
        // 一位小数只有 0.6% 单核的精度，两档实现并列时常显示成同一个数。
        // 无采样必须显示 --：0.00% 会被读成「几乎不占 CPU」，与事实相反。
        [cpu addObject:s.avgCPUSampled
            ? [NSString stringWithFormat:@"%.2f%%", s.cpuSharePercent] : @"--"];
        [jitter addObject:[NSString stringWithFormat:@"%.2f%%", s.fluctuationPercent]];
        [p95 addObject:[NSString stringWithFormat:@"%.2f",
                        result.rounds.lastObject.p95FrameMs]];
        [memory addObject:s.memorySampled
            ? [NSString stringWithFormat:@"%.1f", s.footprintDeltaMB] : @"--"];
    }

    // 行序即判读顺序：快不快 → 贵不贵 → 稳不稳。
    // 净内存提到第 4 行，波动与 P95 落到第 5、6 行：
    // 前四个是每次挑选版本都必看的量，波动和 P95 用于进一步挑刺，
    // 放在尾部既不打断主线，又能固定占据最后两行便于纵向扫视。
    [self.matrixView reloadWithHeaders:headers
                             rowTitles:@[@"解码帧率 fps", @"单帧耗时 ms", @"CPU 整机",
                                         @"净内存 MB", @"波动", @"P95 ms"]
                                values:@[fps, mspf, cpu, memory, jitter, p95]
                         emphasizedRow:0];

    self.metricLegendLabel.text =
        @"波动 = 轮间标准差 ÷ 均值。反复跑同一版本时每轮结果的离散程度，反映测试是否稳定；"
        @"它不是帧与帧之间的抖动。有效轮次不足 2 轮时为 0.00%，只说明样本不够，不代表稳定。\n"
        @"P95 = 最后一轮内全部帧耗时排序后的第 95 百分位，即 95% 的帧不慢于该值。"
        @"它反映帧间抖动，平均值被大量正常帧摊平后看不出偶发长帧，P95 能暴露出来。\n"
        @"显示 -- 表示该轮没有采到有效样本（通常是帧数太少、单轮时长过短），"
        @"不等于占用为 0；此时应提高每轮帧数后重测。";

    self.secondaryLabel.text = [self buildSecondaryInfoText];
}

/**
 * 表格下方的次要信息。
 *
 * 每个组合一段，只在多组合时加标题行以示区分；单组合时省略标题，
 * 避免只有一列却多出一行没有信息量的名字。
 */
- (NSString *)buildSecondaryInfoText {
    NSMutableArray<NSString *> *blocks = [NSMutableArray array];
    const BOOL multi = self.batchResults.count > 1;

    for (BenchStreamResult *result in self.batchResults) {
        BenchSummary *s = result.summary;
        BenchRoundMetrics *last = result.rounds.lastObject;
        NSMutableArray<NSString *> *lines = [NSMutableArray array];

        if (multi) {
            // 与列头一致，不写码流名。多码流时同一版本会出现多段，
            // 此时用与表头相同的序号标记，保证两处能对上号。
            NSUInteger sameNameCount = 0;
            for (BenchStreamResult *other in self.batchResults) {
                if ([other.decoderDisplayName isEqualToString:result.decoderDisplayName]) {
                    sameNameCount++;
                }
            }
            if (sameNameCount > 1) {
                // 序号按出现顺序累加，与表头用的是同一份批次顺序
                NSUInteger ordinal = 0;
                for (BenchStreamResult *other in self.batchResults) {
                    if (other == result) break;
                    if ([other.decoderDisplayName isEqualToString:result.decoderDisplayName]) {
                        ordinal++;
                    }
                }
                [lines addObject:[NSString stringWithFormat:@"%@ #%lu",
                                  result.decoderDisplayName, (unsigned long)(ordinal + 1)]];
            } else {
                [lines addObject:result.decoderDisplayName];
            }
        }

        if (s.scoredCount == 0) {
            [lines addObject:@"  仅有预热轮，未产生有效统计"];
            [blocks addObject:[lines componentsJoinedByString:@"\n"]];
            continue;
        }

        // 用「口径 + 绝对值」并列：整机占比和单核口径是同一件事的两种说法，
        // 但跨机型对比只能用整机占比，排查 CPU 是否被打满却要看单核口径。
        [lines addObject:[NSString stringWithFormat:
            @"  CPU %.1f%% 整机 = %.0f%% 单核口径 · 净内存 峰值 %.0f MB",
            s.cpuSharePercent, s.avgCPUPercent, s.peakFootprintMB]];
        [lines addObject:[NSString stringWithFormat:
            @"  %lu 轮 · 最快 %.3f / 最慢 %.3f ms · P50 %.3f ms · 波动 ±%.3f ms",
            (unsigned long)s.scoredCount, s.minAvgFrameMs, s.maxAvgFrameMs,
            last.p50FrameMs, s.stddevFrameMs]];
        if (last) {
            [lines addObject:[NSString stringWithFormat:
                @"  %@ · 源 %.2f fps · 解码 %lu/%lu 帧 · demux %.1f ms · decode %.1f ms",
                last.resolutionDescription, last.sourceFPS,
                (unsigned long)last.decodedFrames, (unsigned long)last.totalFrames,
                last.demuxMs, last.decodeMs]];
            [lines addObject:[NSString stringWithFormat:
                @"  峰值线程 %ld · resident 峰 %.0f MB",
                (long)last.peakThreadCount, s.peakResidentMB]];
        }

        [blocks addObject:[lines componentsJoinedByString:@"\n"]];
    }

    return [blocks componentsJoinedByString:@"\n\n"];
}

/// 批量测试的报告文本：每个码流一段，末尾附对比表
- (NSString *)buildBatchReportText {
    NSMutableString *text = [NSMutableString string];

    if (self.batchResults.count == 1) {
        BenchStreamResult *result = self.batchResults.firstObject;
        [text appendString:[result.summary textReportWithConfig:result.config]];
    } else {
        // 标题里写明规模：多版本多码流时，"12 个组合"远比"12 个"有信息量，
        // 读者能立刻知道这张表是两个维度的笛卡尔积。
        if (self.batchDecoderCount > 1 && self.batchStreamCount > 1) {
            [text appendFormat:@"===== txav1d 多版本 × 多码流对比 (%lu 版本 × %lu 码流 = %lu 组合) =====\n",
                (unsigned long)self.batchDecoderCount,
                (unsigned long)self.batchStreamCount,
                (unsigned long)self.batchResults.count];
        } else if (self.batchDecoderCount > 1) {
            [text appendFormat:@"===== txav1d 多版本对比测试 (%lu 个版本) =====\n",
                (unsigned long)self.batchResults.count];
        } else {
            [text appendFormat:@"===== txav1d 多码流对比测试 (%lu 个) =====\n",
                (unsigned long)self.batchResults.count];
        }
        [text appendFormat:@"设备      : %@ (%@)\n",
            [BenchSystemMetrics deviceName], [BenchSystemMetrics machineIdentifier]];
        [text appendFormat:@"CPU       : %@\n", [BenchSystemMetrics coreTopologyDescription]];
        [text appendFormat:@"热状态    : %@\n", [BenchSystemMetrics thermalStateDescription]];
        [text appendFormat:@"时间      : %@\n",
            [NSDateFormatter localizedStringFromDate:[NSDate date]
                                           dateStyle:NSDateFormatterMediumStyle
                                           timeStyle:NSDateFormatterMediumStyle]];

        // 参数对所有组合一致，只写一次
        BenchStreamResult *first = self.batchResults.firstObject;
        BenchRunConfig *cfg = first.config;
        // 多版本时逐个列出参与版本：只写"多个版本"等于没写，
        // 事后根本无法确认这批数字覆盖了哪些库。
        if (self.batchDecoderCount > 1) {
            NSMutableArray<NSString *> *versions = [NSMutableArray array];
            for (BenchDecoder *decoder in self.selectedDecoders) {
                [versions addObject:decoder.version];
            }
            [text appendFormat:@"解码器    : %lu 个版本（%@）\n",
                (unsigned long)versions.count,
                [versions componentsJoinedByString:@", "]];
        } else {
            [text appendFormat:@"解码器    : %@\n",
                cfg.decoderName.length > 0 ? cfg.decoderName : BenchDecoderVersionDescription()];
        }
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

        appendPadded(@"版本", 10);
        appendPadded(@"fps", 9);
        appendPadded(@"ms/f", 9);
        appendPadded(@"CPU%", 9);
        appendPadded(@"波动%", 9);
        appendPadded(@"P95ms", 9);
        appendPadded(@"净内存MB", 11);
        [text appendString:@"\n"];

        // 报告里不放码流名：同一批测试的条件是对齐的，码流名对每行都一样，
        // 逐行重复既不提供信息，还挤掉指标列的宽度。
        for (BenchStreamResult *result in self.batchResults) {
            BenchSummary *s = result.summary;
            if (s.scoredCount == 0) continue;
            appendPadded(result.decoderDisplayName, 10);
            appendPadded([NSString stringWithFormat:@"%.2f", s.decodeFPS], 9);
            appendPadded([NSString stringWithFormat:@"%.3f", s.avgFrameMs], 9);
            appendPadded(s.avgCPUSampled
                         ? [NSString stringWithFormat:@"%.2f", s.cpuSharePercent] : @"--", 9);
            appendPadded([NSString stringWithFormat:@"%.2f", s.fluctuationPercent], 9);
            appendPadded([NSString stringWithFormat:@"%.2f",
                          result.rounds.lastObject.p95FrameMs], 9);
            appendPadded(s.memorySampled
                         ? [NSString stringWithFormat:@"%.1f", s.footprintDeltaMB] : @"--", 11);
            [text appendString:@"\n"];
        }

        [text appendString:@"\n（CPU% 为整机占比；波动% = 轮间标准差/均值，越低越稳定；-- 表示无有效采样）\n"];

        // 同码流跨版本对比：这才是多版本测试真正要看的表。
        // 上面的表按组合罗列，要自己横着找同一个码流的两行再比，
        // 版本一多就容易错位，所以直接把「相对基准版本的提升」算出来。
        if (self.batchDecoderCount > 1 && self.batchStreamCount >= 1) {
            [text appendString:@"\n---------- 跨版本提升 ----------\n"];
            [text appendFormat:@"基准 = %@（各版本相对它的 fps 与 CPU 变化）\n",
                self.selectedDecoders.lastObject.version];

            for (BenchStream *stream in self.selectedStreams) {
                NSMutableArray<BenchStreamResult *> *rows = [NSMutableArray array];
                for (BenchStreamResult *result in self.batchResults) {
                    if ([result.stream.name isEqualToString:stream.name]) {
                        [rows addObject:result];
                    }
                }
                if (rows.count < 2) continue;

                BenchSummary *baseline = rows.lastObject.summary;
                if (baseline.scoredCount == 0 || baseline.decodeFPS <= 0) continue;

                // 不写码流名：同一批测试条件对齐，读者只需要看版本之间的差异。
                // 只有真的勾了多个码流时才标出来，否则同名两段无法区分。
                if (self.batchStreamCount > 1) {
                    [text appendFormat:@"\n--- %@ ---\n", rows.lastObject.streamDisplayName];
                } else {
                    [text appendString:@"\n"];
                }
                appendPadded(@"版本", 10);
                appendPadded(@"fps", 9);
                appendPadded(@"fps变化", 11);
                appendPadded(@"CPU%", 9);
                appendPadded(@"CPU变化", 11);
                appendPadded(@"ms/f", 9);
                [text appendString:@"\n"];

                for (BenchStreamResult *result in rows) {
                    BenchSummary *s = result.summary;
                    if (s.scoredCount == 0) continue;
                    const double fpsDelta = (s.decodeFPS / baseline.decodeFPS - 1.0) * 100.0;
                    NSString *fpsChange = fabs(fpsDelta) < 0.05
                        ? @"持平" : [NSString stringWithFormat:@"%+.1f%%", fpsDelta];

                    // 任一侧无采样就不能算变化的百分比：
                    // 0 当分母已排除，0 当分子会得出「-100%」这种假结论。
                    NSString *cpuChange = @"--";
                    if (baseline.avgCPUSampled && s.avgCPUSampled
                        && baseline.cpuSharePercent > 0) {
                        const double cpuDelta =
                            (s.cpuSharePercent / baseline.cpuSharePercent - 1.0) * 100.0;
                        cpuChange = fabs(cpuDelta) < 0.05
                            ? @"持平" : [NSString stringWithFormat:@"%+.1f%%", cpuDelta];
                    }

                    appendPadded(result.decoderDisplayName, 10);
                    appendPadded([NSString stringWithFormat:@"%.2f", s.decodeFPS], 9);
                    appendPadded(fpsChange, 11);
                    appendPadded(s.avgCPUSampled
                                 ? [NSString stringWithFormat:@"%.2f", s.cpuSharePercent] : @"--", 9);
                    appendPadded(cpuChange, 11);
                    appendPadded([NSString stringWithFormat:@"%.3f", s.avgFrameMs], 9);
                    [text appendString:@"\n"];
                }
            }
            [text appendString:@"\n（fps 越高越好，CPU% 越低越好；变化幅度在测量波动内即为持平；-- 表示无有效采样）\n"];
        }

        [text appendString:@"\n---------- 逐组合明细 ----------\n"];
        for (BenchStreamResult *result in self.batchResults) {
            // 不写码流名：同一批测试条件对齐，读者只需要区分版本。
            // 多码流导致同名重复时，用序号标记到与上表一致。
            NSUInteger sameNameCount = 0;
            for (BenchStreamResult *other in self.batchResults) {
                if ([other.decoderDisplayName isEqualToString:result.decoderDisplayName]) {
                    sameNameCount++;
                }
            }
            NSString *detailTitle = result.decoderDisplayName;
            if (sameNameCount > 1) {
                NSUInteger ordinal = 0;
                for (BenchStreamResult *other in self.batchResults) {
                    if (other == result) break;
                    if ([other.decoderDisplayName isEqualToString:result.decoderDisplayName]) {
                        ordinal++;
                    }
                }
                detailTitle = [NSString stringWithFormat:@"%@ #%lu",
                               result.decoderDisplayName, (unsigned long)(ordinal + 1)];
            }
            [text appendFormat:@"\n--- %@ ---\n", detailTitle];
            BenchSummary *s = result.summary;
            [text appendFormat:@"单帧 %.4f ms  P95 %.4f ms  fps %.2f  %@\n",
                s.avgFrameMs,
                result.rounds.lastObject.p95FrameMs,
                s.decodeFPS,
                result.rounds.lastObject.resolutionDescription];
            [text appendFormat:@"CPU 整机 %@\n",
                s.avgCPUSampled
                    ? [NSString stringWithFormat:@"%.1f%% = %.0f%% 单核口径 = %.2f 核",
                       s.cpuSharePercent, s.avgCPUPercent, s.avgCPUCores]
                    : @"无采样"];
            [text appendFormat:@"波动 %.2f%%（轮间标准差 %.4f ms）\n",
                s.fluctuationPercent, s.stddevFrameMs];
            [text appendFormat:@"净内存 %@\n",
                s.memorySampled
                    ? [NSString stringWithFormat:@"%.1f MB（峰值 %.1f MB，resident 峰 %.1f MB）",
                       s.footprintDeltaMB, s.peakFootprintMB, s.peakResidentMB]
                    : @"无采样"];
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
    // 数值输入框改完会直接影响批量规模，刷新折叠区摘要时无需额外处理；
    // 解码器已改为多选行，不再经过这里。
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
    append(@"可用解码器 %lu 个，已选 %lu 个",
           (unsigned long)self.decoders.count, (unsigned long)self.selectedDecoders.count);

    // 自测默认全选，才能覆盖多码流批量与对比表路径
    if ([[NSProcessInfo processInfo].arguments containsObject:@"--all-streams"]) {
        self.selectedStreams = [self.streams mutableCopy];
        [self refreshStreamPickerDisplay];
        append(@"已全选 %lu 个码流", (unsigned long)self.selectedStreams.count);
    }

    // --all-decoders 用来验证多版本同测这条新路径：
    // 一个 App 内同时加载多个 dylib，逐一跑同一码流并出对比表。
    if ([[NSProcessInfo processInfo].arguments containsObject:@"--all-decoders"]) {
        [self.selectedDecoders removeAllObjects];
        for (BenchDecoder *decoder in self.decoders) {
            // 这里不能再用 isUsable 过滤：扫描阶段没有 dlopen，全部都是未加载状态。
            // 直接全选，由引擎开跑时逐个加载；加载失败的组合会被记进
            // failedStreamNames，反而能覆盖「某个库坏了」这种情况。
            [self.selectedDecoders addObject:decoder];
        }
        [self refreshDecoderPickerDisplay];
        append(@"已全选 %lu 个解码器", (unsigned long)self.selectedDecoders.count);
    }

    if (self.selectedStreams.count == 0) {
        append(@"失败：没有选中码流");
        [self writeSelfTestLog:log];
        return;
    }
    if (self.selectedDecoders.count == 0) {
        append(@"失败：没有可用的解码器动态库");
        for (BenchDecoder *decoder in self.decoders) {
            append(@"  %@ -> %@", decoder.version, decoder.loadError ?: @"可用");
        }
        [self writeSelfTestLog:log];
        return;
    }

    // 自测按住真实路径走：直接驱动批量队列，验证多码流串联与结果渲染
    NSArray<NSString *> *args = [NSProcessInfo processInfo].arguments;
    NSUInteger framesIndex = [args indexOfObject:@"--frames"];
    NSUInteger threadsIndex = [args indexOfObject:@"--threads"];
    NSUInteger policyIndex = [args indexOfObject:@"--policy"];
    NSUInteger roundsIndex = [args indexOfObject:@"--rounds"];

    [self.batchResults removeAllObjects];
    [self.failedStreamNames removeAllObjects];
    [self.pendingCombinations removeAllObjects];
    self.batchCancelled = NO;
    self.batchDecoderCount = self.selectedDecoders.count;
    self.batchStreamCount = self.selectedStreams.count;

    // 与 startButtonTapped 保持完全一致的展开顺序，避免自测走一条
    // 生产代码不会走的路径，导致验证结论与实际行为脱节。
    for (BenchDecoder *decoder in self.selectedDecoders) {
        for (BenchStream *stream in self.selectedStreams) {
            [self.pendingCombinations addObject:@{@"decoder": decoder, @"stream": stream}];
        }
    }
    self.batchTotal = self.pendingCombinations.count;

    // 自测固定用轻量参数，避免真机上跑太久
    self.framesField.textField.text = framesIndex != NSNotFound && framesIndex + 1 < args.count
        ? args[framesIndex + 1] : @"200";
    // 轮次同样可覆盖：短跑验证用默认 2 轮，稳定性对比需要更多轮次
    self.roundsField.textField.text = roundsIndex != NSNotFound && roundsIndex + 1 < args.count
        ? args[roundsIndex + 1] : @"2";
    self.warmupField.textField.text = @"1";
    // 线程数直接采用命令行原值，不再反查分段索引。
    // 旧实现用 @[@0,@1,@2,@4,@8] 反查，--threads 6 这类非档位值会 indexOfObject
    // 返回 NSNotFound 而被丢弃，线程数静默落回默认值，看起来就是「命令行改不了线程」。
    if (threadsIndex != NSNotFound && threadsIndex + 1 < args.count) {
        self.threadsOverride = MAX((NSInteger)[args[threadsIndex + 1] integerValue], 0);
        // 若恰好是档位值，顺手同步界面，方便截图与人工核对；
        // 非档位值不同步，避免把界面显示成错误的档位。
        NSArray<NSNumber *> *mapping = @[@0, @1, @2, @4, @8];
        NSUInteger segment = [mapping indexOfObject:@(self.threadsOverride)];
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
    // 0 是「自动」而不是「指定 0 个线程」：配置层把 0 解释为让库按核心数取满，
    // 所以这里单独判 0，避免日志写出「0（命令行指定）」这种自相矛盾的说法。
    if (self.threadsOverride > 0) {
        append(@"线程数：%ld（命令行指定）", (long)self.threadsOverride);
    } else if (self.threadsOverride == 0) {
        append(@"线程数：自动（按逻辑核数取满）");
    } else {
        append(@"线程数：自动（库默认）");
    }
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

        if (self.engine.isRunning || self.pendingCombinations.count > 0) {
            [self pollSelfTestUntilFinished:log append:append];
            return;
        }

        for (BenchStreamResult *result in self.batchResults) {
            append(@"--- %@ ---", result.displayName);
            for (BenchRoundMetrics *r in result.rounds) {
                NSString *cpuText = r.cpuSampled
                    ? [NSString stringWithFormat:@"CPU %.1f%% (%.2f 核, 峰 %.1f%%%@)",
                       r.avgCPUPercent, r.avgCPUCores, r.peakCPUPercent,
                       r.peakCPUSampled ? @"" : @", 峰为估算"]
                    : @"CPU 无采样";
                NSString *memText = r.memorySampled
                    ? [NSString stringWithFormat:@"基线 FP %.1f MB  峰值 FP %.1f MB  净 %.1f MB  RSS峰 %.1f MB",
                       r.baselineFootprintMB, r.peakFootprintMB, r.footprintDeltaMB,
                       r.peakResidentMB]
                    : @"内存 无采样";
                append(@"  #%lu %@ %.4f ms/f  P95 %.4f  %@  %@  %@",
                       (unsigned long)r.index,
                       r.isWarmup ? @"[预热]" : @"[正式]",
                       r.avgFrameMs, r.p95FrameMs,
                       cpuText, memText, r.resolutionDescription);
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




