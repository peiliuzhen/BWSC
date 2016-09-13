//
//  ViewController.m
//  kxmovieapp
//
//  Created by Kolyvan on 11.10.12.
//  Copyright (c) 2012 Konstantin Boukreev . All rights reserved.
//
//  https://github.com/kolyvan/kxmovie
//  this file is part of KxMovie
//  KxMovie is licenced under the LGPL v3, see lgpl-3.0.txt

#import "KxMovieViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <QuartzCore/QuartzCore.h>
#import "KxMovieDecoder.h"
#import "KxAudioManager.h"
#import "KxMovieGLView.h"
#import "AppDelegate.h"
#include "bw_encode.h"
#import "LrdOutputView.h"
#import "ProgramModel.h"
#import "getgateway.h"
#import <arpa/inet.h>
#import <netdb.h>
#import <netinet/in.h>
#import <netinet6/in6.h>
#import <ifaddrs.h>
#import <SystemConfiguration/SCNetworkReachability.h>
#include <sys/socket.h>



// 枚举值，包含水平移动方向和垂直移动方向
typedef NS_ENUM(NSInteger, PanDirection){
    PanDirectionHorizontalMoved, // 横向移动
    PanDirectionVerticalMoved    // 纵向移动
};

NSString * const KxMovieParameterMinBufferedDuration = @"KxMovieParameterMinBufferedDuration";
NSString * const KxMovieParameterMaxBufferedDuration = @"KxMovieParameterMaxBufferedDuration";
NSString * const KxMovieParameterDisableDeinterlacing = @"KxMovieParameterDisableDeinterlacing";

////////////////////////////////////////////////////////////////


static NSString * formatTimeInterval(CGFloat seconds, BOOL isLeft)
{
    seconds = MAX(0, seconds);
    
    NSInteger s = seconds;
    NSInteger m = s / 60;
    NSInteger h = m / 60;
    
    s = s % 60;
    m = m % 60;
    
    return [NSString stringWithFormat:@"%@%d:%0.2d:%0.2d", isLeft ? @"-" : @"", h,m,s];
}

////////////////////////////////////////////////////////////////////////////////

@interface HudView : UIView
@end

@implementation HudView

- (void)layoutSubviews
{
    NSArray * layers = self.layer.sublayers;
    if (layers.count > 0) {        
        CALayer *layer = layers[0];
        layer.frame = self.bounds;
    }
}
@end

////////////////////////////////////////////////////////////////////////////////

enum {

    KxMovieInfoSectionGeneral,
    KxMovieInfoSectionVideo,
    KxMovieInfoSectionAudio,
    KxMovieInfoSectionSubtitles,
    KxMovieInfoSectionMetadata,    
    KxMovieInfoSectionCount,
};

enum {

    KxMovieInfoGeneralFormat,
    KxMovieInfoGeneralBitrate,
    KxMovieInfoGeneralCount,
};

typedef enum : NSUInteger {
    HCDPlayerControlTypeProgress,
    HCDPlayerControlTypeVoice,
    HCDPlayerControlTypeLight,
    HCDPlayerControlTypeNone = 999,
} HCDPlayerControlType;

////////////////////////////////////////////////////////////////////////////////

static NSMutableDictionary * gHistory;

#define LOCAL_MIN_BUFFERED_DURATION   0.2
#define LOCAL_MAX_BUFFERED_DURATION   0.4
#define NETWORK_MIN_BUFFERED_DURATION 2.0
#define NETWORK_MAX_BUFFERED_DURATION 4.0

#define LeastMoveDistance 15
#define TotalScreenTime 90

@interface KxMovieViewController ()<UIGestureRecognizerDelegate,LrdOutputViewDelegate,UITableViewDelegate,UITableViewDataSource> {

    UIBackgroundTaskIdentifier backgroundTask; //用来保存后台运行任务的标示符
    KxMovieDecoder      *_decoder;    
    dispatch_queue_t    _dispatchQueue;
    NSMutableArray      *_videoFrames;
    NSMutableArray      *_audioFrames;
    NSMutableArray      *_subtitles;
    NSData              *_currentAudioFrame;
    NSUInteger          _currentAudioFramePos;
    CGFloat             _moviePosition;
    BOOL                _disableUpdateHUD;
    NSTimeInterval      _tickCorrectionTime;
    NSTimeInterval      _tickCorrectionPosition;
    NSUInteger          _tickCounter;
    BOOL                _fullscreen;
    BOOL                _hiddenHUD;
    BOOL                _fitMode;
    BOOL                _infoMode;
    BOOL                _restoreIdleTimer;
    BOOL                _interrupted;
    
    KxMovieGLView       *_glView;
    UIImageView         *_imageView;
    HudView             *_topHUD;
    UIView              *_bottomHUD;
    UISlider            *_progressSlider;
    MPVolumeView        *_volumeSlider;
    UIButton            *_playButton;
    UIButton            *_rewindButton;
    UIButton            *_forwardButton;
    UIButton            *_doneButton;
    UIView              *_popView;
    UILabel             *_nameLabel;
    UILabel             *_progressLabel;
    UILabel             *_freLabel;
    UILabel             *_leftLabel;
    UIButton            *_infoButton;
    UITableView         *_tableView;
    UIActivityIndicatorView *_activityIndicatorView;
    UIView              *_backView;
    UILabel             *_loadLabel;
    UILabel             *_subtitlesLabel;
    UITableView         *_showTableView;
    
    UITapGestureRecognizer *_tapGestureRecognizer;
    UITapGestureRecognizer *_doubleTapGestureRecognizer;
    UIPanGestureRecognizer *_panGestureRecognizer;
        
#ifdef DEBUG
    UILabel             *_messageLabel;
    NSTimeInterval       _debugStartTime;
    NSUInteger           _debugAudioStatus;
    NSDate              *_debugAudioStatusTS;
#endif

    CGFloat              _bufferedDuration;
    CGFloat              _minBufferedDuration;
    CGFloat              _maxBufferedDuration;
    BOOL                 _buffered;
    BOOL                 _savedIdleTimer;
    NSDictionary        *_parameters;
    
    //节目信息model
    ProgramModel *model;
    //当前节目名称
    NSString *curretName;
    
    //心跳连续返回status＝2的次数
    NSInteger stateNum;
    
    UIInterfaceOrientation _currentOrientation;
    //触摸起点
    CGPoint locationPoint;
    //用来控制上下菜单view隐藏的timer
    NSTimer * _hiddenTimer;
    //用来判断手势是否移动过
    BOOL _hasMoved;
    //判断是否已经判断出手势划的方向
    BOOL _controlJudge;
    //触摸开始触碰到的点
    CGPoint _touchBeginPoint;
    //记录触摸开始时的视频播放的时间
    float _touchBeginValue;
    //记录触摸开始亮度
    float _touchBeginLightValue;
    //记录触摸开始的音量
    float _touchBeginVoiceValue;
}

@property (readwrite) BOOL                    playing;
@property (readwrite) BOOL                    decoding;
@property (nonatomic, strong)UIButton        *showButton;
@property (nonatomic ,strong)UIView          *frameView;
@property (readwrite, strong) KxArtworkFrame *artworkFrame;
@property (nonatomic, strong) UILabel        *horizontalLabel; // 水平滑动时显示进度

@property (nonatomic ,strong)NSMutableArray  *numArr;
@property (nonatomic ,strong)NSMutableDictionary *numDict;
@property (assign, nonatomic) NSInteger       subscript;    //数组下标，记录当前播放视频
@property (nonatomic ,copy)NSString          *str;
@property (nonatomic, strong) NSMutableArray *dataArr;
@property (nonatomic, strong) NSMutableArray *titleArr;
@property (nonatomic, strong) LrdOutputView  *outputView;

@property (nonatomic ,copy)NSString          *updateID;
//路由器地址
//@property (nonatomic ,copy)NSString          *routerIP;
@property (nonatomic ,copy)NSString          *baseUrl;
/** 是否在调节音量*/
@property (nonatomic, assign) BOOL            isVolume;
/** 滑杆 */
@property (nonatomic, strong) UISlider       *volumeViewSlider;
/** 定义一个实例变量，保存枚举值 */
@property (nonatomic, assign) PanDirection    panDirection;
/** 进入后台*/
@property (nonatomic, assign) BOOL            didEnterBackground;

@property (nonatomic , strong)NSTimer        *timer;

@property (nonatomic, strong) UISwipeGestureRecognizer *leftSwipeGestureRecognizer;
@property (nonatomic ,assign)NSInteger        intervals;//时间间隔

@property (nonatomic) BOOL                    statusBarIsHidden;//状态栏显示状态
@property (nonatomic, assign) HCDPlayerControlType controlType;//当前手势是在控制进度、声音还是亮度

@end

@implementation KxMovieViewController

//programinfo programm;
//
//extern programinfo *pinfo;

+ (void)initialize
{
    if (!gHistory)
        gHistory = [NSMutableDictionary dictionary];
}

+ (id) movieViewControllerWithContentPath: (NSString *) path
                               parameters: (NSDictionary *) parameters
{    
    id<KxAudioManager> audioManager = [KxAudioManager audioManager];
    [audioManager activateAudioSession];    
    return [[KxMovieViewController alloc] initWithContentPath: path parameters: parameters];
}



