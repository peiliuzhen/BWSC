//
//  BWSearchViewController.m
//  BWSC_AVS+_Player
//
//  Created by 裴留振 on 16/4/14.
//  Copyright © 2016年 裴留振. All rights reserved.
//

#import "BWSearchViewController.h"
#import "Masonry.h"
#import <SystemConfiguration/CaptiveNetwork.h>
#import "testSingleton.h"
#import "AFNetworking.h"
#import "getgateway.h"
#import <arpa/inet.h>
#import <netdb.h>
#import <netinet/in.h>
#import <netinet6/in6.h>
#import <ifaddrs.h>
#import <SystemConfiguration/SCNetworkReachability.h>
#include <sys/socket.h>
#import "ASProgressPopUpView.h"
#import "JQIndicatorView.h"
#define TIME 2.0f
#define sendTime 2.0f
#define lowstKHz 474000
#define highestKHz 826000
#define dateSpan 30//时间滚轮跨度
#define JQIndicatorDefaultSize CGSizeMake(50,50)


@interface BWSearchViewController ()<UICollectionViewDataSource,UICollectionViewDelegate,UITextFieldDelegate,ASProgressPopUpViewDataSource,UIPickerViewDataSource,UIPickerViewDelegate>
{
    MBProgressHUD *tmpHUD;
    NSMutableArray *_dataArray;
    NSTimer *timer;
    NSString *_urlStr;
    NSString *timeString;
    NSNumber * statusNum;
    UIImageView *failImageView;
    JQIndicatorView *indicator;
    JQIndicatorView *waitIndicator;

}
@property (nonatomic, strong) NSMutableData *responseData;
@property (nonatomic ,strong)UILabel *topLabel;
@property (nonatomic ,strong)UIView *backView;
@property (nonatomic ,strong)UIButton *manualButton;
@property (nonatomic ,strong)UIButton *autoButton;
@property (nonatomic ,strong)UICollectionView *collectionView;
//@property (nonatomic,weak) UIView * downView;
@property (nonatomic,weak) UIView * bgView;
@property (nonatomic ,strong)UILabel *searchLabel;
@property (nonatomic ,strong)UILabel *searchFailLabel;
@property (strong, nonatomic)  ASProgressPopUpView *progressView2;

@property (nonatomic ,assign)BOOL isConnect;
@property (nonatomic ,copy)NSString * wifiName;
@property (nonatomic ,copy)NSString * routerIP;
@property (nonatomic ,copy)NSString * baseUrl;

//搜索返回资源id
@property (nonatomic ,copy)NSString * idString;
//频点个数
@property (nonatomic ,assign)NSInteger menuNum;
@property (nonatomic ,assign)NSInteger pindianAdd;
@property (nonatomic ,copy)NSString * key;
//判断是否为搜索状态
@property (nonatomic ,assign)BOOL isSearching;
//存储缓存key
@property (nonatomic ,strong)NSMutableArray *keyArr;

@property (nonatomic ,strong)NSMutableDictionary *tmpDict;

@property (nonatomic, strong) UIView* selectView;
@property (nonatomic, strong) UIPickerView* pickerView;
@property (nonatomic, strong) UIPickerView* secPickView;
@property (nonatomic, strong) UIButton* sureBtn;
@property (nonatomic, strong) UIButton* cancelBtn;
@property(nonatomic,strong)NSMutableArray *startComponentData;//选择器第一列数据
@property(nonatomic,strong)NSMutableArray *stopComponentData;//选择器第二列数据
@property(nonatomic,copy)NSString *currentStart;//当前起始频率;
@property(nonatomic,copy)NSString *cureentStop;//当前终止频率;
@property (nonatomic ,strong) UILabel *startLabel;
@property (nonatomic ,strong) UILabel *stopLabel;
@property (nonatomic ,strong) UIView *showView;
@property (nonatomic ,copy)NSString *startString;
@property (nonatomic ,copy)NSString *stopString;
@property (nonatomic ,assign)NSInteger interval;
@property (nonatomic ,assign)NSInteger failNum;

@property (nonatomic ,strong)NSMutableDictionary *sendDict;
@end

@implementation BWSearchViewController

static NSString *cellName = @"Cell";

-(void)viewWillAppear:(BOOL)animated{
    
    [super viewWillAppear:animated];
    
    //_routerIP=KAppDelegate.routerIP;
    
    _baseUrl=[NSString stringWithFormat:@"http://%@:8800/",KAppDelegate.routerIP];
    
}

-(void)viewWillDisappear:(BOOL)animated{
    
    [super viewWillDisappear:animated];
    
    _isSearching=NO;
    
    _searchLabel.hidden=YES;
    
    _progressView2.hidden=YES;
    
    [tmpHUD hide:YES];

    if (timer) {
        
        [BWHttpRequest cancelNetworkingWithNetIdentifier:@"keepalive"];
        //如果定时器在运行
        if ([timer isValid]) {
            NSLog(@"搜索成功,取消定时器！！");
            [timer invalidate];
            //这行代码很关键
            timer=nil;
        }
    }
}
- (void)viewDidLoad {
    [super viewDidLoad];
    
    //注册通知(等待接收消息)
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(changeRouterIP2:) name:@"changeRouterIP" object:nil];
    
    [UIApplication sharedApplication].statusBarHidden=YES;
    
    self.sendDict=[NSMutableDictionary dictionary];
    
    [self.sendDict setValue:@"1" forKey:@"interval"];
    
    [self.sendDict setValue:@"0" forKey:@"failNum"];
    
    self.interval=1;
    self.failNum=0;
    
    //app运行时禁止锁屏
    [[UIApplication sharedApplication] setIdleTimerDisabled:YES];
    
    self.title=@"指尖TV";
    
    [self setAutomaticallyAdjustsScrollViewInsets:NO];
    
    self.navigationController.navigationBar.barTintColor=RGBA_MD(0, 150, 255, 1);
    
    self.view.backgroundColor=RGBA_MD(244, 244, 244, 1);
    
    _pindianAdd=0;
    
    _tmpDict=[NSMutableDictionary dictionary];

    
    //--设置导航栏字体大小
    [self.navigationController.navigationBar setTitleTextAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:IPhone4_5_6_6P(19, 20, 21, 22)],NSForegroundColorAttributeName:[UIColor whiteColor]}];
    
    self.navigationController.navigationBar.translucent = NO;
    
    self.navigationItem.backBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"" style:UIBarButtonItemStyleDone target:self action:nil];
    
    
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithImage:[UIImage imageNamed:@"back"] style:UIBarButtonItemStyleDone target:self action:@selector(backLastViewController:)];
    
    [self.navigationController.navigationBar setTintColor:[UIColor whiteColor]];
    
    _dataArray=[NSMutableArray array];
    
    _keyArr=[NSMutableArray array];
    
    _startComponentData=[NSMutableArray array];
    
    _stopComponentData=[NSMutableArray array];
    
    [self creatUI];
    
    [self setUpSelectView];
    
}

