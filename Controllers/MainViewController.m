//
//  MainViewController.m
//  kxmovie
//
//  Created by Kolyvan on 18.10.12.
//  Copyright (c) 2012 Konstantin Boukreev . All rights reserved.
//
//  https://github.com/kolyvan/kxmovie
//  this file is part of KxMovie
//  KxMovie is licenced under the LGPL v3, see lgpl-3.0.txt

#import "MainViewController.h"
#import "KxMovieViewController.h"
#import "BWSearchViewController.h"
#import "BWProgramViewController.h"
#import <SystemConfiguration/CaptiveNetwork.h>
#import <SystemConfiguration/SCNetworkReachability.h>
#include <sys/socket.h>
#import <netinet/in.h>
#import <netinet6/in6.h>
#import <ifaddrs.h> 
#include <arpa/inet.h>
#include <netdb.h>
#include <net/if.h>
#import <dlfcn.h>
#import <arpa/inet.h>
#import "getgateway.h"
#import <arpa/inet.h>
#import "BWHttpRequest.h"
#import "AFNetworking.h"
#import "AFNetworkActivityIndicatorManager.h"
#import "Reachability.h"
#import "Masonry.h"//适配屏幕
#import "ProgramModel.h"

#define BASE_URL @"http://baobab.wdjcdn.com/1456316686552The.mp4"

@interface MainViewController (){
    
    NSNumber * statusNum;
    UIAlertController * _alertController;
    UIAlertController * _alertController1;
}

@property (nonatomic ,strong)UILabel *topLabel;
@property (nonatomic ,strong)UIImageView *remindImageView;
@property (nonatomic ,strong)UILabel *bottemLabel;
@property (nonatomic ,strong)UIButton *connectButton;
@property (nonatomic ,strong)UIButton *nextButton;
@property (nonatomic ,copy)NSString *wifiName;
@property (nonatomic ,copy)NSString *ipAddress;
@property (nonatomic ,copy)NSString* routerIP;
@property (nonatomic ,strong)NSMutableArray *dataArr;
@property (nonatomic ,assign)NSInteger menuCount;

@end

@implementation MainViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [UIApplication sharedApplication].statusBarHidden=YES;
    
    _routerIP= KAppDelegate.routerIP;
    
    //注册通知(等待接收消息)
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(changeRouterIP:) name:@"changeRouterIP" object:nil];
    
    NSLog(@"%@",self.str);
    
    _isConnect=NO;
    
    [self getLocalIP];
    
    [self isConnectOrNot];
    
    NSLog(@"isContect=%d",_isConnect);
    
    self.title=@"指尖TV";
    
    [self setAutomaticallyAdjustsScrollViewInsets:NO];
    
    self.navigationController.navigationBar.barTintColor=RGBA_MD(0, 150, 255, 1);
    
    self.view.backgroundColor=RGBA_MD(244, 244, 244, 1);
    
    //--设置导航栏字体大小
    [self.navigationController.navigationBar setTitleTextAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:IPhone4_5_6_6P(19, 20, 21, 22)],NSForegroundColorAttributeName:[UIColor whiteColor]}];
    
    self.navigationController.navigationBar.translucent = NO;
    
    self.navigationItem.backBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:@"" style:UIBarButtonItemStyleDone target:self action:nil];
    
    [self.navigationController.navigationBar setTintColor:[UIColor whiteColor]];
    
    [self creatUI];
    
    //初始化数组
    self.dataArr=[NSMutableArray array];
    
    //监测网络情况
//    [[NSNotificationCenter defaultCenter] addObserver:self
//                                             selector:@selector(networkStateChange)
//                                                 name: kReachabilityChangedNotification
//                                        object: nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
        
    //[self startMonitoring];
    NSLog(@"isContect:%d",_isConnect);

    //加载缓存
    [self loadData];
}
-(void)changeRouterIP:(NSNotification *)sender{

    KAppDelegate.routerIP=sender.userInfo[@"routerIp"];
    KAppDelegate.isConnect=[sender.userInfo[@"isConnect"] boolValue];
    _routerIP= KAppDelegate.routerIP;
    _isConnect=KAppDelegate.isConnect;
    DLog(@"通知接收路由器地址--------------------------%@",_routerIP);
    [self upDataUI];

}
-(void)viewWillDisappear:(BOOL)animated{
    
    [super viewWillDisappear:animated];
    
    [BWHttpRequest cancelNetworkingWithNetIdentifier:@"menu"];
    
}