- (id) initWithContentPath: (NSString *) path
                parameters: (NSDictionary *) parameters
{
    NSAssert(path.length > 0, @"empty path");
    
    self = [super initWithNibName:nil bundle:nil];
    
    if (self) {
        
        //app运行时禁止自动锁屏
        [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
        
        UIDeviceOrientation orientation = [[UIDevice currentDevice] orientation];
        switch (orientation) {
            case UIDeviceOrientationPortrait:
                _currentOrientation = UIInterfaceOrientationPortrait;
                break;
            case UIDeviceOrientationLandscapeLeft:
                _currentOrientation = UIInterfaceOrientationLandscapeLeft;
                break;
            case UIDeviceOrientationLandscapeRight:
                _currentOrientation = UIInterfaceOrientationLandscapeRight;
                break;
            case UIDeviceOrientationPortraitUpsideDown:
                _currentOrientation = UIInterfaceOrientationPortraitUpsideDown;
                break;
            default:
                break;
        }
        
        // 获取系统音量
        [self configureVolume];
        
        _moviePosition = 0;

        self.edgesForExtendedLayout = UIRectEdgeNone;
        
        _parameters = parameters;
        
        __weak KxMovieViewController *weakSelf = self;
        
        KxMovieDecoder *decoder = [[KxMovieDecoder alloc] init];
        
        decoder.interruptCallback = ^BOOL(){
            
            __strong KxMovieViewController *strongSelf = weakSelf;
            return strongSelf ? [strongSelf interruptDecoder] : YES;
        };
        
        dispatch_async(dispatch_get_global_queue(0, 0), ^{
            
            NSError *error = nil;
            [decoder openFile:path error:&error];
                        
            __strong KxMovieViewController *strongSelf = weakSelf;
            if (strongSelf) {
                
                dispatch_sync(dispatch_get_main_queue(), ^{
                    
                    [strongSelf setMovieDecoder:decoder withError:error];                    
                });
            }
        });
    }
    return self;
}


- (void) dealloc
{
    
    [self pause];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if (_dispatchQueue) {
        _dispatchQueue = NULL;
    }
    
    self.view=nil;
    
    self.timer=nil;
    
    DLog(@"%@ dealloc", self);
}

- (void)loadView
{

    //[UIApplication sharedApplication].statusBarHidden=NO;
    
     self.statusBarIsHidden = NO;
    
    CGRect bounds = [[UIScreen mainScreen] applicationFrame];
    
    self.view = [[UIView alloc] initWithFrame:bounds];
    self.view.backgroundColor = [UIColor blackColor];
    
     //提示背景图
    _backView= [[UIView alloc] initWithFrame:CGRectMake(0, 0, 100, 60)];
    
    [_backView setBackgroundColor:[UIColor clearColor]];
    [self.view addSubview:_backView];
    
    [_backView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.mas_equalTo(self.view.mas_centerX);
        make.centerY.equalTo(self.view.mas_centerY).offset(0);
        make.width.mas_equalTo(100);
        make.height.mas_equalTo(60);
    }];
    
    //
    _activityIndicatorView = [[UIActivityIndicatorView alloc]initWithFrame:CGRectMake(0, 0, 100, 37)];
    [_activityIndicatorView setActivityIndicatorViewStyle:UIActivityIndicatorViewStyleWhiteLarge];
    //_activityIndicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle: UIActivityIndicatorViewStyleWhiteLarge];
    
    _loadLabel=[[UILabel alloc]initWithFrame:CGRectMake(0, 40, 100, 20)];
    _loadLabel.text=@"Loading...";
    _loadLabel.font=[UIFont systemFontOfSize:13.0f];
    _loadLabel.textColor=RGBA_MD(255, 255, 255, 0.8);
    _loadLabel.textAlignment=NSTextAlignmentCenter;
   
    [_backView addSubview:_activityIndicatorView];
    [_backView addSubview:_loadLabel];
    
    _backView.hidden=YES;
    
    CGFloat width = bounds.size.width;
    CGFloat height = bounds.size.height;
    
#ifdef DEBUG
   
#endif
    
    _topHUD      = [[HudView alloc] initWithFrame:CGRectMake(0,0,0,0)];
    _bottomHUD   = [[UIView alloc] initWithFrame:CGRectMake(0,0,0,0)];
    _topHUD.opaque = NO;
    _bottomHUD.opaque = NO;
    _topHUD.frame = CGRectMake(0,0,width,30);
    //显示底部信息
    _bottomHUD.frame = CGRectMake(0,height-60,width,60);
    
//    _topHUD.autoresizingMask = UIViewAutoresizingFlexibleWidth;
//    
//    _bottomHUD.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleLeftMargin;
    
    [self.view addSubview:_topHUD];
    [self.view addSubview:_bottomHUD];
    
    [_topHUD mas_makeConstraints:^(MASConstraintMaker *make) {
        
        make.left.mas_equalTo(0);
        make.right.mas_equalTo(0);
        make.top.equalTo(self.view.mas_top).offset(0);
        make.height.mas_equalTo(50);
        
    }];

    
    [_bottomHUD mas_makeConstraints:^(MASConstraintMaker *make) {
        
        make.left.mas_equalTo(0);
        make.right.mas_equalTo(0);
        make.bottom.mas_equalTo(0);
        make.height.mas_equalTo(60);
        
    }];
    
    // top hud
    
    _doneButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _doneButton.frame = CGRectMake(0,20,60,30);
    _doneButton.backgroundColor = [UIColor clearColor];
    [_doneButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_doneButton setImage:[UIImage imageNamed:@"back"] forState:UIControlStateNormal];
    [_doneButton setTitle:@"      " forState:UIControlStateNormal];
    _doneButton.titleLabel.font = [UIFont systemFontOfSize:18];
    _doneButton.showsTouchWhenHighlighted = YES;
    [_doneButton addTarget:self action:@selector(doneDidTouch:) forControlEvents:UIControlEventTouchUpInside];
    
     _nameLabel= [[UILabel alloc] initWithFrame:CGRectMake(60,0,_topHUD.bounds.size.width-120,30)];
    _nameLabel.backgroundColor = [UIColor clearColor];
    _nameLabel.opaque = NO;
    _nameLabel.adjustsFontSizeToFitWidth = NO;
    _nameLabel.textAlignment = NSTextAlignmentCenter;
    _nameLabel.textColor = [UIColor whiteColor];
    _nameLabel.text = [NSString stringWithFormat:@"%@   频点:%@",_getName,_getFrequency];
    _nameLabel.font = [UIFont systemFontOfSize:15];
    
    _progressLabel = [[UILabel alloc] initWithFrame:CGRectMake(60,15,50,20)];
    _progressLabel.backgroundColor = [UIColor clearColor];
    _progressLabel.opaque = NO;
    _progressLabel.adjustsFontSizeToFitWidth = NO;
    _progressLabel.textAlignment = NSTextAlignmentCenter;
    _progressLabel.textColor = [UIColor whiteColor];
    _progressLabel.text = @"00:00:00";
    _progressLabel.font = [UIFont systemFontOfSize:12];
    
    _progressSlider = [[UISlider alloc] initWithFrame:CGRectMake(112,15,width-200,20)];
    
    _progressSlider.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _progressSlider.continuous = NO;
    _progressSlider.value = 0;
    [_progressSlider setThumbImage:[UIImage imageNamed:@"kxmovie.bundle/sliderthumb"]
                          forState:UIControlStateNormal];
    //滑动进度条触发的事件
    //[_progressSlider addTarget:self action:@selector(progressDidChange:) forControlEvents:UIControlEventValueChanged];
    
    _leftLabel = [[UILabel alloc] initWithFrame:CGRectMake(width-80,15,60,20)];
    _leftLabel.backgroundColor = [UIColor clearColor];
    _leftLabel.opaque = NO;
    _leftLabel.adjustsFontSizeToFitWidth = NO;
    _leftLabel.textAlignment=NSTextAlignmentLeft;
    _leftLabel.textColor = [UIColor whiteColor];
    _leftLabel.text = @"-99:59:59";
    _leftLabel.font = [UIFont systemFontOfSize:12];
   // _leftLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    
    _infoButton = [UIButton buttonWithType:UIButtonTypeInfoDark];
    _infoButton.frame = CGRectMake(width-25,25,20,20);
    _infoButton.showsTouchWhenHighlighted = YES;
    _infoButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_infoButton addTarget:self action:@selector(infoDidTouch:) forControlEvents:UIControlEventTouchUpInside];
    
    [_topHUD addSubview:_doneButton];
    [_topHUD addSubview:_infoButton];
    [_topHUD addSubview:_nameLabel];
    
    [_nameLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        
        make.left.mas_equalTo(60);
        make.right.mas_equalTo(-60);
        make.top.equalTo(_topHUD.mas_top).offset(20);
        make.height.mas_equalTo(30);
        
    }];
    
    // bottom hud
    width = _bottomHUD.bounds.size.width;
    
    _rewindButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _rewindButton.frame = CGRectMake(width * 0.5 - 65, 5, 40, 40);
    _rewindButton.backgroundColor = [UIColor clearColor];
    _rewindButton.showsTouchWhenHighlighted = YES;
    [_rewindButton setImage:[UIImage imageNamed:@"kxmovie.bundle/playback_rew"] forState:UIControlStateNormal];
    [_rewindButton addTarget:self action:@selector(rewindDidTouch:) forControlEvents:UIControlEventTouchUpInside];
    
    _playButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _playButton.frame = CGRectMake(10, 0, 50, 50);
    _playButton.backgroundColor = [UIColor clearColor];
    _playButton.showsTouchWhenHighlighted = YES;
    [_playButton setImage:[UIImage imageNamed:@"kxmovie.bundle/playback_play"] forState:UIControlStateNormal];
    [_playButton addTarget:self action:@selector(playDidTouch:) forControlEvents:UIControlEventTouchUpInside];
    
    _forwardButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _forwardButton.frame = CGRectMake(width * 0.5 + 25, 5, 40, 40);
    _forwardButton.backgroundColor = [UIColor clearColor];
    _forwardButton.showsTouchWhenHighlighted = YES;
    
    [_forwardButton setImage:[UIImage imageNamed:@"kxmovie.bundle/playback_ff"] forState:UIControlStateNormal];
    
    [_forwardButton addTarget:self action:@selector(forwardDidTouch:) forControlEvents:UIControlEventTouchUpInside];
    
    [_bottomHUD addSubview:_rewindButton];
    [_bottomHUD addSubview:_forwardButton];
    [_bottomHUD addSubview:_playButton];
    [_bottomHUD addSubview:_progressLabel];
    [_bottomHUD addSubview:_progressSlider];
    [_bottomHUD addSubview:_leftLabel];
    
    [_playButton mas_makeConstraints:^(MASConstraintMaker *make) {
        
        make.centerX.mas_equalTo(_bottomHUD.mas_centerX);
        make.bottom.equalTo(_bottomHUD.mas_bottom).offset(0);
        make.top.equalTo(_progressLabel.mas_bottom).offset(0);
        make.width.mas_equalTo(40);
        
    }];
    
    [_rewindButton mas_makeConstraints:^(MASConstraintMaker *make) {
        
        make.right.equalTo(_playButton.mas_left).offset(-20);
        make.bottom.equalTo(_bottomHUD.mas_bottom).offset(0);
        make.top.equalTo(_progressLabel.mas_bottom).offset(0);
        make.width.mas_equalTo(40);
        
    }];
    
    [_forwardButton mas_makeConstraints:^(MASConstraintMaker *make) {
        
        make.left.equalTo(_playButton.mas_right).offset(20);
        make.bottom.equalTo(_bottomHUD.mas_bottom).offset(0);
        make.top.equalTo(_progressLabel.mas_bottom).offset(0);
        make.width.mas_equalTo(40);
        
    }];
    //60,15,50,20
    [_progressLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        
        make.left.mas_equalTo(5);
        make.height.mas_equalTo(20);
        make.top.equalTo(_bottomHUD.mas_top).offset(5);
        make.width.mas_equalTo(60);
        
    }];
    //width-80,15,60,20
    [_leftLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        
        make.right.mas_equalTo(-5);
        make.left.equalTo(_progressSlider.mas_right).offset(5);
       make.height.mas_equalTo(20);
        make.top.equalTo(_bottomHUD.mas_top).offset(5);
        
    }];
    //112,15,width-200,20)
    [_progressSlider mas_makeConstraints:^(MASConstraintMaker *make) {
        
        make.right.equalTo(_leftLabel.mas_left).offset(-5);
        make.left.equalTo(_progressLabel.mas_right).offset(0);
        make.height.mas_equalTo(20);
        make.top.equalTo(_bottomHUD.mas_top).offset(5);
        
    }];
    
    _popView = [[UIView alloc]init];
    _popView.frame = CGRectMake(KScreenWidth-30, 50, 30, KScreenHeight-80);
    _popView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_popView];
    
    [_popView mas_makeConstraints:^(MASConstraintMaker *make) {
        
        make.right.mas_equalTo(0);
        make.width.mas_equalTo(50);
        make.bottom.mas_equalTo(0);
        make.top.mas_equalTo(30);
        
    }];
    
    _showButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _showButton.frame = CGRectMake(28, KScreenHeight/2-16-30, 2, 32);
    _showButton.backgroundColor = RGBA_MD(50, 180, 50, 0.8);
    _showButton.tintColor=[UIColor lightGrayColor];
    _showButton.showsTouchWhenHighlighted = YES;
    
    //[_showButton setImage:[UIImage imageNamed:@"left"] forState:UIControlStateNormal];
    //    [_showButton setTitle:@"电视节目" forState:UIControlStateNormal];
    //    _showButton.titleLabel.textAlignment=NSTextAlignmentCenter;
    
    [_showButton addTarget:self action:@selector(showProgramBtnDidTouch:) forControlEvents:UIControlEventTouchUpInside];

    //[_showButton setImage:[UIImage imageNamed:@"kxmovie.bundle/playback_ff"] forState:UIControlStateNormal];
    
    self.leftSwipeGestureRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(showProgramBtnDidTouch:)];
     self.leftSwipeGestureRecognizer.direction = UISwipeGestureRecognizerDirectionLeft;
     [_popView addGestureRecognizer:self.leftSwipeGestureRecognizer];
    
    [_popView addSubview:_showButton];
    
    //(28, KScreenHeight/2-16-30, 2, 32)
    [_showButton mas_makeConstraints:^(MASConstraintMaker *make) {
        
        make.right.equalTo(_popView.mas_right).offset(-2);
        make.width.mas_equalTo(2);
        make.height.mas_equalTo(32);
        make.centerY.equalTo(_popView.mas_centerY).offset(-16);
        
    }];

    // gradients
    
    CAGradientLayer *gradient;
    
    gradient = [CAGradientLayer layer];
    gradient.frame = _bottomHUD.bounds;
    gradient.cornerRadius = 5;
    gradient.masksToBounds = YES;
    gradient.borderColor = [UIColor darkGrayColor].CGColor;
    gradient.borderWidth = 1.0f;
    gradient.colors = [NSArray arrayWithObjects:
                       (id)[[UIColor whiteColor] colorWithAlphaComponent:0.3].CGColor,
                       (id)[[UIColor lightGrayColor] colorWithAlphaComponent:0.3].CGColor,
                       (id)[[UIColor darkGrayColor] colorWithAlphaComponent:0.3].CGColor,
                       (id)[[UIColor blackColor] colorWithAlphaComponent:0.5].CGColor,
                       nil];
    
    gradient.locations = [NSArray arrayWithObjects:
                          [NSNumber numberWithFloat:0.0f],
                          [NSNumber numberWithFloat:0.1f],
                          [NSNumber numberWithFloat:0.5],
                          [NSNumber numberWithFloat:0.9],
                          nil];
    
    [_bottomHUD.layer insertSublayer:gradient atIndex:0];

    gradient = [CAGradientLayer layer];
    
    gradient.frame = _topHUD.bounds;
    
    gradient.colors = [NSArray arrayWithObjects:
                       (id)[[UIColor lightGrayColor] colorWithAlphaComponent:0.6].CGColor,
                       (id)[[UIColor darkGrayColor] colorWithAlphaComponent:0.6].CGColor,
                       nil];
    
    gradient.locations = [NSArray arrayWithObjects:
                          [NSNumber numberWithFloat:0.0f],
                          [NSNumber numberWithFloat:0.5],
                          nil];
    [_topHUD.layer insertSublayer:gradient atIndex:0];
    
    if (_decoder) {
        
        [self setupPresentView];
        
    } else {
        
       // _bottomHUD.hidden = YES;
        _progressLabel.hidden = YES;
        _progressSlider.hidden = YES;
        _leftLabel.hidden = YES;
        _infoButton.hidden = YES;
    }
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    
    if (self.playing) {
        
        [self pause];
        [self freeBufferedFrames];
        
        if (_maxBufferedDuration > 0) {
            
            _minBufferedDuration = _maxBufferedDuration = 0;
            [self play];
            
            DLog(@"didReceiveMemoryWarning, disable buffering and continue playing");
            
        } else {
            
            [_decoder closeFile];
            [_decoder openFile:nil error:nil];
            
            [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Failure", nil)
                                        message:NSLocalizedString(@"Out of memory", nil)
                                       delegate:nil
                              cancelButtonTitle:NSLocalizedString(@"Close", nil)
                              otherButtonTitles:nil] show];
        }
        
    } else {
        
        [self freeBufferedFrames];
        [_decoder closeFile];
        [_decoder openFile:nil error:nil];
        
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Failure", nil)
                                    message:NSLocalizedString(@"Out of memory", nil)
                                   delegate:nil
                          cancelButtonTitle:NSLocalizedString(@"Close", nil)
                          otherButtonTitles:nil] show];

    }
}