-(void)changeRouterIP2:(NSNotification *)sender{
    
    KAppDelegate.routerIP=sender.userInfo[@"routerIp"];
    KAppDelegate.isConnect=[sender.userInfo[@"isConnect"] boolValue];

    //_routerIP= KAppDelegate.routerIP;
    DLog(@"通知接收路由器地址--------------------------%@",KAppDelegate.routerIP);
    
    _baseUrl=[NSString stringWithFormat:@"http://%@:8800/",KAppDelegate.routerIP];

}

-(void)dealloc{
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"changeRouterIP" object:nil];

}

#pragma mark--搜索界面UI创建
-(void)creatUI{
    
    //topLabel
    _topLabel=[[UILabel alloc]init];
    
    _topLabel.textAlignment=NSTextAlignmentLeft;
    
    _topLabel.textColor=[UIColor grayColor];
    
    _topLabel.font=[UIFont fontWithName:@"Arial Rounded MT Bold" size:IPhone4_5_6_6P(18, 19, 20, 21)];
    
    _topLabel.text=@"搜索电视节目";
    
    [self.view addSubview:_topLabel];
    
    [_topLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        
        make.left.mas_equalTo(20);
        make.top.mas_equalTo(0);
        make.height.mas_equalTo(40);
        make.right.mas_equalTo(-20);
    }];
    
    //自定义布局初始化
    CustomerScaleLayout *layout = [[CustomerScaleLayout alloc] init];
    self.collectionView = [[UICollectionView alloc]initWithFrame:CGRectMake(64, 64, self.view.frame.size.width-100, self.view.frame.size.height-100) collectionViewLayout:layout];
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.collectionView.backgroundColor = RGBA_MD(220, 220, 220, 1);
    self.collectionView.decelerationRate = UIScrollViewDecelerationRateFast;
    //self.collectionView.pagingEnabled=YES;
    
    
    [self.view addSubview:self.collectionView];
    
    [_collectionView mas_makeConstraints:^(MASConstraintMaker *make) {
        
        make.top.equalTo(_topLabel.mas_bottom).offset(10);
        make.height.mas_equalTo(MDXFrom6(120));
        make.left.mas_equalTo(50);
        make.right.mas_equalTo(-50);
    }];
    //设置圆角
    _collectionView.layer.cornerRadius=15;
    
    _collectionView.layer.masksToBounds=YES;
    //注册
    [self.collectionView registerClass:[CustomerCollectionViewCell class] forCellWithReuseIdentifier:cellName];
    
    //底部view
    UIView *bottemView=[[UIView alloc]init];
    bottemView.layer.borderWidth = 1;
    bottemView.layer.borderColor = [RGBA_MD(220, 220, 220, 0.8) CGColor];
    [self.view addSubview:bottemView];
    
    [bottemView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.mas_equalTo(0);
        make.bottom.mas_equalTo(-40);
        make.height.mas_equalTo(40);
        make.right.mas_equalTo(0);
    }];
        //连接按钮
    _autoButton=[UIButton buttonWithType:UIButtonTypeCustom];
    
    [_autoButton setTitleColor:RGBA_MD(0, 150, 255, 1) forState:UIControlStateNormal];
        
    [_autoButton setTitle:@"自动搜索" forState:UIControlStateNormal];
    
    _autoButton.backgroundColor=[UIColor clearColor];
    
    _autoButton.titleLabel.textAlignment=NSTextAlignmentCenter;
    
    [_autoButton addTarget:self action:@selector(autoSearchBtn:) forControlEvents:UIControlEventTouchUpInside];
    
    [bottemView addSubview:_autoButton];
    
    [_autoButton mas_makeConstraints:^(MASConstraintMaker *make)
    {
        make.width.mas_equalTo(100);
        make.top.mas_equalTo(bottemView.mas_top);
        make.height.mas_equalTo(bottemView.mas_height);
        make.right.equalTo(bottemView.mas_centerX).offset(MDYFrom6(-50));
    }];
    
    //下一步按钮
    _manualButton=[UIButton buttonWithType:UIButtonTypeCustom];
    
    [_manualButton setTitle:@"区间搜索" forState:UIControlStateNormal];
    
    _manualButton.backgroundColor=[UIColor clearColor];
    
    _manualButton.titleLabel.textAlignment=NSTextAlignmentCenter;
    
        [_manualButton setTitleColor:RGBA_MD(0, 150, 255, 1) forState:UIControlStateNormal];
        
        [_manualButton addTarget:self action:@selector(manualSearchBtn:) forControlEvents:UIControlEventTouchUpInside];
    
    [bottemView addSubview:_manualButton];
    
    [_manualButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.width.mas_equalTo(100);
        make.top.mas_equalTo(bottemView.mas_top);
        make.height.mas_equalTo(bottemView.mas_height);
        make.left.equalTo(bottemView.mas_centerX).offset(MDYFrom6(50));
    }];
    
}