- (void)dealloc
{
     //[self.conn stopNotifier];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"changeRouterIP" object:nil];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

-(void)loadData{
    
    NSString * baseUrl=[NSString stringWithFormat:@"http://%@:8800/",KAppDelegate.routerIP];
    
    __weak typeof(self)weakSelf=self;
    
    NSString *timeString=[self getCurrentTime];
    
    NSLog(@"%@",timeString);
    
    NSString *urlStr=[NSString stringWithFormat:@"%@menu?frequency=474000-826000&timestamp=%@",baseUrl,timeString];
    
    [BWHttpRequest getWithUrl:urlStr params:nil netIdentifier:@"menu" success:^(id response) {
        
        NSLog(@"解析成功");
        
        statusNum = @([response[@"status"] integerValue]);
        
        if ([statusNum isEqualToNumber:@(0)]) {
            
            [self.dataArr removeAllObjects];
            
            [BWListCache clearCacheListData:^{
                
                
            }];
            
            NSArray *tmpArr=response[@"menu"];
            
            NSLog(@"%d",tmpArr.count);
            
            _menuCount=tmpArr.count;
            
            
            [tmpArr enumerateObjectsUsingBlock:^(NSDictionary * obj, NSUInteger idx, BOOL *stop) {
                
                NSDictionary *dict=[NSDictionary dictionaryWithDictionary:obj];
                
                NSString * key=[dict objectForKey:@"frequency"];
                
                [BWListCache setObjectOfDic:dict key:[NSString stringWithFormat:@"%@",key]];
                
                NSArray *subArr=[NSArray arrayWithArray:[dict objectForKey:@"submenu"]];
                
                [subArr enumerateObjectsUsingBlock:^(NSDictionary *obj1, NSUInteger idx1, BOOL * _Nonnull stop1) {
                    
                    NSMutableDictionary *dictionary=[NSMutableDictionary dictionaryWithDictionary:obj1];
                    
                    [dictionary setObject:key forKey:@"frequency"];
                    
                    ProgramModel *model=[[ProgramModel alloc]initWithDictionary:dictionary];
                    
                    [weakSelf.dataArr addObject:model];
                    
                    NSLog(@"name=%@",model.name);
                    NSLog(@"sid=%@",model.sid);
                    NSLog(@"fre=%@",model.frequency);
                }];
                
            }];
            
        }else{
            
            [LCProgressHUD showMessage:@"数据不合法"];
            
            [NSTimer scheduledTimerWithTimeInterval:2
                                             target:self
                                           selector:@selector(hideHUD)
                                           userInfo:nil
                                            repeats:NO];
        }

    } fail:^(NSError *error) {
        
        NSLog(@"%@",error);
        
        /*
        NSLog(@"解析失败");
        
        // 缓存的 文件夹路径
        NSString *path = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
        
        NSString *filePath = [path stringByAppendingPathComponent:@"com.bwsctv.listDataCache"];
        
        NSFileManager *fileManager = [[NSFileManager alloc] init];
        
        NSArray *contents = [fileManager contentsOfDirectoryAtPath:filePath error:nil];
        
         _menuCount=contents.count;
        
        for (id obj in contents) {
            
            //获取文件路径
            NSString *filePath1 = [filePath stringByAppendingPathComponent:obj];
            
            NSLog(@"缓存文件:%@",filePath1);
            
            //删除沙盒文件
            //[fm removeItemAtPath:filePath error:nil];
        }
        */

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

//创建UI
-(void)creatUI{
    
    //topLabel
    _topLabel=[[UILabel alloc]init];
    
    _topLabel.textAlignment=NSTextAlignmentLeft;
    
    _topLabel.textColor=[UIColor grayColor];
    
    _topLabel.font=[UIFont systemFontOfSize:IPhone4_5_6_6P(18, 19, 20, 21)];

    _topLabel.text=@"连接DTMB网关的WLAN";
    
    [self.view addSubview:_topLabel];
    
    [_topLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        
        make.left.mas_equalTo(20);
        make.top.mas_equalTo(0);
        make.height.mas_equalTo(40);
        make.right.mas_equalTo(-20);
    }];
    
    //底部view
    UIView *bottemView=[[UIView alloc]init];
   // bottemView.layer.borderWidth = 1;
   //bottemView.layer.borderColor = [RGBA_MD(220, 220, 220, 0.8) CGColor];
    [self.view addSubview:bottemView];
    
    [bottemView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.mas_equalTo(0);
        make.bottom.mas_equalTo(-40);
        make.height.mas_equalTo(40);
        make.right.mas_equalTo(0);
    }];
    //提示背景
    _remindImageView=[[UIImageView alloc]init];
    
    [self.view addSubview: _remindImageView];
    
    [_remindImageView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerX.mas_equalTo(self.view.mas_centerX);
        make.top.equalTo(_topLabel.mas_bottom).offset(0);
        make.bottom.equalTo(bottemView.mas_top).offset(0);
        make.width.equalTo(_remindImageView.mas_height).multipliedBy(10/4.5);
    }];
    [_remindImageView setImage:[UIImage imageNamed:@"Interface_1.png"]];
    
    _remindImageView.contentMode = UIViewContentModeScaleToFill;
    [_remindImageView setClipsToBounds:YES];
    
    //底部文本
    _bottemLabel=[[UILabel alloc]init];
    
    _bottemLabel.textAlignment=NSTextAlignmentCenter;
    
    _bottemLabel.textColor=[UIColor grayColor];
    
   // _bottemLabel.font=[UIFont systemFontOfSize:MDXFrom6(13.0f)];
    
    _bottemLabel.text=_isConnect==YES?[NSString stringWithFormat:@"已连接“%@”",_wifiName]:@"目前尚未连接!";
    
   // _bottemLabel.backgroundColor=RGBA_MD(244, 244, 244, 1);
    
    [bottemView addSubview:_bottemLabel];
    
    [_bottemLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        
        make.left.equalTo(self.view.mas_left).offset(50);
        make.top.mas_equalTo(bottemView.mas_top);
        make.height.mas_equalTo(bottemView.mas_height);
        make.right.mas_equalTo(bottemView.mas_centerX);
    }];
    //连接按钮
    _connectButton=[UIButton buttonWithType:UIButtonTypeCustom];
    
    [_connectButton setTitleColor:RGBA_MD(0, 150, 255, 1) forState:UIControlStateNormal];
    
    _connectButton.backgroundColor=RGBA_MD(244, 244, 244, 1);
    
    
    [_connectButton setTitle:_isConnect==YES?@"重新连接":@"立即连接" forState:UIControlStateNormal];
    
    _connectButton.titleLabel.textAlignment=NSTextAlignmentCenter;
    
    [_connectButton addTarget:self action:@selector(clickBtn:) forControlEvents:UIControlEventTouchUpInside];
    
    [bottemView addSubview:_connectButton];
    
    [_connectButton mas_makeConstraints:^(MASConstraintMaker *make) {
        
        make.width.mas_equalTo(100);
        make.top.mas_equalTo(bottemView.mas_top);
        make.height.mas_equalTo(bottemView.mas_height);
        make.left.equalTo(bottemView.mas_centerX).offset(10);
    }];
    
    //下一步按钮
    _nextButton=[UIButton buttonWithType:UIButtonTypeCustom];
    
    [_nextButton setTitle:@"下一步" forState:UIControlStateNormal];
    
    _nextButton.backgroundColor=RGBA_MD(244, 244, 244, 1);
    
    _nextButton.titleLabel.textAlignment=NSTextAlignmentCenter;
    
    
    [_nextButton addTarget:self action:@selector(nextBtn:) forControlEvents:UIControlEventTouchUpInside];
    
    if (_isConnect==YES) {
        
        [_nextButton setTitleColor:RGBA_MD(0, 150, 255, 1) forState:UIControlStateNormal];
        
        [_nextButton setImage:[UIImage imageNamed:@"openh"] forState:UIControlStateNormal];
        
    }
    else{
        
        [_nextButton setTitleColor:[UIColor darkGrayColor] forState:UIControlStateNormal];
        
        [_nextButton setImage:[UIImage imageNamed:@"gray"] forState:UIControlStateNormal];
    }

    [bottemView addSubview:_nextButton];
    
    [_nextButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.width.mas_equalTo(100);
        make.top.mas_equalTo(bottemView.mas_top);
        make.height.mas_equalTo(bottemView.mas_height);
        make.left.equalTo(_connectButton.mas_right).offset(30);
    }];

}
-(BOOL)upDataUI{
    
    _bottemLabel.text=_isConnect==YES?[NSString stringWithFormat:@"已连接“%@”",_wifiName]:@"目前尚未连接!";
    
    [_connectButton setTitle:_isConnect==YES?@"重新连接":@"立即连接" forState:UIControlStateNormal];
    
    if (_isConnect==YES) {
        
        [_nextButton setTitleColor:RGBA_MD(0, 150, 255, 1) forState:UIControlStateNormal];
        
        [_nextButton setImage:[UIImage imageNamed:@"openh"] forState:UIControlStateNormal];
        
        if (_alertController) {
            
            [_alertController dismissViewControllerAnimated:YES completion:nil];
        }
        
        _alertController1 = [UIAlertController alertControllerWithTitle:nil message:@"网络已正常连接" preferredStyle:UIAlertControllerStyleAlert];
        
        [_alertController1 addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            
        }]];
        
        [self presentViewController:_alertController1 animated:YES completion:nil];
        
    }
    else{
        
        [_nextButton setTitleColor:[UIColor darkGrayColor] forState:UIControlStateNormal];
        
        [_nextButton setImage:[UIImage imageNamed:@"gray"] forState:UIControlStateNormal];
        
        if (_alertController1) {
            
            [_alertController1 dismissViewControllerAnimated:YES completion:nil];
        }

         _alertController = [UIAlertController alertControllerWithTitle:@"网络连接异常" message:@"请检查您的网络设置" preferredStyle:UIAlertControllerStyleAlert];
        
        [_alertController addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            
        }]];
        
        [self presentViewController:_alertController animated:YES completion:nil];
        
    }
    NSLog(@"%@已更新UI",self);
    
    return _isConnect;
    
}

