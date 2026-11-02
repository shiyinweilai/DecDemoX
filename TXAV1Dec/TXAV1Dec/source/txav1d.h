//
//  txav1d.h
//  TXAV1Dec
//
//  Created by 又贵又不好用的MacBookPro on 2022/12/6.
//

#ifndef txav1d_h
#define txav1d_h
#import <Foundation/Foundation.h>

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MyPickerView : UIView<UIPickerViewDelegate, UIPickerViewDataSource>

@property (nonatomic, strong) UIPickerView *pickerView;  //选择器
@property (nonatomic, strong) UIButton *sureButton;  //确认按钮
@property (nonatomic, strong) NSString *opt;  //最终的时间
@property (nonatomic, strong) NSArray *option;  //最终的时间

//判断是否要显示视图
- (void)isShowOnView:(BOOL)select;

@end

NS_ASSUME_NONNULL_END



#endif /* txav1d_h */