//搜索成功，显示搜索状态
-(void)creatSearchPrograssUI{
    
    self.progressView2 = [[ASProgressPopUpView alloc] init];
    self.progressView2.dataSource = self;
    self.progressView2.popUpViewCornerRadius = 12.0;
    self.progressView2.font = [UIFont systemFontOfSize:14];
    [self.progressView2 showPopUpViewAnimated:YES];
    self.progressView2.progress = 0.0;
    [self.view addSubview:self.progressView2];
    [self.progressView2 mas_makeConstraints:^(MASConstraintMaker *make) {
        
        make.top.equalTo(_collectionView.mas_bottom).offset(-1.0f);
        make.centerX.mas_equalTo(_collectionView.mas_centerX);
        make.width.equalTo(_collectionView.mas_width).offset(-30);
        make.height.mas_equalTo(MDXFrom6(2));
    }];
    
    _searchLabel=[[UILabel alloc]init];
    
    _searchLabel.textAlignment=NSTextAlignmentCenter;
    
    _searchLabel.textColor=[UIColor grayColor];
    
    _searchLabel.font=[UIFont systemFontOfSize:MDXFrom6(20.0f)];
    
    _searchLabel.text=[NSString stringWithFormat:@"已搜索到%u个节目",(NSInteger)_dataArray.count];
    
    [self.view addSubview:_searchLabel];
    
    [_searchLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        
        make.top.equalTo(self.progressView2.mas_bottom).offset(8.0f);
        make.height.mas_equalTo(30);
        make.centerX.mas_equalTo(_collectionView.mas_centerX);
        make.width.mas_equalTo(_collectionView.mas_width);
    }];

    /*
    _tmpProgressView = [[LDProgressView alloc] init];
    _tmpProgressView.color = RGBA_MD(0, 107, 255, 1);
    _tmpProgressView.flat = @YES;
    _tmpProgressView.progress = 0;
    _tmpProgressView.animate = @YES;
    
    [self.view addSubview:_tmpProgressView];
    
    [_tmpProgressView mas_makeConstraints:^(MASConstraintMaker *make) {
        
        make.top.equalTo(_searchLabel.mas_bottom).offset(0.0f);
        make.centerX.mas_equalTo(_searchLabel.mas_centerX);
        make.width.mas_equalTo(_searchLabel.mas_width);
        make.height.mas_equalTo(MDXFrom6(2));
    }];
     */
    
    indicator = [[JQIndicatorView alloc] initWithType:0 tintColor:RGBA_MD(0, 150, 255, 1) size:CGSizeMake(MDXFrom6(50), MDXFrom6(50))];
    
    indicator.center = _collectionView.center;
    
    [self.view addSubview:indicator];
    
    [indicator mas_makeConstraints:^(MASConstraintMaker *make) {
        
        make.centerX.equalTo(_collectionView.mas_centerX).offset(MDXFrom6(25));
        make.centerY.equalTo(_collectionView.mas_centerY).offset(MDXFrom6(25));
        make.width.mas_equalTo(MDXFrom6(50));
        make.height.mas_equalTo(MDXFrom6(50));
    }];
    
    [indicator startAnimating];
    
}

//电视宝连接错误，手动搜索失败
-(void)showSearchFieldUI{
    
    _isSearching=NO;
    
    _searchLabel.hidden=YES;
    
    _searchFailLabel=[[UILabel alloc]init];
    
    _searchFailLabel.textAlignment=NSTextAlignmentCenter;
    
    _searchFailLabel.textColor=[UIColor grayColor];
    
    _searchFailLabel.font=[UIFont systemFontOfSize:MDXFrom6(20.0f)];
    
    _searchFailLabel.text=@"搜索失败!";
    
    [self.view addSubview:_searchFailLabel];
    
    [_searchFailLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        
        make.top.equalTo(_collectionView.mas_bottom).offset(5.0f);
        make.height.mas_equalTo(30);
        make.centerX.mas_equalTo(_collectionView.mas_centerX);
        make.width.mas_equalTo(_collectionView.mas_width);
    }];
    
    failImageView=[[UIImageView alloc]init];
    
    failImageView.backgroundColor=[UIColor clearColor];
    
    failImageView.image=[UIImage imageNamed:@"fail"];
    
    [_collectionView addSubview:failImageView];
    
    [failImageView mas_makeConstraints:^(MASConstraintMaker *make) {
    
        make.centerX.mas_equalTo(_collectionView.mas_centerX);
        make.centerY.mas_equalTo(_collectionView.mas_centerY);
        make.width.mas_equalTo(58);
        make.height.mas_equalTo(74);
    }];

}

-(void)backLastViewController:(UIBarButtonItem *)sender{
    
    if (_isSearching==YES) {
        
//        //关闭定时器
//        if (timer) {
//            //如果定时器在运行
//            if ([timer isValid]) {
//                
//                [timer setFireDate:[NSDate distantFuture]];
//            }
//        }
        NSLog(@"返回");
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"提示" message:@"确定要结束搜索并前往节目表吗?" preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleDefault handler:nil];
        
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
           
            [self okActionTouchUpInside];
        }];
        
        [alertController addAction:cancelAction];
        [alertController addAction:okAction];
        
        [self presentViewController:alertController animated:YES completion:nil];
        
    }else{
        
        [self.navigationController popViewControllerAnimated:YES];
    }
}