-(void)clickBtn:(UIButton *)sender{
    
    
    NSURL *url = [NSURL URLWithString:@"prefs:root=WIFI"];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url];
    }
    NSLog(@"连接按钮");
}
-(void)nextBtn:(UIButton *)sender{
    
    NSLog(@"下一步按钮");
    
    if (_isConnect==YES) {
        
        BWProgramViewController *programVC=[[BWProgramViewController alloc]init];
        programVC.menuCount=_menuCount;
//        programVC.getIpAddress=_ipAddress;
        
        [self.navigationController pushViewController:programVC animated:YES];

    }else{
        
        
    }
    
}

#pragma mark - Configuring the view’s layout behavior

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

/*
 *获取wifi名称判断wifi连接是否正确
 */
-(void)isConnectOrNot{
    
    _wifiName=[self getCurrentWifiName];
    
    if([_wifiName hasPrefix:BWStr] || [_wifiName hasPrefix:NSStr]){
        
        _isConnect=YES;        
    }
    else{
        
        _isConnect=NO;
        
        
    }
    
    NSLog(@"网络状态:%d",_isConnect);
    
    NSLog(@"当前wifiName:%@",_wifiName);
}


//检测网络状况
-(void)startMonitoring
{
    // 1.获得网络监控的管理者
    AFNetworkReachabilityManager *mgr = [AFNetworkReachabilityManager sharedManager];
    // 2.设置网络状态改变后的处理
    [mgr setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
        // 当网络状态改变了, 就会调用这个block
        switch (status)
        {
            case AFNetworkReachabilityStatusUnknown: // 未知网络
                NSLog(@"未知网络");
                [BWHttpRequest sharedBWHttpRequest].networkStats=StatusUnknown;
                 _isConnect=NO;
                
                
                break;
            case AFNetworkReachabilityStatusNotReachable: // 没有网络(断网)
                NSLog(@"%@----------没有网络",self);
                 _isConnect=NO;
                [BWHttpRequest sharedBWHttpRequest].networkStats=StatusNotReachable;
                break;
            case AFNetworkReachabilityStatusReachableViaWWAN: // 手机自带网络
                NSLog(@"--------手机自带网络");
                 _isConnect=NO;
                
                [BWHttpRequest sharedBWHttpRequest].networkStats=StatusReachableViaWWAN;

                break;
            case AFNetworkReachabilityStatusReachableViaWiFi: // WIFI
                
                
                [BWHttpRequest sharedBWHttpRequest].networkStats=StatusReachableViaWiFi;
                NSLog(@"%@WIFI-----------%d",self,[BWHttpRequest sharedBWHttpRequest].networkStats);
                
                [self isConnectOrNot];
                //手机ip地址
                _ipAddress=[self getLocalIP];
                
                break;
        }
        [self upDataUI];
    }];
    [mgr startMonitoring];
    
    
}
-(void)showWifiError{
    
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"网络连接异常" message:@"请检查您的网络设置" delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
    [alert show];
    alert=nil;

    
}
-(void)showWifiRight{
    
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"网络连接信息" message:@"网络连接正常" delegate:nil cancelButtonTitle:@"确定" otherButtonTitles:nil];
    [alert show];
    alert=nil;

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
@end