- (void) viewDidAppear:(BOOL)animated
{
    // NSLog(@"viewDidAppear");
    
    [super viewDidAppear:animated];
        
    if (self.presentingViewController)
        [self fullscreenMode:YES];
    
    if (_infoMode)
        [self showInfoView:NO animated:NO];
    
    _savedIdleTimer = [[UIApplication sharedApplication] isIdleTimerDisabled];
    
    if (_decoder) {
        
        [self restorePlay];
        
    } else {
        
         _backView.hidden=NO;
        
        [_activityIndicatorView startAnimating];
        
        //[self performSelector:@selector(isPopView) withObject:nil afterDelay:5];
        
    }
   
}

- (void)setStatusBarHidden:(BOOL)hidden
{
    self.statusBarIsHidden = hidden;
    
    [self setNeedsStatusBarAppearanceUpdate];
    [[UIApplication sharedApplication] setStatusBarHidden:hidden withAnimation:UIStatusBarAnimationSlide];
}


//隐藏状态栏－－
- (UIStatusBarStyle)preferredStatusBarStyle
{
    //return UIStatusBarStyleDefault;
    //UIStatusBarStyleDefault = 0 黑色文字，浅色背景时使用
    return UIStatusBarStyleLightContent; //白色文字，深色背景时使用
}

- (BOOL)prefersStatusBarHidden
{
    return _statusBarIsHidden; // 返回NO表示要显示，返回YES将hiden
}

- (UIStatusBarAnimation)preferredStatusBarUpdateAnimation
{
    return UIStatusBarAnimationSlide;
}

-(void)viewWillAppear:(BOOL)animated{
    
    [super viewWillAppear:animated];
    
    [self setNeedsStatusBarAppearanceUpdate];
    
    stateNum=0;
    
    self.intervals=1.5;
    
    // 获取系统音量
    [self configureVolume];
    
    //[UIApplication sharedApplication].statusBarHidden=NO;
    
    //[UIApplication sharedApplication].statusBarStyle = UIStatusBarStyleLightContent;
    
    //[[UIScreen mainScreen] setBrightness: 0.6];//0.6是自己设定认为比较合适的亮度值
    
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    
    DLog(@"路由器地址----%@",KAppDelegate.routerIP);
    _baseUrl=[NSString stringWithFormat:@"http://%@:8800/",KAppDelegate.routerIP];
    
    if (!_timer) {
        
        _timer = [NSTimer scheduledTimerWithTimeInterval:self.intervals target:self selector:@selector(timeReloop) userInfo:nil repeats:YES];
    }
    
    [_timer fire];
    
//    //开启子线程到网络上获取数据
//    myFirstThread = [[NSThread alloc]initWithTarget:self selector:@selector(thread1GetData) object:nil];
//    [myFirstThread setName:@"第一个子线程,用于获取网络数据"];
//    [myFirstThread start];
    _dataArr=[NSMutableArray arrayWithArray:_getArr];
    
    _titleArr=[NSMutableArray array];
    
    for (int i=0; i<_dataArr.count; i++) {
        
        ProgramModel *model1=_dataArr[i];
        
        NSString *str1=[NSString stringWithFormat:@"%@",model1.frequency];
        
        NSString *str2=[str1 substringToIndex:3];
        
        if (![model1.encrypt isEqualToNumber:@(1)]) {
            
             _str=[NSString stringWithFormat:@"%@/%@",model1.name,str2];
        }else{

            
            _str=[NSString stringWithFormat:@"*%@/%@",[model1.name isEqualToString:@""]?model1.sid:model1.name,str2];
        }
        
        LrdCellModel *nameModel=[[LrdCellModel alloc]initWithTitle:_str imageName:nil];
        
        [_titleArr addObject:nameModel];
        
        DLog(@"%@",_titleArr[i]);
    }

    _numArr=[NSMutableArray array];
    
    // app退到后台
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidEnterBackground) name:UIApplicationWillResignActiveNotification object:nil];
    // app进入前台
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidEnterPlayGround) name:UIApplicationDidBecomeActiveNotification object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:[UIApplication sharedApplication]];
    //注册通知(等待接收消息)
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(changeRouterIP3:) name:@"changeRouterIP" object:nil];
    //初始化指针并分配地址
    //pinfo = (programinfo *)malloc(sizeof(programinfo));
    
}
-(void)changeRouterIP3:(NSNotification *)sender{
    
    KAppDelegate.routerIP=sender.userInfo[@"routerIp"];
    KAppDelegate.isConnect=[sender.userInfo[@"isConnect"] boolValue];
    //_routerIP= KAppDelegate.routerIP;
    DLog(@"通知接收路由器地址--------------------------%@",KAppDelegate.routerIP);
    _baseUrl=[NSString stringWithFormat:@"http://%@:8800/",KAppDelegate.routerIP];

    
}
-(void)viewDidDisappear:(BOOL)animated{
    
    [super viewDidDisappear:animated];
    
    [BWHttpRequest cancelNetworkingWithNetIdentifier:@"keepalive"];

}

- (void) viewWillDisappear:(BOOL)animated
{
    //[UIApplication sharedApplication].statusBarHidden=YES;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"changeRouterIP" object:nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [super viewWillDisappear:animated];
    
    if (_doneCallback) {
        _doneCallback();
    }
    
    //[[UIScreen mainScreen] setBrightness: KAppDelegate.currentLight];//恢复屏幕之前的亮度值
    
    //_loadLabel.text=@"Loading...";
    
    _backView.hidden=YES;
    [_activityIndicatorView stopAnimating];
    
    
    if (_decoder) {
    
        
        [self pause];
        
        if (_moviePosition == 0 || _decoder.isEOF)
            [gHistory removeObjectForKey:_decoder.path];
        else if (!_decoder.isNetwork)
            [gHistory setValue:[NSNumber numberWithFloat:_moviePosition]
                        forKey:_decoder.path];
    }
    
    if (_fullscreen)
        [self fullscreenMode:NO];
        
    [[UIApplication sharedApplication] setIdleTimerDisabled:_savedIdleTimer];
    
    _backView.hidden=YES;
    [_activityIndicatorView stopAnimating];
    _buffered = NO;
    _interrupted = YES;

    if (_timer) {
        //如果定时器在运行
        if ([_timer isValid]) {
            
            [_timer invalidate];
            //这行代码很关键
            _timer=nil;
        }
    }
    if (_hiddenTimer) {
        //如果定时器在运行
        if ([_hiddenTimer isValid]) {
            
            [_hiddenTimer invalidate];
            //这行代码很关键
            _hiddenTimer=nil;
        }
    }
    
   // [NSObject cancelPreviousPerformRequestsWithTarget:self];//可以成功取消全部。
    
   // [BWHttpRequest cancelAllOperations];
    
//    NSArray <NSString *>* str =[BWHttpRequest getUnderwayNetIdentifierArray];
//    
//    [BWHttpRequest cancelNetworkingWithNetIdentifierArray:str];
    
    DLog(@"viewWillDisappear %@", self);
}

//当应用程序将要进入非活动状态执行，在此期间，应用程序不接受消息或事件
- (void) applicationWillResignActive: (NSNotification *)notification
{
    [self pause];
    
    [self toolViewHidden];
    
    DLog(@"applicationWillResignActive");
}

#pragma mark--程序进入后台或前端处理方法
/**
 *  应用退到后台
 */
- (void)appDidEnterBackground
{
    
    self.didEnterBackground = YES;
    
    [self pause];
    
    //[self startBackgroundTask];
    
}

/**
 *  应用进入前台
 */
- (void)appDidEnterPlayGround
{
    
    self.didEnterBackground = NO;
    
    [self play];
}

- (void)startBackgroundTask
{
    UIApplication *application = [UIApplication sharedApplication];
    //通知系统, 我们需要后台继续执行一些逻辑
    backgroundTask = [application beginBackgroundTaskWithExpirationHandler:^{
        //超过系统规定的后台运行时间, 则暂停后台逻辑
        [application endBackgroundTask:backgroundTask];
        backgroundTask = UIBackgroundTaskInvalid;
    }];
    
    DLog(@"%@程序进入后台",self);
    
    //判断如果申请失败了, 返回
    if (backgroundTask == UIBackgroundTaskInvalid) {
        DLog(@"beginground error");
        return;
    }
    //已经成功向系统争取了一些后台运行时间, 实现一些逻辑, 如网络处理
    //some code
}

#pragma mark--获取系统音量
/**
 *  获取系统音量
 */
- (void)configureVolume
{
    MPVolumeView *volumeView = [[MPVolumeView alloc] init];
    _volumeViewSlider = nil;
    volumeView.showsRouteButton = NO;
    volumeView.showsVolumeSlider = NO;
    for (UIView *view in [volumeView subviews]){
        if ([view.class.description isEqualToString:@"MPVolumeSlider"]){
            _volumeViewSlider = (UISlider *)view;
            break;
        }
    }
    
    // 使用这个category的应用不会随着手机静音键打开而静音，可在手机静音下播放声音
    NSError *setCategoryError = nil;
    BOOL success = [[AVAudioSession sharedInstance]
                    setCategory: AVAudioSessionCategoryPlayback
                    error: &setCategoryError];
    
    if (!success) { /* handle the error in setCategoryError */ }
    
    // 监听耳机插入和拔掉通知
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioRouteChangeListenerCallback:) name:AVAudioSessionRouteChangeNotification object:nil];
}