-(void)okActionTouchUpInside{
    
    if (timer) {
        //如果定时器在运行
        if ([timer isValid]) {
            NSLog(@"搜索成功,取消定时器！！");
            [timer invalidate];
            //这行代码很关键
            timer=nil;
        }
    }
    
    NSString *urlStr=[NSString stringWithFormat:@"%@stop",_baseUrl];
    
    NSDictionary *dict=@{@"id":[NSString stringWithFormat:@"%@",_idString]};
    
    [BWHttpRequest postWithUrl:urlStr params:dict netIdentifier:@"stop" success:^(id response) {
        
       NSNumber * statusNum1 = @([response[@"status"] integerValue]);
        
        if ([statusNum1 isEqualToNumber:@(0)]) {
            
//            [p removeFromSuperview];
            
            if (self.popTimeStringBlock) {
                
                self.popTimeStringBlock(timeString);
            }
            
            NSLog(@"结束搜索");
        }else if ([statusNum1 isEqualToNumber:@(1)]){
            
            [LCProgressHUD showMessage:@"数据不合法"];
            [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
        }
        
    } fail:^(NSError *error) {
        
        NSLog(@"--%@",error.description);
        
        NSLog(@"---结束搜索失败");
        
    } showHUD:NO];
    
    [self.navigationController popViewControllerAnimated:YES];
}

-(NSMutableData *)responseData
{
    if (_responseData == nil) {
    _responseData = [NSMutableData data];
    }
    return _responseData;
}

////////////////////////////////////
//获取系统当前时间，记录为请求时间
- (NSString *)getCurrentTime {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSString *dateTime = [formatter stringFromDate:[NSDate date]];
    return dateTime;
}

-(void)creatSearchWiatUI{
    
    waitIndicator = [[JQIndicatorView alloc] initWithType:1 tintColor:[UIColor orangeColor] size:CGSizeMake(MDXFrom6(100), MDXFrom6(200))];
    
    waitIndicator.center = _collectionView.center;
    
    [_collectionView addSubview:waitIndicator];
    
    [waitIndicator mas_makeConstraints:^(MASConstraintMaker *make) {
        
        make.centerX.equalTo(_collectionView.mas_centerX).offset(100);
        make.centerY.equalTo(_collectionView.mas_centerY).offset(50);
        make.width.mas_equalTo(200);
        make.height.mas_equalTo(100);
    }];
    
    [waitIndicator startAnimating];
}

#pragma mark--点击自动搜索按钮方法---
-(void)autoSearchBtn:(UIButton *)sender{
        
    NSLog(@"自动搜索");
    
    [_searchFailLabel removeFromSuperview];
    
    [failImageView removeFromSuperview];
    
     _searchFailLabel.hidden=YES;
    
    _wifiName=[self getCurrentWifiName];
    
    if([_wifiName hasPrefix:BWStr] || [_wifiName hasPrefix:NSStr]){
        
        _isConnect=YES;
        
        [self creatSearchWiatUI];
        
        NSString *urlStr=[NSString stringWithFormat:@"%@search",_baseUrl];
        
        timeString=[self getCurrentTime];
        
        NSLog(@"请求时间:%@",timeString);
        
        NSDictionary *dict=@{@"frequency":@"474000-826000",@"timestamp":timeString};
        
        //搜索状态关闭用户交互
        [self closeUserInteractionEnabled];

        [BWHttpRequest postWithUrl:urlStr params:dict netIdentifier:@"search" success:^(id response) {
            
            [waitIndicator stopAnimating];
            
            [waitIndicator removeFromSuperview];
            
            [self openUserInteractionEnabled];
            
            _idString=response[@"id"];
            
            NSLog(@"搜索节目id:%@",_idString);
            
            _urlStr=[NSString stringWithFormat:@"%@menu?frequency=474000-826000&timestamp=%@",_baseUrl,timeString];
            
            
            statusNum = @([response[@"status"] integerValue]);
            
            NSLog(@"%@",statusNum);

            
           if ([statusNum isEqualToNumber:@(0)]) {
               
               [BWListCache clearCacheListData:^{
                   
                   
               }];
               
                [self requestSuccessMothed];
               
           }else if([statusNum isEqualToNumber:@(-2)]){
               
               [LCProgressHUD showMessage:@"设备初始化,请稍后"];
               [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
               
           }else if ([statusNum isEqualToNumber:@(4)]){
               
               [LCProgressHUD showMessage:@"其他用户正在观看不同频点节目"];
               [NSTimer scheduledTimerWithTimeInterval:TIME target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
               
           }else if ([statusNum isEqualToNumber:@(3)]){
               
               [LCProgressHUD showMessage:@"其他用户正在搜索节目"];
               [NSTimer scheduledTimerWithTimeInterval:TIME target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
               
           }else if ([statusNum isEqualToNumber:@(5)]){
               
               [LCProgressHUD showMessage:@"请3秒后再搜索"];
               [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
               
           }
            
        } fail:^(NSError *error) {

            NSLog(@"请求失败:%@", error.description);
            
            [waitIndicator stopAnimating];
            
            [waitIndicator removeFromSuperview];
            
            NSString *errorStr=[RequestSever getMsgWithError:error];
            
            UIAlertController * alertController = [UIAlertController alertControllerWithTitle:@"搜索失败" message:errorStr preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDestructive handler:nil];
            
            [alertController addAction:cancelAction];
            
            [self presentViewController:alertController animated:YES completion:nil];
            
            [self requestFailMothed];
            
        } showHUD:NO];
    }
    else{
        
        _isConnect=NO;
        
        [LCProgressHUD showMessage:@"连接网关错误,请检查wifi连接"];
        [NSTimer scheduledTimerWithTimeInterval:TIME target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
    }
}

#pragma mark--手动搜索按钮
-(void)manualSearchBtn:(UIButton *)sender{
    
    NSLog(@"手动搜索");
    [_searchFailLabel removeFromSuperview];
    
    [failImageView removeFromSuperview];
    
    _wifiName=[self getCurrentWifiName];
    
    if([_wifiName hasPrefix:BWStr] || [_wifiName hasPrefix:NSStr]){
        
        //[self creatDownViewUI];
        [UIView animateWithDuration:0.2 animations:^{
            
            _selectView.frame = CGRectMake(0, KScreenHeight/2-30-44, KScreenWidth, KScreenHeight/2+30);
        }];
        for (NSInteger i=474000; i<=826000; i+=8000) {
            
            [_startComponentData addObject:[NSString stringWithFormat:@"%u",i]];
            [_stopComponentData addObject:[NSString stringWithFormat:@"%u",i]];
        }
        [_secPickView removeFromSuperview];
        [_selectView addSubview:_pickerView];
        [_pickerView becomeFirstResponder];
        //_selectView.hidden = !_selectView.hidden;
        
    }else{
        
        [LCProgressHUD showMessage:@"连接网关错误,请检查wifi连接"];
        [NSTimer scheduledTimerWithTimeInterval:TIME target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
    }
}

#pragma mark--创建手动搜索视图
- (void)setUpSelectView
{
    if (_selectView == nil) {
        
        _selectView = [[UIView alloc] initWithFrame:CGRectMake(0, KScreenHeight, KScreenWidth, KScreenHeight/2+30)];
        _selectView.backgroundColor = [UIColor whiteColor];
        //_selectView.hidden = YES;
        [self.view addSubview:_selectView];
        [self.view bringSubviewToFront:_selectView];
        
    }
    if (_cancelBtn == nil) {
        
        _cancelBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        _cancelBtn.frame = CGRectMake(MDXFrom6(50), 0, 60, 30);
        [_cancelBtn setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
        _cancelBtn.titleLabel.font=[UIFont systemFontOfSize:MDXFrom6(24)];
        [_cancelBtn setTitle:@"取消" forState:UIControlStateNormal];
        _cancelBtn.titleLabel.textAlignment=NSTextAlignmentCenter;
        [_cancelBtn addTarget:self action:@selector(cancelBtnEvent) forControlEvents:UIControlEventTouchUpInside];
        [_selectView addSubview:_cancelBtn];
        
    }
    if (_sureBtn == nil) {
        
        _sureBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        _sureBtn.frame = CGRectMake(KScreenWidth -MDXFrom6(50)-80, 0, 60, 30);
        [_sureBtn setTitle:@"确定" forState:UIControlStateNormal];
        _sureBtn.titleLabel.textAlignment=NSTextAlignmentCenter;
        _sureBtn.titleLabel.font=[UIFont systemFontOfSize:MDXFrom6(24)];
        [_sureBtn setTitleColor:RGB_MD(0, 150, 255) forState:UIControlStateNormal];
        [_sureBtn addTarget:self action:@selector(sureBtnEvent:) forControlEvents:UIControlEventTouchUpInside];
        [_selectView addSubview:_sureBtn];
        
    }
    if (_showView == nil) {
        
        _showView=[[UIView alloc]initWithFrame:CGRectMake(0, 30, KScreenWidth, 30)];
        _showView.backgroundColor=[UIColor whiteColor];
        [_selectView addSubview:_showView];
    }
    if (_startLabel==nil) {
        
        _startLabel=[[UILabel alloc]initWithFrame:CGRectMake(MDXFrom6(50), 0, KScreenWidth/2-MDXFrom6(50), 30)];
        _startLabel.backgroundColor=[UIColor whiteColor];
        _startLabel.text=@"选择起始频率(Hz)";
        _startLabel.textAlignment=NSTextAlignmentCenter;
        _startLabel.textColor=[UIColor grayColor];
        _startLabel.font=[UIFont systemFontOfSize:MDXFrom6(20)];
        [_showView addSubview:_startLabel];
        
    }
    if (_stopLabel==nil) {
        
        _stopLabel=[[UILabel alloc]initWithFrame:CGRectMake(KScreenWidth/2, 0, KScreenWidth/2-MDXFrom6(50), 30)];
        _stopLabel.backgroundColor=[UIColor whiteColor];
        _stopLabel.text=@"选择终止频率(Hz)";
        _stopLabel.textAlignment=NSTextAlignmentCenter;
        _stopLabel.textColor=[UIColor grayColor];
        _stopLabel.font=[UIFont systemFontOfSize:MDXFrom6(20)];
        [_showView addSubview:_stopLabel];
        
    }
    
    if (_pickerView == nil) {
        
        _pickerView = [[UIPickerView alloc] initWithFrame:CGRectMake(0, 60, KScreenWidth, KScreenHeight/2-30)];
        _pickerView.delegate = self;
        _pickerView.dataSource = self;
        _pickerView.showsSelectionIndicator = YES;
        [_secPickView selectRow:0 inComponent:0 animated:YES];
        _pickerView.backgroundColor = [UIColor whiteColor];
        
        
    }
    
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    if (![touch.view isEqual:self.selectView]) {
        
        [UIView animateWithDuration:0.2 animations:^{
            
            _selectView.frame = CGRectMake(0, KScreenHeight, KScreenWidth, KScreenHeight/2+30);
        }];

    }
}

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView*)pickerView
{
    return 2;
}
- (NSInteger)pickerView:(UIPickerView*)pickerView numberOfRowsInComponent:(NSInteger)component
{
    if (component==0) {
        
        return _startComponentData.count;
        
    }else{
        
        return _stopComponentData.count;
    }
    
}

-(NSInteger)selectedRowInComponent:(NSInteger)component{
    
    return 2;
}
- (CGFloat)pickerView:(UIPickerView *)pickerView rowHeightForComponent:(NSInteger)component {
    return 30;
}
#pragma mark 实现协议UIPickerViewDelegate方法
- (NSString*)pickerView:(UIPickerView*)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component
{
    if (component==0) {
        
        return [self.startComponentData objectAtIndex:row];
        
    }else{
        
        return [self.stopComponentData objectAtIndex:row];
    }
}
- (UIView *)pickerView:(UIPickerView *)pickerView viewForRow:(NSInteger)row forComponent:(NSInteger)component reusingView:(UIView *)view{
    
    UILabel* pickerLabel = (UILabel*)view;
    if (!pickerLabel){
        pickerLabel = [[UILabel alloc] init];
        pickerLabel.adjustsFontSizeToFitWidth = YES;
        [pickerLabel setTextAlignment:NSTextAlignmentCenter];
        [pickerLabel setBackgroundColor:[UIColor clearColor]];
        [pickerLabel setFont:[UIFont boldSystemFontOfSize:MDXFrom6(24)]];
    }
     pickerLabel.text=[self pickerView:pickerView titleForRow:row forComponent:component];
    // Fill the label text here
   
    return pickerLabel;
}
-(void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component{
    
    if (component == 0) {
        
        [pickerView reloadComponent:1];
        
        [pickerView selectRow:row inComponent:1 animated:NO];
        
    }
}
- (void)cancelBtnEvent
{
    [UIView animateWithDuration:0.2 animations:^{
        
        _selectView.frame = CGRectMake(0, KScreenHeight, KScreenWidth, KScreenHeight/2+30);
    }];
}
- (void)sureBtnEvent:(UIButton*)sender
{
    
    NSInteger row1 = [self.pickerView selectedRowInComponent:0];
    NSInteger row2 = [self.pickerView selectedRowInComponent:1];
    
    _startString=[self.startComponentData objectAtIndex:row1];
    _stopString = [self.stopComponentData objectAtIndex:row2];
    //
    NSLog(@"%@-%@",_startString,_stopString);
    
    if (_startString && _stopString && [_startString intValue]>[_stopString intValue]){
        
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:nil message:@"终止频率不能低于起始频率" delegate:nil cancelButtonTitle:@"好的" otherButtonTitles:nil];
        [alert show];
        alert=nil;
        
    }else{
        
        [UIView animateWithDuration:0.2 animations:^{
            
            _selectView.frame = CGRectMake(0, KScreenHeight, KScreenWidth, KScreenHeight/2+30);
        }];
        
        _wifiName=[self getCurrentWifiName];
        
        if([_wifiName hasPrefix:BWStr] || [_wifiName hasPrefix:NSStr]){
            
            _isConnect=YES;
            
            [self creatSearchWiatUI];
            
            NSString *urlStr=[NSString stringWithFormat:@"%@search",_baseUrl];
            
            _isSearching=YES;
            
            //获取当前时间
            timeString=[self getCurrentTime];
            
            NSLog(@"%@",timeString);
            
            NSDictionary *dict=@{@"frequency":[NSString stringWithFormat:@"%@-%@",_startString,_stopString],@"timestamp":timeString};
            
            [BWHttpRequest postWithUrl:urlStr params:dict netIdentifier:@"search" success:^(id response) {
                
                [waitIndicator stopAnimating];
                
                [waitIndicator removeFromSuperview];

                
                if ([_getStatus isEqualToNumber:@(2)]) {
                    
                    [BWListCache clearCacheListData:^{
                        
                        NSLog(@"清除之前的缓存");
                    }];

                }
                
                _idString=response[@"id"];
                NSLog(@"资源id:%@",_idString);
                
                _urlStr=[NSString stringWithFormat:@"%@menu?frequency=%@-%@&timestamp=%@",_baseUrl,_startString,_stopString,timeString];
                
                statusNum = @([response[@"status"] integerValue]);
                
                NSLog(@"%@",statusNum);
                
                [self requestSuccessMothed];
                
            } fail:^(NSError *error) {
                
                NSLog(@"请求失败:%@", error.description);
                
                [waitIndicator stopAnimating];
                
                [waitIndicator removeFromSuperview];
                
                NSString *errorStr=[RequestSever getMsgWithError:error];
                
                UIAlertController * alertController = [UIAlertController alertControllerWithTitle:@"搜索失败" message:errorStr preferredStyle:UIAlertControllerStyleAlert];
                
                UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDestructive handler:nil];
                
                [alertController addAction:cancelAction];
                
                [self presentViewController:alertController animated:YES completion:nil];
                
                [self requestFailMothed];
                
            } showHUD:NO];
        }
        else{
            _isConnect=NO;
            
            [self showSearchFieldUI];
            
            [LCProgressHUD showMessage:@"连接网关错误,请检查wifi连接"];
            
            [NSTimer scheduledTimerWithTimeInterval:TIME target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
        }
        
    }
    
}

#pragma mark--发送节目搜索请求失败方法
-(void)requestFailMothed{
    
    [_searchLabel removeFromSuperview];
    
    [_progressView2 removeFromSuperview];
    
    _isSearching=NO;
    //搜索失败开启用户交互
    [self openUserInteractionEnabled];
    
    [tmpHUD hide:YES];
    
    [indicator stopAnimating];
    
    [indicator removeFromSuperview];
    
    [_dataArray removeAllObjects];
    
    [_collectionView reloadData];
    
    [self showSearchFieldUI];
    
    NSString *urlStr=[NSString stringWithFormat:@"%@stop",_baseUrl];
    
    NSDictionary *dict=@{@"id":[NSString stringWithFormat:@"%@",_idString]};
    
    [BWHttpRequest postWithUrl:urlStr params:dict netIdentifier:@"stop" success:^(id response) {
        
        NSLog(@"自动搜索失败啦");
        NSNumber * statusNum1 = @([response[@"status"] integerValue]);
        
        if ([statusNum1 isEqualToNumber:@(0)]) {
            
            
        }else if ([statusNum1 isEqualToNumber:@(1)]){
            
            [LCProgressHUD showMessage:@"数据不合法"];
            [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
        }

    } fail:^(NSError *error) {
        
        NSLog(@"--%@",error.description);
        
        
        
    } showHUD:NO];


}

#pragma mark--发送节目搜索请求成功方法
-(void)requestSuccessMothed{

    
    if ([statusNum isEqualToNumber:@(0)]) {
        
        _isSearching=YES;
        
        [self creatSearchPrograssUI];
        
        //搜索状态关闭用户交互
        [self closeUserInteractionEnabled];
//        [BWListCache clearCacheListData:^{
//            
//            NSLog(@"清除之前的缓存");
//        }];

        if (!timer) {
            
            timer = [NSTimer scheduledTimerWithTimeInterval:self.interval target:self selector:@selector(reloop) userInfo:nil repeats:YES];
        }
        
        [timer fire];
        
    }else if ([statusNum isEqualToNumber:@(4)]){
        
        _isSearching=NO;
        [LCProgressHUD showMessage:@"其他用户正在观看节目"];
        [NSTimer scheduledTimerWithTimeInterval:TIME target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
        
        
    }else if ([statusNum isEqualToNumber:@(3)]){
        
        _isSearching=NO;
        [LCProgressHUD showMessage:@"其他用户正在搜索节目"];
        [NSTimer scheduledTimerWithTimeInterval:TIME target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
        
    }else if ([statusNum isEqualToNumber:@(5)]){
        
        _isSearching=NO;
        [LCProgressHUD showMessage:@"请3秒后再搜索"];
        [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
        
    }else if ([statusNum isEqualToNumber:@(-2)]){
        
        _isSearching=NO;
        [LCProgressHUD showMessage:@"设备正在初始化,请稍后"];
        [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
        
    }
}

#pragma  mark--管理搜索按钮的用户交互
-(void)closeUserInteractionEnabled{
    
    //搜索状态关闭用户交互
    _autoButton.userInteractionEnabled=NO;
    
    _manualButton.userInteractionEnabled=NO;
    
    [_autoButton setTitleColor:RGBA_MD(220, 220, 220, 1) forState:UIControlStateNormal];
    
    [_manualButton setTitleColor:RGBA_MD(220, 220, 220, 1) forState:UIControlStateNormal];
}

-(void)openUserInteractionEnabled{
    
    _autoButton.userInteractionEnabled=YES;
    
    _manualButton.userInteractionEnabled=YES;
    
    [_autoButton setTitleColor:RGBA_MD(0, 150, 255, 1) forState:UIControlStateNormal];
    
    [_manualButton setTitleColor:RGBA_MD(0, 150, 255, 1) forState:UIControlStateNormal];

    
}
#pragma mark - Timer

- (BOOL)progressViewShouldPreCalculatePopUpViewSize:(ASProgressPopUpView *)progressView;
{
    return NO;
}
- (void)progress
{
    if (self.progressView2.progress >= 1.0) {
            }
    
    float progress = self.progressView2.progress;
    if (progress < 1.0) {
        
        progress +=0.005;
        
        [self.progressView2 setProgress:progress animated:YES];
        
        [NSTimer scheduledTimerWithTimeInterval:0.05
                                         target:self
                                       selector:@selector(progress)
                                       userInfo:nil
                                        repeats:NO];
    }
}
#pragma mark - ASProgressPopUpView dataSource

// <ASProgressPopUpViewDataSource> is entirely optional
// it allows you to supply custom NSStrings to ASProgressPopUpView
- (NSString *)progressView:(ASProgressPopUpView *)progressView stringForProgress:(float)progress
{
    NSString *s;
    return s;
}

#pragma mark--节目搜索循环发送请求
-(void)reloop{
    
    NSLog(@"搜索状态不断发送报文心跳");
    
    NSString *urlStr=[NSString stringWithFormat:@"%@keepalive",_baseUrl];
    
    NSString *timeStr=[self getCurrentTime];
    
    NSDictionary *dict=@{@"id":[NSString stringWithFormat:@"%@",_idString],@"time":timeStr};
    
    [BWHttpRequest postWithUrl:urlStr params:dict netIdentifier:@"keepalive" success:^(id response) {
        
        NSLog(@"请求成功");
        
        NSNumber * statusNum2 = @([response[@"status"] integerValue]);
        
        if ([statusNum2 isEqualToNumber:@(0)]) {
            
            
        }else if ([statusNum2 isEqualToNumber:@(2)]){
            
            NSLog(@"获取资源id失败");
        }else if([statusNum2 isEqualToNumber:@(1)]){
            
            [LCProgressHUD showMessage:@"非法操作"];
            [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
        }else if([statusNum2 isEqualToNumber:@(-2)]){
            
            [LCProgressHUD showMessage:@"设备初始化,请稍后"];
            [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideHUD) userInfo:nil repeats:NO];
        }
        
    } fail:^(NSError *error) {
        
        NSLog(@"请求失败");
        
    } showHUD:NO];

    
    [_dataArray removeAllObjects];
    
    
    [BWHttpRequest getWithUrl:_urlStr params:nil netIdentifier:@"menu" success:^(id response) {
        
        self.interval=1;
        
        self.failNum=0;

        NSArray *tmpArr=response[@"menu"];
        
        //频段内频点总个数
        _menuNum=tmpArr.count;
        
        NSLog(@"_menuNum:%d",_menuNum);
        
        [tmpArr enumerateObjectsUsingBlock:^(NSDictionary * obj, NSUInteger idx, BOOL *stop) {
            
            NSDictionary *dict=[NSDictionary dictionaryWithDictionary:obj];
            
            NSArray *subArr=[NSArray arrayWithArray:[dict objectForKey:@"submenu"]];
            
            _key=[dict objectForKey:@"frequency"];
            //解析出的频点时间戳
            NSString *timestamp=[dict objectForKey:@"timestamp"];
            
            NSLog(@"timestamp:%@",timestamp);
            
            if(_menuNum==0){
                
                _progressView2.progress=1.0;
                
                if (timer) {
                    //如果定时器在运行
                    if ([timer isValid]) {
                        NSLog(@"单击停止按钮，取消定时器！！");
                        [timer invalidate];
                        //这行代码很关键
                        timer=nil;
                        
                    }
                    [self openUserInteractionEnabled];

                }
                [self requestFailMothed];
            }
            else{
                
                //判断时间戳是否是当前时间戳
                if ([timestamp isEqualToString:timeString]) {
                    
                    
                    [_tmpDict setObject:dict forKey:[NSString stringWithFormat:@"%d",idx]];
                    
                    _pindianAdd=_tmpDict.count;
                    
                     NSLog(@"_pindianAdd:%d",_pindianAdd);
                    
                   // _progressView2.progress=1.0*_pindianAdd/_menuNum;
                    
                    [self.progressView2 setProgress:1.0*_pindianAdd/_menuNum animated:YES];
                    
                    if (subArr.count!=0) {
                        
                        //缓存的文件夹路径
                        NSString *path = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
                        
                        NSString *filePath = [path stringByAppendingPathComponent:@"com.bwsctv.listDataCache"];
                        
                        NSString *cacheFilePath = [filePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist",_key]];
                        
                        NSFileManager *fileManager = [[NSFileManager alloc] init];
                        
                        NSArray *contents = [fileManager contentsOfDirectoryAtPath:filePath error:nil];
                        
                        for (id obj in contents) {
                            
                            //获取文件路径
                            NSString *filePath1 = [filePath stringByAppendingPathComponent:obj];
                            
                            if(filePath1==cacheFilePath){
                                
                                [fileManager removeItemAtPath:filePath1 error:nil];
                            }
                            
                        }
                        
                        [fileManager removeItemAtPath:cacheFilePath error:nil];
                        
                        NSLog(@"已清除旧的缓存");
                        
                        //                    NSArray *contents = [fileManager contentsOfDirectoryAtPath:filePath error:nil];
                        //
                        //
                        //
                        //                    _pindianAdd=contents.count;
                        //
                        //                    NSLog(@"count:%d",contents.count);
                        //
                        //                    NSLog(@"_pindianAdd:%d",_pindianAdd);
                        
                        [BWListCache setObjectOfDic:dict key:[NSString stringWithFormat:@"%@",_key]];
                        NSLog(@"写入缓存");
                        NSLog(@"缓存的key:%@",_key);
                        
                        [_keyArr addObject:[NSString stringWithFormat:@"%@",_key]];
                        
                        if (self.popKeyArrBlock) {
                            
                            self.popKeyArrBlock(_keyArr);
                        }
                        
                        //获取缓存信息
                        NSDictionary *dic=[BWListCache cacheDicForKey:[NSString stringWithFormat:@"%@",_key]];
                        
                        NSArray *subArr=[NSArray arrayWithArray:[dic objectForKey:@"submenu"]];
                        
                        NSString *frequency=[dic objectForKey:@"frequency"];
                        
                        NSString *timestamp1=[dic objectForKey:@"timestamp"];
                        
                        NSLog(@"frequency=%@",frequency);
                        
                        //__weak typeof(self)weakSelf=self;
                        
                        [subArr enumerateObjectsUsingBlock:^(NSDictionary *obj1, NSUInteger idx1, BOOL * _Nonnull stop1) {
                            
                            NSMutableDictionary *dict1=[NSMutableDictionary dictionaryWithDictionary:obj1];
                            
                            for (id obj2 in obj1) {
                                
                                [dict1 setObject:[obj1 objectForKey:obj2] forKey:obj2];
                            }
                            [dict1 setObject:frequency forKey:@"frequency"];
                            [dict1 setObject:timestamp1 forKey:@"timestamp"];
                            
                            ProgramModel *model=[[ProgramModel alloc]initWithDictionary:dict1];
                            
                            [_dataArray addObject:model];
                            if (_dataArray.count>0) {
                                
                                [indicator stopAnimating];
                                
                                [indicator removeFromSuperview];

                            }
                            
                            _searchLabel.text=[NSString stringWithFormat:@"已搜索到%d个节目",_dataArray.count];
                            
                            NSLog(@"name=%@",model.name);
                            NSLog(@"frequency=%@",model.frequency);
                            NSLog(@"timestamp=%@",model.timestamp);
                            
                            [self.collectionView reloadData];
                        }];

                    }
                    
                }
                
            }
        }];

    } fail:^(NSError *error) {
        
        NSLog(@"%@请求失败:%@",self,error.description);
        
        self.interval=0.2;
        
        if (self.failNum<=30) {
            
            self.failNum++;
        }else{
            
            self.failNum=0;
            
            if (timer) {
                //如果定时器在运行
                if ([timer isValid]) {
                    NSLog(@"取消定时器！！");
                    [timer invalidate];
                    //这行代码很关键
                    timer=nil;
                }
            }
            [self requestFailMothed];
        }
        
        
        
        
        
    } showHUD:NO];
    
    //判断定时器是否终止
    NSLog(@"_menuNum:%d",_menuNum);
    NSLog(@"_pindianAdd:%d",_pindianAdd);
    
    if (_menuNum!=0 && _pindianAdd!=0 && _pindianAdd==_menuNum) {
       
        _progressView2.progress=1.0;
        
        _isSearching=NO;
        
        [self openUserInteractionEnabled];
        
        [_autoButton setTitleColor:RGBA_MD(0, 150, 255, 1) forState:UIControlStateNormal];
        
        [_manualButton setTitleColor:RGBA_MD(0, 150, 255, 1) forState:UIControlStateNormal];

        _searchLabel.hidden=YES;
        
        _progressView2.hidden=YES;
        
        [tmpHUD hide:YES];
        
        if (timer) {
            //如果定时器在运行
            if ([timer isValid]) {
                NSLog(@"搜索成功,取消定时器！！");
                [timer invalidate];
                //这行代码很关键
                timer=nil;
            }
        }
//        [p removeFromSuperview];
        
        [self.navigationController popViewControllerAnimated:YES];
        
        if (self.popTimeStringBlock) {
            
            self.popTimeStringBlock(timeString);
        }
    }
    else{
        
        NSLog(@"搜索未完成");
    }
}
- (void)hideHUD {
    
    [LCProgressHUD hide];
}

#pragma mark --collectionView代理方法
-(NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return _dataArray.count;
    //return 100;
}

-(UICollectionViewCell*)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    ProgramModel *model = nil;
    
    if (_dataArray.count > indexPath.item) {
        
        model = _dataArray[indexPath.item];
    }
    
    CustomerCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:cellName forIndexPath:indexPath];
    
    //使用自定义cell
    // -- 绑定数据
    [cell bindDataWithProgramModel:model];

    return cell;
}

//cell的点击方法
-(void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    NSLog(@"点我也没用");
}

-(BOOL)collectionView:(UICollectionView *)collectionView shouldSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    return YES;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
//支持旋转
-(BOOL)shouldAutorotate{
    return YES;
}

//支持的方向 因为界面A我们只需要支持竖屏
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}

//一开始的方向  很重要
-(UIInterfaceOrientation)preferredInterfaceOrientationForPresentation{
    return UIInterfaceOrientationLandscapeLeft;
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
