//
//  txav1d.m
//  TXAV1Dec
//
//  Created by 又贵又不好用的MacBookPro on 2022/12/6.
//

#import "txav1d.h"

#define ScreenWidth [UIScreen mainScreen].bounds.size.width
#define ScreenHeight [UIScreen mainScreen].bounds.size.height

@implementation MyPickerView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    
    //初始化数据
    [self p_initData];
    
    //初始化选择器
    [self p_initPickerView];
    
    return self;
}

//初始化选择器
- (void)p_initPickerView {
    //自定义选择器
    self.pickerView = [[UIPickerView alloc] initWithFrame:CGRectNull];
    self.pickerView.delegate = self;
    self.pickerView.dataSource = self;
    [self addSubview:self.pickerView];
    
    self.option = [NSArray arrayWithObjects:@"test1.stream", @"test2.stream", @"test3.stream", @"avif1.stream",@"avif2.stream",@"avif3.stream", nil];
}

//返回显示的列数
- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView {
    return 1;
}

//返回每一列中需要显示的行数
- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component {
    return [self.option count];
}

//返回每一列的宽度
- (CGFloat)pickerView:(UIPickerView *)pickerView widthForComponent:(NSInteger)component {
        return 200;
}

//返回每一列的高度
- (CGFloat)pickerView:(UIPickerView *)pickerView rowHeightForComponent:(NSInteger)component {
    return 40;
}

//返回UIPickerView控件中指定列的列表项的要显示的内容
- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component {
    @autoreleasepool {
        self.opt =self.option[row];
        return self.option[row];
    }
}

//初始化数据
- (void)p_initData {
//    self.opt = [[NSString alloc] init];
    self.opt = @"";
    self.pickerView.frame = CGRectMake(0, 30, ScreenWidth, 230);

}

//判断是否要显示在视图上
- (void)isShowOnView:(BOOL)select {
    if (select) {
        self.pickerView.frame = CGRectMake(0, 30, ScreenWidth, 230);
    } else {
        self.pickerView.frame = CGRectNull;
    }
}

@end