#pragma mark--耳机插入拔出事件
/**
 *  耳机插入、拔出事件
 */
- (void)audioRouteChangeListenerCallback:(NSNotification*)notification
{
    NSDictionary *interuptionDict = notification.userInfo;
    
    NSInteger routeChangeReason = [[interuptionDict valueForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
    
    switch (routeChangeReason) {
            
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
            // 耳机插入
            break;
            
        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
        {
            // 耳机拔掉
            // 拔掉耳机继续播放
            [self play];
        }
            break;
            
        case AVAudioSessionRouteChangeReasonCategoryChange:
            // called at start - also when other audio wants to play
            DLog(@"AVAudioSessionRouteChangeReasonCategoryChange");
            break;
    }
}
#pragma mark - UIPanGestureRecognizer手势方法
/**
 *  tap手势事件
 *
 *  @param tap UITapGestureRecognizer
 */
- (void) handleTap: (UITapGestureRecognizer *) sender
{
    if (sender.state == UIGestureRecognizerStateEnded) {
        
        if (sender == _tapGestureRecognizer) {
            
            if (_topHUD.hidden) {
                [self toolViewOutHidden];
            } else {
                [self toolViewHidden];
            }
            
        } else if (sender == _doubleTapGestureRecognizer) {
            
            _frameView = [self frameView];
            
            if (_frameView.contentMode == UIViewContentModeScaleAspectFit){
                _frameView.contentMode = UIViewContentModeScaleAspectFill;
                _showButton.hidden=YES;
            }else{
                _frameView.contentMode = UIViewContentModeScaleAspectFit;
                _showButton.hidden=NO;
            }
            
            
        }
    }
}
#pragma mark - 控制条隐藏

- (void)toolViewHidden {
    _statusBarIsHidden=YES;
    _topHUD.hidden = YES;
    _bottomHUD.hidden = YES;
    [_hiddenTimer invalidate];
    
    [self setStatusBarHidden:YES];
}

#pragma mark - 控制条退出隐藏

- (void)toolViewOutHidden {
    _statusBarIsHidden=NO;
    _topHUD.hidden = NO;
    _bottomHUD.hidden = NO;
    
    if (!_hiddenTimer.valid) {
        _hiddenTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(toolViewHidden) userInfo:nil repeats:NO];
    }else{
        [_hiddenTimer invalidate];
        _hiddenTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(toolViewHidden) userInfo:nil repeats:NO];
    }
    
    [self setStatusBarHidden:NO];
}

/**
 *  pan手势事件
 *
 *  @param pan UIPanGestureRecognizer
 */
- (void)handlePan: (UIPanGestureRecognizer *) pan
{
    //根据在view上Pan的位置，确定是调音量还是亮度
     locationPoint = [pan locationInView:self.view];
    
    // 我们要响应水平移动和垂直移动
    // 根据上次和本次移动的位置，算出一个速率的point
    //CGPoint veloctyPoint = [pan velocityInView:self.view];
    
    // 判断是垂直移动还是水平移动
    switch (pan.state) {
        case UIGestureRecognizerStateBegan:{ // 开始移动
            // 使用绝对值来判断移动的方向
            //触摸开始, 初始化一些值
            _hasMoved = NO;
            _controlJudge = NO;
            _touchBeginVoiceValue = _volumeViewSlider.value;
            _touchBeginLightValue = [UIScreen mainScreen].brightness;
            _touchBeginPoint = locationPoint;
        }
        case UIGestureRecognizerStateChanged:{
            
            //如果移动的距离过于小, 就判断为没有移动
            if (fabs(locationPoint.x - _touchBeginPoint.x) < LeastMoveDistance && fabs(locationPoint.y - _touchBeginPoint.y) < LeastMoveDistance) {
                return;
            }
            
            _hasMoved = YES;
            
            //如果还没有判断出是什么手势就进行判断
            if (!_controlJudge) {
                //根据滑动角度的tan值来进行判断
                float tan = fabs(locationPoint.y - _touchBeginPoint.y) / fabs(locationPoint.x - _touchBeginPoint.x);
                
                //当滑动角度小于30度的时候, 进度手势
                if (tan < 1 / sqrt(3)) {
                    self.controlType = HCDPlayerControlTypeProgress;
                    _controlJudge = YES;
                }
                //当滑动角度大于60度的时候, 控制声音和亮度
                else if (tan > sqrt(3)) {
                    //判断是在屏幕的左半边还是右半边滑动, 左侧控制为亮度, 右侧控制音量
                    if (_touchBeginPoint.x < self.view.frame.size.width / 2) {
                        _controlType = HCDPlayerControlTypeLight;
                        self.isVolume = NO;
                    }else{
                        _controlType = HCDPlayerControlTypeVoice;
                        self.isVolume = YES;
                    }
                    _controlJudge = YES;
                } else {
                    _controlType = HCDPlayerControlTypeNone;
                    return;
                }
            }
            
            if (HCDPlayerControlTypeProgress == _controlType) {
                
                DLog(@"不能控制播放进度");
                
            } else if (HCDPlayerControlTypeVoice == _controlType) {
                //根据触摸开始时的音量和触摸开始时的点去计算出现在滑动到的音量
                float voiceValue = _touchBeginVoiceValue - ((locationPoint.y - _touchBeginPoint.y) / CGRectGetHeight(self.view.frame));
                
                //判断控制一下, 不能超出 0~1
                if (voiceValue < 0) {
                    self.volumeViewSlider.value = 0;
                }else if(voiceValue > 1){
                    self.volumeViewSlider.value = 1;
                }else{
                    self.volumeViewSlider.value = voiceValue;
                }
            } else if (HCDPlayerControlTypeLight == _controlType) {
                
                float lightValue = _touchBeginLightValue - ((locationPoint.y - _touchBeginPoint.y) / CGRectGetHeight(self.view.frame));
                
                //判断控制一下, 不能超出 0~1
                if (lightValue < 0) {
                    [UIScreen mainScreen].brightness = 0;
                }else if(lightValue > 1){
                    [UIScreen mainScreen].brightness = 1;
                }else{
                    [UIScreen mainScreen].brightness = lightValue;
                }
                KAppDelegate.currentLight=[UIScreen mainScreen].brightness;
                
                HcdLightView *lightView = [HcdLightView sharedInstance];
                
                [[UIApplication sharedApplication].keyWindow bringSubviewToFront:lightView];
                
            }
            
        }
        case UIGestureRecognizerStateEnded:{ // 移动停止
    
            // 移动结束也需要判断垂直或者平移
            // 比如水平移动结束时，要快进到指定位置，如果这里没有判断，当我们调节音量完之后，会出现屏幕跳动的bug
            switch (self.panDirection) {
                case PanDirectionHorizontalMoved:{
                    
                    /*
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        
                        
                        
                    });
                    const CGPoint vt = [pan velocityInView:self.view];
                    const CGPoint pt = [pan translationInView:self.view];
                    const CGFloat sp = MAX(0.1, log10(fabsf(vt.x)) - 1.0);
                    const CGFloat sc = fabsf(pt.x) * 0.33 * sp;
                    if (sc > 10) {
                        
                        const CGFloat ff = pt.x > 0 ? 1.0 : -1.0;
                        [self setMoviePosition: _moviePosition + ff * MIN(sc, 600.0)];
                        //NSLog(@"pan %.2f %.2f %.2f sec", pt.x, vt.x, sc);
                    }
                    
                    */
                    break;
                }
                case PanDirectionVerticalMoved:{
                    // 垂直移动结束后，把状态改为不再控制音量
                    self.isVolume = NO;
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        
                        //[HcdLightView sharedInstance];
                    });
                    break;
                }
                default:
                    break;
            }
            break;
        }
        default:
            break;
    }
}

#pragma mark - public

-(void) play
{
    
    [UIApplication sharedApplication].idleTimerDisabled = YES;

    if (self.playing)
        return;
    
    if (!_decoder.validVideo &&
        !_decoder.validAudio) {
        
        return;
    }
    
    if (_interrupted)
        return;

    self.playing = YES;
    _interrupted = NO;
    _disableUpdateHUD = NO;
    _tickCorrectionTime = 0;
    _tickCounter = 0;

#ifdef DEBUG
    _debugStartTime = -1;
#endif

    [self asyncDecodeFrames];
    [self updatePlayButton];

    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [self tick];
    });

    if (_decoder.validAudio)
        [self enableAudio:YES];

    DLog(@"play movie");
    
}
/**
 *定时器循环事件
 */
-(void)timeReloop{
    
    DLog(@"%@timeReloop：节目播放中发送报文心跳",self);
    NSString *urlStr=[NSString stringWithFormat:@"%@keepalive",_baseUrl];
    
    NSString *timeStr=[self getCurrentTime];
    
    NSDictionary *dict=@{@"id":[NSString stringWithFormat:@"%@",_getId],@"time":timeStr};
    
    [BWHttpRequest postWithUrl:urlStr params:dict netIdentifier:@"keepalive" success:^(id response) {
        
        DLog(@"请求成功");
        NSNumber * statusNum2 = @([response[@"status"] integerValue]);
        
        if ([statusNum2 isEqualToNumber:@(0)]) {
            
            stateNum=0;
            self.intervals=1.5;
            
            DLog(@"stateNum=%d",stateNum);
            
            
        }else if ([statusNum2 isEqualToNumber:@(2)]){
            
            //[_timer setFireDate:[NSDate distantFuture]];
            
            DLog(@"获取资源失败");
            
            stateNum++;
            
            DLog(@"stateNum=%d",stateNum);
            
            if (stateNum>=9) {
                            
                UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"播放失败" message:@"请返回重新播放" preferredStyle:UIAlertControllerStyleAlert];
                
                [alertController addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
                    
                    if (self.presentingViewController || !self.navigationController)
                        [self dismissViewControllerAnimated:YES completion:nil];
                    else
                        [self.navigationController popViewControllerAnimated:YES];
                    
                    
                }]];
                
                [self presentViewController:alertController animated:YES completion:nil];
                
                if (_timer) {
                    if ([_timer isValid]) {
                        
                        [_timer invalidate];
                        _timer=nil;
                    }
                }
                stateNum=0;
            }
            
            
        }else if([statusNum2 isEqualToNumber:@(-2)]){
            
            [LCProgressHUD showMessage:@"正在初始化，请稍后"];
            [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
        }
        
    } fail:^(NSError *error) {
        
        DLog(@"发送心跳请求失败");
        
        self.intervals=0.5;
        
    } showHUD:NO];
}

/**
 *获取系统当前时间
 */
- (NSString *)getCurrentTime {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSString *dateTime = [formatter stringFromDate:[NSDate date]];
    return dateTime;
}

- (void) pause
{
    if (!self.playing)
        return;

    self.playing = NO;
    //_interrupted = YES;
    [self enableAudio:NO];
    [self updatePlayButton];
    DLog(@"pause movie");
}

- (void) setMoviePosition: (CGFloat) position
{
    BOOL playMode = self.playing;
    
    self.playing = NO;
    _disableUpdateHUD = YES;
    [self enableAudio:NO];
    
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, 0.1 * NSEC_PER_SEC);
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){

        [self updatePosition:position playMode:playMode];
    });
}

#pragma mark - actions

