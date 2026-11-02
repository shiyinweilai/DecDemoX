//
//  ViewController.m
//  TXAV1Dec
//
//  Created by 又贵又不好用的MacBookPro on 2022/12/6.
//

#import "ViewController.h"
#import "txav1d_core.h"
#import "source/txav1d.h"

#define ScreenWidth [UIScreen mainScreen].bounds.size.width
#define ScreenHeight [UIScreen mainScreen].bounds.size.height

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UITextField *cmd;
@property (strong, nonatomic) IBOutlet UITextField *spf;
@property (weak, nonatomic) IBOutlet UITextField *frames;

@property (nonatomic, strong) IBOutlet UIButton *lanuch;
@property (strong, nonatomic) IBOutlet UITextField *epoch;
@property (strong, nonatomic) IBOutlet UITextField *vp;




@property (nonatomic, strong) MyPickerView *timeSelectView;
@property (nonatomic, assign) float mspf;
@property (nonatomic, assign) int clickCnt;

@end

@implementation ViewController

@synthesize mspf;

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.

    self.timeSelectView = [[MyPickerView alloc] initWithFrame:CGRectZero];
    self.timeSelectView.frame = CGRectMake(0, self.frames.frame.origin.y + 200, ScreenWidth, ScreenHeight - 400);
    [self.timeSelectView isShowOnView:YES];
    [self.view addSubview:self.timeSelectView];
    
    self.epoch.keyboardType = UIKeyboardTypeNumberPad;
    self.frames.keyboardType = UIKeyboardTypeNumberPad;
    self.clickCnt = 0;
}

- (IBAction)lanuch:(id)sender {
//    
//    if([self.cmd.text  isEqual: @""]){
//        self.cmd.text =@"test.stream";
//    }else{
//        self.cmd.text =self.timeSelectView.opt;
//    }
    self.cmd.text =self.timeSelectView.opt;

    if([self.frames.text  isEqual: @""]){
        self.frames.text = @"1";
    }
    
    if([self.epoch.text isEqual:@""]){
        self.epoch.text = @"1";
    }
    
    
    NSArray *PathArray = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *FilePath = [[PathArray firstObject] stringByAppendingString:[NSString stringWithFormat:@"%s%@", "/", self.cmd.text]];
    
    self.clickCnt += 1;
    
    if([self.epoch.text isEqual:@"1"]){
        [self decode :FilePath :self.frames.text];
        self.vp.text = [NSString stringWithFormat:@"%f", self.mspf];
    }else{
        int epoch = [self.epoch.text intValue];
        float totalTime = 0.0;
        float *timeArr = (float *)malloc(epoch * sizeof(float));
        
        for (int e = 0; e < epoch + 3; e++) {
            [self decode :FilePath :self.frames.text];
            if (e > 2) {
                timeArr[e - 3] = self.mspf;
                totalTime += self.mspf;
            }
        }
        float avgMspf = totalTime / epoch;

        
        float deltaMspf = 0.0;
        float totalDeltaMspf = 0.0;
        float avgDeltaMspf = 0.0;
        for (int idx = 0; idx < epoch; idx++) {
            deltaMspf = timeArr[idx] - avgMspf;
            totalDeltaMspf += deltaMspf;
            NSLog(@"%d    %.4f ms/f    波动 %.4f ms/f",idx, timeArr[idx], deltaMspf);
        }
        avgDeltaMspf = totalDeltaMspf / epoch;
        self.vp.text = [NSString stringWithFormat:@"%f", avgDeltaMspf];
    }
    

    
    [self.view endEditing:YES];

}

-(void)decode :(NSString *)inputFile :(NSString *)frame{

    int argc = 8;
    char **argv = (char**)malloc(argc * sizeof(char*));
    if(argv != NULL)
    {
        //        argv[0] = "ffmpeg";
        argv[1] = (char *)[@"-i" UTF8String];
        argv[2] = (char *)[inputFile UTF8String];
        argv[3] = (char *)[@"--muxer" UTF8String];
        argv[4] = (char *)[@"null" UTF8String];
        argv[5] = (char *)[@"--limit" UTF8String];
        argv[6] = (char *)[frame UTF8String];
        argv[7] = (char *)[@"--quiet" UTF8String];
//        argv[7] = (char *)[@"" UTF8String];
        
        CFTimeInterval start1 = CACurrentMediaTime();
        int totalFrames = txav1d_lanuch(argc, argv);
        CFTimeInterval end1 = CACurrentMediaTime();
        NSString *cost = [NSString stringWithFormat:@"%@", @((end1 - start1)*1000)];
        float time = [cost floatValue];
        int frameToDecoder = [self.frames.text intValue];
        mspf = 0.0;
        int frameCnt = 0;
        if (frameToDecoder > totalFrames) {
            frameCnt = totalFrames;
        }else{
            frameCnt = frameToDecoder;
        }
        mspf = time / frameCnt;

//        NSString *ret = [NSString stringWithFormat:@"%@", [time substringWithRange:{0, 8}]];
        NSString *ret = [NSString stringWithFormat:@"%.4f   %s", mspf, "ms/f"];
        self.spf.text = ret;
        NSLog(@"总耗时/总帧数 %.4f / %d    单帧耗时 %.4f ms/f", time, frameCnt, mspf);
    }
}

@end