- (void) doneDidTouch: (id) sender
{
    
    __weak __typeof(&*self)weakSelf =self;
    //---------------------GCD----------------------支持多核，高效率的多线程技术
    dispatch_queue_t queue = dispatch_queue_create("name", NULL);
    //创建一个子线程
    dispatch_async(queue, ^{
        // 子线程code... ..
        DLog(@"GCD子线程");
         
        
        //发送节目播放结束请求
        NSString *urlStr=[NSString stringWithFormat:@"%@stop",_baseUrl];
        
        NSDictionary *dict=@{@"id":[NSString stringWithFormat:@"%@",_getId]};
        
        [BWHttpRequest postWithUrl:urlStr params:dict netIdentifier:@"stop" success:^(id response) {
            
            
            NSNumber * statusNum1 = @([response[@"status"] integerValue]);
            
            if ([statusNum1 isEqualToNumber:@(0)]) {
                
                if (weakSelf.timer) {
                    //如果定时器在运行
                    if ([weakSelf.timer isValid]) {
                        
                        [weakSelf.timer invalidate];
                        //这行代码很关键
                        weakSelf.timer=nil;
                    }
                }
                
                DLog(@"节目关闭");
            }else if ([statusNum1 isEqualToNumber:@(1)]){
                
                [LCProgressHUD showMessage:@"非法操作"];
                [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
                
            }else if([statusNum1 isEqualToNumber:@(-2)]){
                
                [LCProgressHUD showMessage:@"设备初始化，请稍后"];
                [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
                
            }
            
        } fail:^(NSError *error) {
            
            DLog(@"--%@",error.description);
            
            DLog(@"---请求失败");
            
        } showHUD:NO];
        
        [BWHttpRequest cancelNetworkingWithNetIdentifier:@"keepalive"];
        
        //回到主线程
        dispatch_sync(dispatch_get_main_queue(), ^{//其实这个也是在子线程中执行的，只是把它放到了主线程的队列中
            Boolean isMain = [NSThread isMainThread];
            if (isMain) {
                DLog(@"GCD主线程");
                
                if (weakSelf.presentingViewController || !weakSelf.navigationController)
                    [weakSelf dismissViewControllerAnimated:YES completion:nil];
                else
                    [weakSelf.navigationController popViewControllerAnimated:YES];
            }
        });
    });
}

- (void) infoDidTouch: (id) sender
{
    [self showInfoView: !_infoMode animated:YES];
}

- (void) playDidTouch: (id) sender
{
    if (self.playing)
        [self pause];
    else
        
        [self play];
}

-(void)showProgramBtnDidTouch:(UIButton *)sender{
    
    _showButton.hidden=YES;
    
    _outputView = [[LrdOutputView alloc] initWithDataArray:self.titleArr origin:CGPointMake(0, 0) width:130 height:44 direction:kLrdOutputViewDirectionRight];
    
    __weak __typeof(&*self)weakSelf =self;

    _outputView.delegate = self;
    _outputView.dismissOperation = ^(){
        //设置成nil，以防内存泄露
        _outputView = nil;
        
        if (weakSelf.frameView.contentMode==UIViewContentModeScaleAspectFill) {
            
            weakSelf.showButton.hidden=YES;
        }else{
            
            weakSelf.showButton.hidden=NO;
        }
        
        
    };
    [_outputView pop];
    
}

#pragma mark--节目列表的点击事件  更换节目／change
- (void)didSelectedAtIndexPath:(NSIndexPath *)indexPath {
    
//    if (_port<2020) {
//        
//        _port++;
//    }
//    else{
//        
//        _port=2000;
//    }
    
    _outputView.userInteractionEnabled=NO;
    
    __weak __typeof(&*self)weakSelf =self;
    model=self.dataArr[indexPath.row];
    
    NSLog(@"%@",model.name);
    NSLog(@"%@",model.frequency);
    
    
    if ([model.encrypt isEqualToNumber:@(1)]) {
        
        [LCProgressHUD showMessage:@"加密节目，暂无法播放"];
        [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
        
    }else{
        NSString *urlStr=[NSString stringWithFormat:@"%@change",_baseUrl];
        
        NSNumber *portNum=@(_port);
        
        DLog(@"===================>%@",portNum);
        
        NSNumber *freNum=@([model.frequency integerValue]);
        
        NSDictionary *dict=@{@"id":[NSString stringWithFormat:@"%@",_getId],@"frequency":freNum,@"sid":model.sid,@"port":portNum};
        
        [BWHttpRequest postWithUrl:urlStr params:dict netIdentifier:@"change" success:^(id response) {
            NSLog(@"---请求成功");
            
            _outputView.userInteractionEnabled=YES;
            
            NSNumber *statusNum = @([response[@"status"] integerValue]);
            
            NSLog(@"%@",statusNum);
            
            if ([statusNum isEqualToNumber:@(0)]) {
                
                [[UIApplication sharedApplication] setIdleTimerDisabled:YES]; 
                
                if (weakSelf.timer) {
                    //如果定时器在运行
                    if ([weakSelf.timer isValid]) {
                        NSLog(@"播放结束，取消定时器！");
                        [weakSelf.timer invalidate];
                        //这行代码很关键
                        weakSelf.timer=nil;
                    }
                }
                NSString *idString=response[@"id"];
                
                       _getId=idString;
//                
//                        NSLog(@"idString:%@",_getId);
                
                NSString *path=[NSString stringWithFormat:@"udp://%@:%ld",_getIpAddress,(long)_port];
                
                NSLog(@"%@/change:%@",self,path);
                
                NSDictionary *dict1 =[[NSDictionary alloc] initWithObjectsAndKeys:path,@"path",idString,@"idString",model.name,@"name",model.frequency,@"frequency",nil];
                //创建通知
                NSNotification *notification =[NSNotification notificationWithName:@"changNotification" object:nil userInfo:dict1];
                
                //通过通知中心发送通知
                [[NSNotificationCenter defaultCenter] postNotification:notification];

                if (self.presentingViewController || !self.navigationController)
                    
                    
                    [self dismissViewControllerAnimated:YES completion:nil];
                
                else
                    [self.navigationController popViewControllerAnimated:YES];
                
            }else if([statusNum isEqualToNumber:@(2)]){
                
                [LCProgressHUD showMessage:@"节目信息已过期"];
                [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
                
            }
            else if([statusNum isEqualToNumber:@(3)]){
                
                [LCProgressHUD showMessage:@"其他用户正在搜索节目"];
                [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
            }else if ([statusNum isEqualToNumber:@(4)]){
                
                [LCProgressHUD showMessage:@"其他用户正在观看节目"];
                [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
            }else if ([statusNum isEqualToNumber:@(5)]){
                
                [LCProgressHUD showMessage:@"无可用通道"];
                [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
            }else if([statusNum isEqualToNumber:@(1)]){
                
                [LCProgressHUD showMessage:@"非法操作"];
                [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
            }else if([statusNum isEqualToNumber:@(-2)]){
                
                [LCProgressHUD showMessage:@"设备初始化,请稍后"];
                [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
            }
            
            
        } fail:^(NSError *error) {
            
            NSLog(@"请求失败:%@", error.description);
            
        } showHUD:NO];
        
    }
    
}

/*
- (void)playNextVideo:(NSString *)filePath {
    [self pause];
    [self freeBufferedFrames];
    [_decoder closeFile];
    _moviePosition = 0;
    [_decoder openFile:filePath error:nil];
    [self play];
}
*/

/**
 *
 */
- (void) forwardDidTouch: (id) sender
{
   // [self setMoviePosition: _moviePosition + 10];
    
    curretName=[NSString stringWithFormat:@"%@",_getName];
    
//    for (int i=2000; i<=2020; i++) {
//        
//        if (_port==i) {
//            
//            if (_port<2020) {
//                
//                _port=i+1;
//            }
//            else{
//                
//                _port=2000;
//            }
//            
//        }
//        
//    }
    
    _outputView.userInteractionEnabled=NO;
    
    for (NSInteger i=0; i<self.dataArr.count; i++) {
        
        ProgramModel *model1=self.dataArr[i];
        
        if ([model1.name isEqualToString:curretName]) {
            
            if (i<self.dataArr.count-1) {
                
                model =self.dataArr[i+1];
                
            }else{
                
                model=self.dataArr[0];
                
                 DLog(@"%@",model.name);
            }
        }
    }
    
    _getName=model.name;
    
    _getFrequency=model.frequency;
    
    if ([model.encrypt isEqualToNumber:@(1)]) {
        
        [LCProgressHUD showMessage:@"加密节目，暂无法播放"];
        [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
        
    }else{
        
        
        [self changeProgramMathod];
    }

}

- (void) rewindDidTouch: (id) sender
{
    
   // [self setMoviePosition: _moviePosition - 10];
    
    curretName=[NSString stringWithFormat:@"%@",_getName];
    
//    if (_port<2020) {
//        
//        _port++;
//    }
//    else{
//        
//        _port=2000;
//    }
    
    _outputView.userInteractionEnabled=NO;
    
    for (NSInteger i=0; i<self.dataArr.count; i++) {
        
        ProgramModel *model1=self.dataArr[i];
        
        if ([model1.name isEqualToString:curretName]) {
            
            if (i>0) {
                
                model =self.dataArr[i-1];
                
            }else{
                
                model=self.dataArr[self.dataArr.count-1];
                
                DLog(@"%@",model.name);
            }
        }
    }

    _getName=model.name;
    
    _getFrequency=model.frequency;
    
    if ([model.encrypt isEqualToNumber:@(1)]) {
        
        [LCProgressHUD showMessage:@"加密节目，暂无法播放"];
        [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
        
    }else{
        
        [self changeProgramMathod];
        
    }

}

-(void)changeProgramMathod{
    
    if (self.popPortBlock) {
        
        self.popPortBlock(_port);
    }

    NSString *urlStr=[NSString stringWithFormat:@"%@change",_baseUrl];
    
    NSNumber *portNum1=@(_port);
        
    NSNumber *freNum=@([model.frequency integerValue]);
    
    NSDictionary *dict=@{@"id":[NSString stringWithFormat:@"%@",_getId],@"frequency":freNum,@"sid":model.sid,@"port":portNum1};
    
    [BWHttpRequest postWithUrl:urlStr params:dict netIdentifier:@"change" success:^(id response) {
        DLog(@"---请求成功");
        
        _outputView.userInteractionEnabled=YES;
        
        NSNumber *statusNum = @([response[@"status"] integerValue]);
        
        DLog(@"%@",statusNum);
        
        if ([statusNum isEqualToNumber:@(0)]) {
            
            
            NSString *idString=response[@"id"];
            
            _getId=idString;
            
            NSString *path=[NSString stringWithFormat:@"udp://%@:%ld",_getIpAddress,(long)_port];
            
            NSLog(@"%@/change:%@",self,path);
            
            NSDictionary *dict1 =[[NSDictionary alloc] initWithObjectsAndKeys:path,@"path",idString,@"idString",model.name,@"name",model.frequency,@"frequency",nil];
            //创建通知
            NSNotification *notification =[NSNotification notificationWithName:@"changNotification" object:nil userInfo:dict1];
            
            //通过通知中心发送通知
            [[NSNotificationCenter defaultCenter] postNotification:notification];
            
            if (self.presentingViewController || !self.navigationController)
                
                
                [self dismissViewControllerAnimated:YES completion:nil];
            
            else
                [self.navigationController popViewControllerAnimated:YES];

            
            //[self playNewContentIndex:path];
            
        }else if([statusNum isEqualToNumber:@(2)]){
            
            [LCProgressHUD showMessage:@"节目信息已无效"];
            [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
            
        }
        else if([statusNum isEqualToNumber:@(3)]){
            
            [LCProgressHUD showMessage:@"其他用户正在搜索节目"];
            [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
        }else if ([statusNum isEqualToNumber:@(4)]){
            
            [LCProgressHUD showMessage:@"其他用户正在观看不同频点节目"];
            [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
        }else if ([statusNum isEqualToNumber:@(5)]){
            
            [LCProgressHUD showMessage:@"无可用通道"];
            [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
        }else if([statusNum isEqualToNumber:@(1)]){
            
            [LCProgressHUD showMessage:@"非法操作"];
            [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
        }else if([statusNum isEqualToNumber:@(-2)]){
            
            [LCProgressHUD showMessage:@"设备初始化,请稍后"];
            [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
        }
        
        
    } fail:^(NSError *error) {
        
        DLog(@"请求失败:%@", error.description);
        
        UIAlertController * alertController = [UIAlertController alertControllerWithTitle:nil message:@"请求失败,请检测网络异常" preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDestructive handler:nil];
        
        [alertController addAction:cancelAction];
        
        [self presentViewController:alertController animated:YES completion:nil];

        
    } showHUD:NO];

}

#pragma mark--单击更换节目／change
-(void)playNewContentIndex:(NSString *)path{
    
    if (_activityIndicatorView.isAnimating) {
        
        _backView.hidden=YES;
        
        [_activityIndicatorView stopAnimating];
    }
    __weak KxMovieViewController *weakSelf = self;
    
    if (_playing) {
        
        [self pause];
    }
    
    if (_fullscreen)
        [self fullscreenMode:NO];
    
     //[_decoder closeFile];
    
    KxMovieDecoder *decoder = [[KxMovieDecoder alloc] init];
    [decoder closeFile];
    
    _loadLabel.text=@"Loading...";
    
    _bottomHUD.userInteractionEnabled=NO;
    
    _backView.hidden=NO;
    
    [_activityIndicatorView startAnimating];
    
    [self freeBufferedFrames];
    
    self.artworkFrame = nil;
    
    _moviePosition = 0;
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        
        NSError *error = nil;
        
        __strong KxMovieViewController *strongSelf = weakSelf;
        
        @synchronized(_decoder){
            
            [_decoder openFile:path error:&error];
        }
        if (strongSelf) {
            dispatch_sync(dispatch_get_main_queue(), ^{
                
                _backView.hidden=YES;
                
                [_activityIndicatorView stopAnimating];
                
                [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
                
                _nameLabel.text = [NSString stringWithFormat:@"%@   频点:%@",_getName,_getFrequency];
                
                [strongSelf play];
                
                _bottomHUD.userInteractionEnabled=YES;
                
                
            });
        }
    });
}


- (void) progressDidChange: (id) sender
{
    NSAssert(_decoder.duration != MAXFLOAT, @"bugcheck");
    
    UISlider *slider = sender;
    
    [self setMoviePosition:slider.value * _decoder.duration];
}

#pragma mark - private

- (void) setMovieDecoder: (KxMovieDecoder *) decoder
               withError: (NSError *) error
{
    
    
    DLog(@"setMovieDecoder");
            
    if (!error && decoder) {
        
        _decoder        = decoder;
        _dispatchQueue  = dispatch_queue_create("KxMovie", DISPATCH_QUEUE_SERIAL);
        _videoFrames    = [NSMutableArray array];
        _audioFrames    = [NSMutableArray array];
        
        if (_decoder.subtitleStreamsCount) {
            _subtitles = [NSMutableArray array];
        }
    
        if (_decoder.isNetwork) {
            
            _minBufferedDuration = NETWORK_MIN_BUFFERED_DURATION;
            _maxBufferedDuration = NETWORK_MAX_BUFFERED_DURATION;
            
        } else {
            
            _minBufferedDuration = LOCAL_MIN_BUFFERED_DURATION;
            _maxBufferedDuration = LOCAL_MAX_BUFFERED_DURATION;
        }
        
        if (!_decoder.validVideo)
            _minBufferedDuration *= 10.0; // increase for audio
                
        // allow to tweak some parameters at runtime
        if (_parameters.count) {
            
            id val;
            
            val = [_parameters valueForKey: KxMovieParameterMinBufferedDuration];
            if ([val isKindOfClass:[NSNumber class]])
                _minBufferedDuration = [val floatValue];
            
            val = [_parameters valueForKey: KxMovieParameterMaxBufferedDuration];
            if ([val isKindOfClass:[NSNumber class]])
                _maxBufferedDuration = [val floatValue];
            
            val = [_parameters valueForKey: KxMovieParameterDisableDeinterlacing];
            if ([val isKindOfClass:[NSNumber class]])
                _decoder.disableDeinterlacing = [val boolValue];
            
            if (_maxBufferedDuration < _minBufferedDuration)
                _maxBufferedDuration = _minBufferedDuration * 2;
        }
        
        DLog(@"buffered limit: %.1f - %.1f", _minBufferedDuration, _maxBufferedDuration);
        
        if (self.isViewLoaded) {
            
            [self setupPresentView];
            
            _bottomHUD.hidden       = NO;
            _progressLabel.hidden   = NO;
            _progressSlider.hidden  = NO;
            _leftLabel.hidden       = NO;
            _infoButton.hidden      = NO;
            
            if (_activityIndicatorView.isAnimating) {
                
                _backView.hidden=YES;
                [_activityIndicatorView stopAnimating];
                
                //取消延时执行的函数
               // [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(isPopView) object:nil];

                // if (self.view.window)
                [self restorePlay];
            }
        }
        
    } else {
        
         if (self.isViewLoaded && self.view.window) {
        
             _backView.hidden=YES;
             [_activityIndicatorView stopAnimating];
             if (!_interrupted)
                 [self handleDecoderMovieError: error];
         }
    }
}

- (void) restorePlay
{
    NSNumber *n = [gHistory valueForKey:_decoder.path];
    if (n)
        [self updatePosition:n.floatValue playMode:YES];
    else
        [self play];
}

- (void) setupPresentView
{
    //CGRect bounds = self.view.bounds;
    CGRect bounds=[UIScreen mainScreen].bounds;
    
    if (_decoder.validVideo) {
        _glView = [[KxMovieGLView alloc] initWithFrame:bounds decoder:_decoder];
    } 
    
    if (!_glView) {
        
        DLog(@"fallback to use RGB video frame and UIKit");
        [_decoder setupVideoFrameFormat:KxVideoFrameFormatRGB];
        _imageView = [[UIImageView alloc] initWithFrame:bounds];
    }
    
    UIView *frameView = [self frameView];
    
    frameView.backgroundColor=[UIColor blackColor];
    
    frameView.contentMode = UIViewContentModeScaleAspectFit;
    
    frameView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleBottomMargin;
    
    [self.view insertSubview:frameView atIndex:0];
        
    if (_decoder.validVideo) {
    
        [self setupUserInteraction];
    
    } else {
       
        _imageView.image = [UIImage imageNamed:@"kxmovie.bundle/music_icon.png"];
        _imageView.contentMode = UIViewContentModeCenter;
    }
    
    self.view.backgroundColor = [UIColor clearColor];
    
    if (_decoder.duration == MAXFLOAT) {
        
        _leftLabel.text = @"\u221E"; // infinity
        _leftLabel.font = [UIFont systemFontOfSize:14];
        
        CGRect frame;
        
        frame = _leftLabel.frame;
        frame.origin.x += 40;
        frame.size.width -= 40;
        _leftLabel.frame = frame;
        
        frame =_progressSlider.frame;
        frame.size.width += 40;
        _progressSlider.frame = frame;
        
    } else {
        
        [_progressSlider addTarget:self
                            action:@selector(progressDidChange:)
                  forControlEvents:UIControlEventValueChanged];
    }
    
    if (_decoder.subtitleStreamsCount) {
        
        CGSize size = self.view.bounds.size;
        
        _subtitlesLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, size.height, size.width, 0)];
        _subtitlesLabel.numberOfLines = 0;
        _subtitlesLabel.backgroundColor = [UIColor clearColor];
        _subtitlesLabel.opaque = NO;
        _subtitlesLabel.adjustsFontSizeToFitWidth = NO;
        _subtitlesLabel.textAlignment = NSTextAlignmentCenter;
        _subtitlesLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        _subtitlesLabel.textColor = [UIColor whiteColor];
        _subtitlesLabel.font = [UIFont systemFontOfSize:16];
        _subtitlesLabel.hidden = YES;

        [self.view addSubview:_subtitlesLabel];
    }
}

- (void) setupUserInteraction
{
    UIView * view = [self frameView];
    view.userInteractionEnabled = YES;
    
    _tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    _tapGestureRecognizer.numberOfTapsRequired = 1;
    
    _doubleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    _doubleTapGestureRecognizer.numberOfTapsRequired = 2;
    
    [_tapGestureRecognizer requireGestureRecognizerToFail: _doubleTapGestureRecognizer];
    
    [view addGestureRecognizer:_doubleTapGestureRecognizer];
    [view addGestureRecognizer:_tapGestureRecognizer];
    
    _panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    _panGestureRecognizer.enabled = YES;
    
    [view addGestureRecognizer:_panGestureRecognizer];
    
    _hiddenTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(toolViewHidden) userInfo:nil repeats:NO];
    
}


- (UIView *) frameView
{
    return _glView ? _glView : _imageView;
}

- (void) audioCallbackFillData: (float *) outData
                     numFrames: (UInt32) numFrames
                   numChannels: (UInt32) numChannels
{
    //fillSignalF(outData,numFrames,numChannels);
    //return;
    
    if (_buffered) {
        memset(outData, 0, numFrames * numChannels * sizeof(float));
        return;
    }
    
    @autoreleasepool {
        
        while (numFrames > 0) {
            
            if (!_currentAudioFrame) {
                
                @synchronized(_audioFrames) {
                    
                    NSUInteger count = _audioFrames.count;
                    
                    if (count > 0) {
                        
                        KxAudioFrame *frame = _audioFrames[0];
                        
#ifdef DUMP_AUDIO_DATA
                        LoggerAudio(2, @"Audio frame position: %f", frame.position);
#endif
                        if (_decoder.validVideo) {
                            
                            const CGFloat delta = _moviePosition - frame.position;
                            
                            if (delta < -10) {
                                
                                memset(outData, 0, numFrames * numChannels * sizeof(float));
#ifdef DEBUG
                                LoggerStream(0, @"desync audio (outrun) wait %.4f %.4f", _moviePosition, frame.position);
                                _debugAudioStatus = 1;
                                _debugAudioStatusTS = [NSDate date];
#endif
                                break; // silence and exit
                            }
                            
                            [_audioFrames removeObjectAtIndex:0];
                            
                            if (delta > 0.2 && count > 1) {
                                
#ifdef DEBUG
                                LoggerStream(0, @"desync audio (lags) skip %.4f %.4f", _moviePosition, frame.position);
                                _debugAudioStatus = 2;
                                _debugAudioStatusTS = [NSDate date];
#endif
                                continue;
                            }
                            
                        } else {
                            
                            [_audioFrames removeObjectAtIndex:0];
                            _moviePosition = frame.position;
                            _bufferedDuration -= frame.duration;
                        }
                        
                        _currentAudioFramePos = 0;
                        _currentAudioFrame = frame.samples;
                    }
                }
            }
            
            if (_currentAudioFrame) {
                
                const void *bytes = (Byte *)_currentAudioFrame.bytes + _currentAudioFramePos;
                const NSUInteger bytesLeft = (_currentAudioFrame.length - _currentAudioFramePos);
                const NSUInteger frameSizeOf = numChannels * sizeof(float);
                const NSUInteger bytesToCopy = MIN(numFrames * frameSizeOf, bytesLeft);
                const NSUInteger framesToCopy = bytesToCopy / frameSizeOf;
                
                memcpy(outData, bytes, bytesToCopy);
                numFrames -= framesToCopy;
                outData += framesToCopy * numChannels;
                
                if (bytesToCopy < bytesLeft)
                    _currentAudioFramePos += bytesToCopy;
                else
                    _currentAudioFrame = nil;
                
            } else {
                
                memset(outData, 0, numFrames * numChannels * sizeof(float));
                //LoggerStream(1, @"silence audio");
#ifdef DEBUG
                _debugAudioStatus = 3;
                _debugAudioStatusTS = [NSDate date];
#endif
                break;
            }
        }
    }
}

- (void) enableAudio: (BOOL) on
{
    id<KxAudioManager> audioManager = [KxAudioManager audioManager];
            
    if (on && _decoder.validAudio) {
                
        audioManager.outputBlock = ^(float *outData, UInt32 numFrames, UInt32 numChannels) {
            
            [self audioCallbackFillData: outData numFrames:numFrames numChannels:numChannels];
        };
        
        [audioManager play];
        
        DLog(@"audio device smr: %d fmt: %d chn: %d",
              (int)audioManager.samplingRate,
              (int)audioManager.numBytesPerSample,
              (int)audioManager.numOutputChannels);
        
    } else {
        
        [audioManager pause];
        audioManager.outputBlock = nil;
    }
}

- (BOOL) addFrames: (NSArray *)frames
{
    if (_decoder.validVideo) {
        
        @synchronized(_videoFrames) {
            
            for (KxMovieFrame *frame in frames)
                if (frame.type == KxMovieFrameTypeVideo) {
                    [_videoFrames addObject:frame];
                    _bufferedDuration += frame.duration;
                }
        }
    }
    
    if (_decoder.validAudio) {
        
        @synchronized(_audioFrames) {
            
            for (KxMovieFrame *frame in frames)
                if (frame.type == KxMovieFrameTypeAudio) {
                    [_audioFrames addObject:frame];
                    if (!_decoder.validVideo)
                        _bufferedDuration += frame.duration;
                }
        }
        
        if (!_decoder.validVideo) {
            
            for (KxMovieFrame *frame in frames)
                if (frame.type == KxMovieFrameTypeArtwork)
                    self.artworkFrame = (KxArtworkFrame *)frame;
        }
    }
    
    if (_decoder.validSubtitles) {
        
        @synchronized(_subtitles) {
            
            for (KxMovieFrame *frame in frames)
                if (frame.type == KxMovieFrameTypeSubtitle) {
                    [_subtitles addObject:frame];
                }
        }
    }
    
    return self.playing && _bufferedDuration < _maxBufferedDuration;
}

- (BOOL) decodeFrames
{
    //NSAssert(dispatch_get_current_queue() == _dispatchQueue, @"bugcheck");
    
    NSArray *frames = nil;
    
    if (_decoder.validVideo ||
        _decoder.validAudio) {
        
        frames = [_decoder decodeFrames:0];
    }
    
    if (frames.count) {
        return [self addFrames: frames];
    }
    return NO;
}

- (void) asyncDecodeFrames
{
    if (self.decoding)
        return;
    
    __weak KxMovieViewController *weakSelf = self;
    __weak KxMovieDecoder *weakDecoder = _decoder;
    
    const CGFloat duration = _decoder.isNetwork ? .0f : 0.1f;
    
    self.decoding = YES;
    dispatch_async(_dispatchQueue, ^{
        
        {
            __strong KxMovieViewController *strongSelf = weakSelf;
            if (!strongSelf.playing)
                return;
        }
        
        BOOL good = YES;
        while (good) {
            
            good = NO;
            
            @autoreleasepool {
                
                __strong KxMovieDecoder *decoder = weakDecoder;
                
                if (decoder && (decoder.validVideo || decoder.validAudio)) {
                    
                    NSArray *frames = [decoder decodeFrames:duration];
                    if (frames.count) {
                        
                        __strong KxMovieViewController *strongSelf = weakSelf;
                        if (strongSelf)
                            good = [strongSelf addFrames:frames];
                    }
                }
            }
        }
        {
            __strong KxMovieViewController *strongSelf = weakSelf;
            if (strongSelf) strongSelf.decoding = NO;
        }
    });
}

- (void) tick
{
    if (_buffered && ((_bufferedDuration > _minBufferedDuration) || _decoder.isEOF)) {
        
        _tickCorrectionTime = 0;
        _buffered = NO;
        [_activityIndicatorView stopAnimating];
        _backView.hidden=YES;
    }
    
    CGFloat interval = 0;
    if (!_buffered)
        interval = [self presentFrame];
    
    if (self.playing) {
        
        const NSUInteger leftFrames =
        (_decoder.validVideo ? _videoFrames.count : 0) +
        (_decoder.validAudio ? _audioFrames.count : 0);
        
        if (0 == leftFrames) {
            
            if (_decoder.isEOF) {
                
                [self pause];
                [self updateHUD];
                return;
            }
            
            if (_minBufferedDuration > 0 && !_buffered) {
                                
                _buffered = YES;
                _backView.hidden=NO;
                [_activityIndicatorView startAnimating];
                
            }
        }
        
        if (!leftFrames ||
            !(_bufferedDuration > _minBufferedDuration)) {
            
            [self asyncDecodeFrames];
        }
        
        const NSTimeInterval correction = [self tickCorrection];
        const NSTimeInterval time = MAX(interval + correction, 0.01);
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, time * NSEC_PER_SEC);
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            [self tick];
        });
    }
    
    if ((_tickCounter++ % 3) == 0) {
        [self updateHUD];
    }
}

- (CGFloat) tickCorrection
{
    if (_buffered)
        return 0;
    
    const NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    
    if (!_tickCorrectionTime) {
        
        _tickCorrectionTime = now;
        _tickCorrectionPosition = _moviePosition;
        return 0;
    }
    
    NSTimeInterval dPosition = _moviePosition - _tickCorrectionPosition;
    NSTimeInterval dTime = now - _tickCorrectionTime;
    NSTimeInterval correction = dPosition - dTime;
    
    //if ((_tickCounter % 200) == 0)
    //    NSLog(@"tick correction %.4f", correction);
    
    if (correction > 1.f || correction < -1.f) {
        
        DLog(@"tick correction reset %.2f", correction);
        correction = 0;
        _tickCorrectionTime = 0;
    }
    
    return correction;
}

- (CGFloat) presentFrame
{
    CGFloat interval = 0;
    
    if (_decoder.validVideo) {
        
        KxVideoFrame *frame;
        
        @synchronized(_videoFrames) {
            
            if (_videoFrames.count > 0) {
                
                frame = _videoFrames[0];
                [_videoFrames removeObjectAtIndex:0];
                _bufferedDuration -= frame.duration;
            }
        }
        
        if (frame)
            interval = [self presentVideoFrame:frame];
        
    } else if (_decoder.validAudio) {

        //interval = _bufferedDuration * 0.5;
                
        if (self.artworkFrame) {
            
            _imageView.image = [self.artworkFrame asImage];
            self.artworkFrame = nil;
        }
    }

    if (_decoder.validSubtitles)
        [self presentSubtitles];
    
#ifdef DEBUG
    if (self.playing && _debugStartTime < 0)
        _debugStartTime = [NSDate timeIntervalSinceReferenceDate] - _moviePosition;
#endif

    return interval;
}

- (CGFloat) presentVideoFrame: (KxVideoFrame *) frame
{
    if (_glView) {
        
        [_glView render:frame];
        
    } else {
        
        KxVideoFrameRGB *rgbFrame = (KxVideoFrameRGB *)frame;
        _imageView.image = [rgbFrame asImage];
    }
    
    _moviePosition = frame.position;
        
    return frame.duration;
}

- (void) presentSubtitles
{
    NSArray *actual, *outdated;
    
    if ([self subtitleForPosition:_moviePosition
                           actual:&actual
                         outdated:&outdated]){
        
        if (outdated.count) {
            @synchronized(_subtitles) {
                [_subtitles removeObjectsInArray:outdated];
            }
        }
        
        if (actual.count) {
            
            NSMutableString *ms = [NSMutableString string];
            for (KxSubtitleFrame *subtitle in actual.reverseObjectEnumerator) {
                if (ms.length) [ms appendString:@"\n"];
                [ms appendString:subtitle.text];
            }
            
            if (![_subtitlesLabel.text isEqualToString:ms]) {
                
                CGSize viewSize = self.view.bounds.size;
                
                NSAttributedString *attributedText =
                [[NSAttributedString alloc]
                 initWithString:ms
                 attributes:@
                 {
                 NSFontAttributeName: _subtitlesLabel.font
                 }];
                
                CGRect rect = [attributedText boundingRectWithSize:(CGSize){viewSize.width, viewSize.height * 0.5}
                                                           options:NSStringDrawingUsesLineFragmentOrigin
                                                           context:nil];
                CGSize size = rect.size;
                
//                CGSize size = [ms sizeWithFont:_subtitlesLabel.font
//                             constrainedToSize:CGSizeMake(viewSize.width, viewSize.height * 0.5)
//                                 lineBreakMode:NSLineBreakByTruncatingTail];
                _subtitlesLabel.text = ms;
                _subtitlesLabel.frame = CGRectMake(0, viewSize.height - size.height - 10,
                                                   viewSize.width, size.height);
                _subtitlesLabel.hidden = NO;
            }
            
        } else {
            
            _subtitlesLabel.text = nil;
            _subtitlesLabel.hidden = YES;
        }
    }
}

- (BOOL) subtitleForPosition: (CGFloat) position
                      actual: (NSArray **) pActual
                    outdated: (NSArray **) pOutdated
{
    if (!_subtitles.count)
        return NO;
    
    NSMutableArray *actual = nil;
    NSMutableArray *outdated = nil;
    
    for (KxSubtitleFrame *subtitle in _subtitles) {
        
        if (position < subtitle.position) {
            
            break; // assume what subtitles sorted by position
            
        } else if (position >= (subtitle.position + subtitle.duration)) {
            
            if (pOutdated) {
                if (!outdated)
                    outdated = [NSMutableArray array];
                [outdated addObject:subtitle];
            }
            
        } else {
            
            if (pActual) {
                if (!actual)
                    actual = [NSMutableArray array];
                [actual addObject:subtitle];
            }
        }
    }
    
    if (pActual) *pActual = actual;
    if (pOutdated) *pOutdated = outdated;
    
    return actual.count || outdated.count;
}

- (void) updatePlayButton
{
    [_playButton setImage:[UIImage imageNamed:self.playing ? @"kxmovie.bundle/playback_pause" : @"kxmovie.bundle/playback_play"]
                 forState:UIControlStateNormal];
}

- (void) updateHUD
{
    if (_disableUpdateHUD)
        return;
    
    const CGFloat duration = _decoder.duration;
    const CGFloat position = _moviePosition -_decoder.startTime;
    
    if (_progressSlider.state == UIControlStateNormal)
        _progressSlider.value = position / duration;
    _progressLabel.text = formatTimeInterval(position, NO);
    
    if (_decoder.duration != MAXFLOAT)
        _leftLabel.text = formatTimeInterval(duration - position, YES);
    

#ifdef DEBUG
   // const NSTimeInterval timeSinceStart = [NSDate timeIntervalSinceReferenceDate] - _debugStartTime;
   // NSString *subinfo = _decoder.validSubtitles ? [NSString stringWithFormat: @" %d",_subtitles.count] : @"";
    
    NSString *audioStatus;
    
    if (_debugAudioStatus) {
        
        if (NSOrderedAscending == [_debugAudioStatusTS compare: [NSDate dateWithTimeIntervalSinceNow:-0.5]]) {
            _debugAudioStatus = 0;
        }
    }
    
    if (_debugAudioStatus == 1) audioStatus = @"\n(audio outrun)";
    else if (_debugAudioStatus == 2) audioStatus = @"\n(audio lags)";
    else if (_debugAudioStatus == 3) audioStatus = @"\n(audio silence)";
    else audioStatus = @"";
    
    _loadLabel.text = [NSString stringWithFormat:@"%@",
                          _buffered ? [NSString stringWithFormat:@"Loading %.1f%%", _bufferedDuration / _minBufferedDuration * 100] : @""];
#endif
}


- (void) fullscreenMode: (BOOL) on
{
    _fullscreen = on;
    UIApplication *app = [UIApplication sharedApplication];
    [app setStatusBarHidden:on withAnimation:UIStatusBarAnimationNone];
     if (!self.presentingViewController) {
    [self.navigationController setNavigationBarHidden:on animated:YES];
    //[self.tabBarController setTabBarHidden:on animated:YES];
     }
}

- (void) setMoviePositionFromDecoder
{
    _moviePosition = _decoder.position;
}

- (void) setDecoderPosition: (CGFloat) position
{
    _decoder.position = position;
}

- (void) enableUpdateHUD
{
    _disableUpdateHUD = NO;
}

- (void) updatePosition: (CGFloat) position
               playMode: (BOOL) playMode
{
    [self freeBufferedFrames];
    
    position = MIN(_decoder.duration - 1, MAX(0, position));
    
    __weak KxMovieViewController *weakSelf = self;

    dispatch_async(_dispatchQueue, ^{
        
        if (playMode) {
        
            {
                __strong KxMovieViewController *strongSelf = weakSelf;
                if (!strongSelf) return;
                [strongSelf setDecoderPosition: position];
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
        
                __strong KxMovieViewController *strongSelf = weakSelf;
                if (strongSelf) {
                    [strongSelf setMoviePositionFromDecoder];
                    [strongSelf play];
                }
            });
            
        } else {

            {
                __strong KxMovieViewController *strongSelf = weakSelf;
                if (!strongSelf) return;
                [strongSelf setDecoderPosition: position];
                [strongSelf decodeFrames];
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                
                __strong KxMovieViewController *strongSelf = weakSelf;
                if (strongSelf) {
                
                    [strongSelf enableUpdateHUD];
                    [strongSelf setMoviePositionFromDecoder];
                    [strongSelf presentFrame];
                    [strongSelf updateHUD];
                }
            });
        }        
    });
}

- (void) freeBufferedFrames
{
    @synchronized(_videoFrames) {
        [_videoFrames removeAllObjects];
    }
    
    @synchronized(_audioFrames) {
        
        [_audioFrames removeAllObjects];
        _currentAudioFrame = nil;
    }
    
    if (_subtitles) {
        @synchronized(_subtitles) {
            [_subtitles removeAllObjects];
        }
    }
    
    _bufferedDuration = 0;
}

- (void) showInfoView: (BOOL) showInfo animated: (BOOL)animated
{
    if (!_tableView)
        [self createTableView];

    [self pause];
    
    CGSize size = self.view.bounds.size;
    CGFloat Y = _topHUD.bounds.size.height;
    
    if (showInfo) {
        
        _tableView.hidden = NO;
        
        if (animated) {
        
            [UIView animateWithDuration:0.4
                                  delay:0.0
                                options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionTransitionNone
                             animations:^{
                                 
                                 _tableView.frame = CGRectMake(0,Y,size.width,size.height - Y);
                             }
                             completion:nil];
        } else {
            
            _tableView.frame = CGRectMake(0,Y,size.width,size.height - Y);
        }
    
    } else {
        
        [self play];
        
        if (animated) {
            
            [UIView animateWithDuration:0.4
                                  delay:0.0
                                options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionTransitionNone
                             animations:^{
                                 
                                 _tableView.frame = CGRectMake(0,size.height,size.width,size.height - Y);
                                 
                             }
                             completion:^(BOOL f){
                                 
                                 if (f) {
                                     _tableView.hidden = YES;
                                 }
                             }];
        } else {
        
            _tableView.frame = CGRectMake(0,size.height,size.width,size.height - Y);
            _tableView.hidden = YES;
        }
    }
    
    _infoMode = showInfo;    
}

- (void) createTableView
{    
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth |UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleBottomMargin;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.hidden = YES;
    
    CGSize size = self.view.bounds.size;
    CGFloat Y = _topHUD.bounds.size.height;
    _tableView.frame = CGRectMake(0,size.height,size.width,size.height - Y);
    
    [self.view addSubview:_tableView];
    
}
- (void) createShowTableView
{
    _showTableView = [[UITableView alloc] initWithFrame:CGRectMake(KScreenWidth-100, 0, 100, KScreenHeight) style:UITableViewStyleGrouped];
    _showTableView.autoresizingMask = UIViewAutoresizingFlexibleWidth |UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleBottomMargin;
    _showTableView.delegate = self;
    _showTableView.dataSource = self;
    _showTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _showTableView.separatorColor = [UIColor colorWithWhite:0.3 alpha:1];
    _showTableView.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1];
    _showTableView.bounces = NO;
    _showTableView.hidden = NO;
    [self.view addSubview:_showTableView];
    
}

- (void) handleDecoderMovieError: (NSError *) error
{
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Failure", nil)
                                                        message:[error localizedDescription]
                                                       delegate:nil
                                              cancelButtonTitle:NSLocalizedString(@"Close", nil)
                                              otherButtonTitles:nil];
    
    [alertView show];
}

- (BOOL) interruptDecoder
{
    //if (!_decoder)
    //    return NO;
    return _interrupted;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return KxMovieInfoSectionCount;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
            
        case KxMovieInfoSectionGeneral:
            return NSLocalizedString(@"General", nil);
        case KxMovieInfoSectionMetadata:
            return NSLocalizedString(@"Metadata", nil);
        case KxMovieInfoSectionVideo: {
            NSArray *a = _decoder.info[@"video"];
            return a.count ? NSLocalizedString(@"Video", nil) : nil;
        }
        case KxMovieInfoSectionAudio: {
            NSArray *a = _decoder.info[@"audio"];
            return a.count ?  NSLocalizedString(@"Audio", nil) : nil;
        }
        case KxMovieInfoSectionSubtitles: {
            NSArray *a = _decoder.info[@"subtitles"];
            return a.count ? NSLocalizedString(@"Subtitles", nil) : nil;
        }
    }
    return @"";
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
            
        case KxMovieInfoSectionGeneral:
            return KxMovieInfoGeneralCount;
            
        case KxMovieInfoSectionMetadata: {
            NSDictionary *d = [_decoder.info valueForKey:@"metadata"];
            return d.count;
            
        }
            
        case KxMovieInfoSectionVideo: {
            NSArray *a = _decoder.info[@"video"];
            return a.count;
        }
            
        case KxMovieInfoSectionAudio: {
            NSArray *a = _decoder.info[@"audio"];
            return a.count;
        }
            
        case KxMovieInfoSectionSubtitles: {
            NSArray *a = _decoder.info[@"subtitles"];
            return a.count ? a.count + 1 : 0;
        }
            
        default:
            return 0;
    }
}

- (id) mkCell: (NSString *) cellIdentifier
    withStyle: (UITableViewCellStyle) style
{
    UITableViewCell *cell = [_tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:cellIdentifier];
    }
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell;
    
    if (indexPath.section == KxMovieInfoSectionGeneral) {
    
        if (indexPath.row == KxMovieInfoGeneralBitrate) {
            
            int bitrate = [_decoder.info[@"bitrate"] intValue];
            cell = [self mkCell:@"ValueCell" withStyle:UITableViewCellStyleValue1];
            cell.textLabel.text = NSLocalizedString(@"Bitrate", nil);
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%d kb/s",bitrate / 1000];
            
        } else if (indexPath.row == KxMovieInfoGeneralFormat) {

            NSString *format = _decoder.info[@"format"];
            cell = [self mkCell:@"ValueCell" withStyle:UITableViewCellStyleValue1];
            cell.textLabel.text = NSLocalizedString(@"Format", nil);
            cell.detailTextLabel.text = format ? format : @"-";
        }
        
    } else if (indexPath.section == KxMovieInfoSectionMetadata) {
      
        NSDictionary *d = _decoder.info[@"metadata"];
        NSString *key = d.allKeys[indexPath.row];
        cell = [self mkCell:@"ValueCell" withStyle:UITableViewCellStyleValue1];
        cell.textLabel.text = key.capitalizedString;
        cell.detailTextLabel.text = [d valueForKey:key];
        
    } else if (indexPath.section == KxMovieInfoSectionVideo) {
        
        NSArray *a = _decoder.info[@"video"];
        cell = [self mkCell:@"VideoCell" withStyle:UITableViewCellStyleValue1];
        cell.textLabel.text = a[indexPath.row];
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        cell.textLabel.numberOfLines = 2;

        
        
    } else if (indexPath.section == KxMovieInfoSectionAudio) {
        
        NSArray *a = _decoder.info[@"audio"];
        cell = [self mkCell:@"AudioCell" withStyle:UITableViewCellStyleValue1];
        cell.textLabel.text = a[indexPath.row];
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        cell.textLabel.numberOfLines = 2;
        BOOL selected = _decoder.selectedAudioStream == indexPath.row;
        cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        
    } else if (indexPath.section == KxMovieInfoSectionSubtitles) {
        
        NSArray *a = _decoder.info[@"subtitles"];
        
        cell = [self mkCell:@"SubtitleCell" withStyle:UITableViewCellStyleValue1];
        cell.textLabel.font = [UIFont systemFontOfSize:14];
        cell.textLabel.numberOfLines = 1;
        
        if (indexPath.row) {
            cell.textLabel.text = a[indexPath.row - 1];
        } else {
            cell.textLabel.text = NSLocalizedString(@"Disable", nil);
        }
        
        const BOOL selected = _decoder.selectedSubtitleStream == (indexPath.row - 1);
        cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    }
    
     cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == KxMovieInfoSectionVideo) {
        
        NSInteger selected = _decoder.selectedVideoStream;
        
        if (selected != indexPath.row) {
            
            _decoder.selectedVideoStream = indexPath.row;
            _decoder.selectedAudioStream = indexPath.row;
          //_decoder.selectedSubtitleStream = indexPath.row;
            NSInteger now = _decoder.selectedVideoStream;
            
            if (now == indexPath.row) {
                
                UITableViewCell *cell;
                
                cell = [_tableView cellForRowAtIndexPath:indexPath];
                cell.accessoryType = UITableViewCellAccessoryCheckmark;
                
                indexPath = [NSIndexPath indexPathForRow:selected inSection:KxMovieInfoSectionVideo];
                cell = [_tableView cellForRowAtIndexPath:indexPath];
                cell.accessoryType = UITableViewCellAccessoryNone;
            }
        }
        [self showInfoView: !_infoMode animated:YES];
    }
    else if (indexPath.section == KxMovieInfoSectionAudio) {
        
        NSInteger selected = _decoder.selectedAudioStream;
        
        if (selected != indexPath.row) {

            _decoder.selectedAudioStream = indexPath.row;
            NSInteger now = _decoder.selectedAudioStream;
            
            if (now == indexPath.row) {
            
                UITableViewCell *cell;
                
                cell = [_tableView cellForRowAtIndexPath:indexPath];
                cell.accessoryType = UITableViewCellAccessoryCheckmark;
                
                indexPath = [NSIndexPath indexPathForRow:selected inSection:KxMovieInfoSectionAudio];
                cell = [_tableView cellForRowAtIndexPath:indexPath];
                cell.accessoryType = UITableViewCellAccessoryNone;
            }
        }
        
    } else if (indexPath.section == KxMovieInfoSectionSubtitles) {
        
        NSInteger selected = _decoder.selectedSubtitleStream;
        
        if (selected != (indexPath.row - 1)) {
            
            _decoder.selectedSubtitleStream = indexPath.row - 1;
            NSInteger now = _decoder.selectedSubtitleStream;
            
            if (now == (indexPath.row - 1)) {
                
                UITableViewCell *cell;
                
                cell = [_tableView cellForRowAtIndexPath:indexPath];
                cell.accessoryType = UITableViewCellAccessoryCheckmark;
                
                indexPath = [NSIndexPath indexPathForRow:selected + 1 inSection:KxMovieInfoSectionSubtitles];
                cell = [_tableView cellForRowAtIndexPath:indexPath];
                
                cell.accessoryType = UITableViewCellAccessoryNone;
            }
            
            // clear subtitles
            _subtitlesLabel.text = nil;
            _subtitlesLabel.hidden = YES;
            @synchronized(_subtitles) {
                [_subtitles removeAllObjects];
            }
        }
    }
}

//支持旋转
-(BOOL)shouldAutorotate{
    return YES;
}

//支持的方向
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
     self.view.backgroundColor=[UIColor blackColor];
    
    return UIInterfaceOrientationMaskAll;
}

//一开始的方向  很重要
//-(UIInterfaceOrientation)preferredInterfaceOrientationForPresentation{
//    
//    self.view.backgroundColor=[UIColor blackColor];
//    return UIInterfaceOrientationLandscapeRight;
//}

//屏幕翻转调用的方法
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id <UIViewControllerTransitionCoordinator>)coordinator{
    
    // 翻转的时间
    CGFloat duration = [coordinator transitionDuration];
    
    [UIView animateWithDuration:duration animations:^{
        
       [_outputView dismiss];
        
    }];
    
    
}

@end

