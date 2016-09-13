//
//  BWProgramViewController.m
//  BWSC_AVS+_Player
//
//  Created by 裴留振 on 16/4/18.
//  Copyright © 2016年 裴留振. All rights reserved.
//

#import "BWProgramViewController.h"
#import "Masonry.h"
#import "CustomerCollectionViewCell.h"
#import "CustomerScaleLayout.h"
#import "BWSearchViewController.h"
#import "KxMovieViewController.h"
#include "bw_encode.h"
#import "ProgramModel.h"
#import "getgateway.h"
#import <arpa/inet.h>
#import <netdb.h>
#import <netinet/in.h>
#import <netinet6/in6.h>
#import <ifaddrs.h>
#import <SystemConfiguration/SCNetworkReachability.h>
#include <sys/socket.h>
#import "JQIndicatorView.h"


@interface BWProgramViewController ()<UICollectionViewDataSource,UICollectionViewDelegate,UICollectionViewDelegateFlowLayout>{
    
    NSString *urlPath;
    NSString *idString;
    NSString *programName;
    NSString *programFrequency;
    NSString *sendID;
    UIView *view;
    NSNumber *sendStatus;
    JQIndicatorView *indicator;

}

@property (nonatomic ,strong)NSMutableArray *dataArray;
@property (nonatomic ,strong)UILabel *topLabel;
@property (nonatomic ,strong)UIView *backView;
@property (nonatomic ,strong)UIButton *searchButton;
@property (nonatomic ,strong)UICollectionView *collectionView;
@property (nonatomic ,strong)UIImageView *failImageView;
@property (nonatomic ,strong)UIButton *enctyptBtn;
@property (nonatomic ,strong)UILabel *encryptLabel;
@property (nonatomic ,assign)BOOL isEnctypt;
@property (nonatomic ,strong)UILabel *midleLabel;
@property (nonatomic ,copy)NSString * baseUrl;
@property (nonatomic ,copy)NSString *ipAddress;
@property (nonatomic ,copy)NSString* routerIP;//路由地址
@property (nonatomic ,copy)NSString *path;
@property (nonatomic ,strong)ProgramModel *model;
@property (nonatomic ,assign)NSInteger port;
@property (nonatomic ,strong)UISwitch* mySwitch;
@end

@implementation BWProgramViewController

static NSString *cellName = @"Cell";

-(void)viewWillAppear:(BOOL)animated{
    
    [super viewWillAppear:animated];
    
    [UIApplication sharedApplication].statusBarHidden=YES;
    
    [self loadData];
    
}

-(void)changeRouterIP1:(NSNotification *)sender{
    
    KAppDelegate.routerIP=sender.userInfo[@"routerIp"];
    KAppDelegate.isConnect=[sender.userInfo[@"isConnect"] boolValue];
    //_routerIP= KAppDelegate.routerIP;
    DLog(@"通知接收路由器地址--------------------------%@",KAppDelegate.routerIP);
    _baseUrl=[NSString stringWithFormat:@"http://%@:8800/",KAppDelegate.routerIP];

}

-(void)viewWillDisappear:(BOOL)animated{
    
    [super viewWillDisappear:animated];
    
    [indicator stopAnimating];
    
    [indicator removeFromSuperview];
    
    [view removeFromSuperview];
    
    self.navigationController.navigationBarHidden=NO;
    
}

#pragma mark--加载节目信息
-(void)loadData{
    
    BWSearchViewController *searchVC=[[BWSearchViewController alloc]init];
    
    [searchVC setPopTimeStringBlock:^(NSString *timeString) {
        
        _timeString=timeString;
    }];

    
    [_dataArray removeAllObjects];
    
    //缓存的文件夹路径
    NSString *path = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    
    NSString *filePath = [path stringByAppendingPathComponent:@"com.bwsctv.listDataCache"];
    
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    
    NSArray *contents = [fileManager contentsOfDirectoryAtPath:filePath error:nil];
    
    for (id obj in contents) {
        
        //获取文件路径
        NSString *filePath1 = [filePath stringByAppendingPathComponent:obj];
        
       // NSLog(@"缓存文件:%@",filePath1);
        
        //取得缓存数据
        NSDictionary *dic = [NSDictionary dictionaryWithContentsOfFile:filePath1];

        NSArray *subArr=[NSArray arrayWithArray:[dic objectForKey:@"submenu"]];
        
        NSString *frequency=[dic objectForKey:@"frequency"];
        
        //DLog(@"frequency=%@",frequency);
        
        __weak typeof(self)weakSelf=self;
        
        [subArr enumerateObjectsUsingBlock:^(NSDictionary *obj1, NSUInteger idx1, BOOL * _Nonnull stop1) {
            
            NSMutableDictionary *dict1=[NSMutableDictionary dictionaryWithDictionary:obj1];
            for (id obj2 in obj1) {
                
                [dict1 setObject:[obj1 objectForKey:obj2] forKey:obj2];
            }
            [dict1 setObject:frequency forKey:@"frequency"];
            
             //if (![[dict1 objectForKey:@"name"] isEqualToString:@""])
            
            if(_timeString==nil){
                
                if (_isEnctypt==NO) {
                    
                    //节目加密
                    if (![[dict1 objectForKey:@"encrypt"] isEqualToNumber:@(1)])
                    {
                        ProgramModel *model=[[ProgramModel alloc]initWithDictionary:dict1];
                        
                        [weakSelf.dataArray addObject:model];
                        
                        DLog(@"name=%@",model.name);
                        NSLog(@"encrypt=%d",[model.encrypt intValue]);
                        
                    }
                    
                }else{
                    
                    ProgramModel *model=[[ProgramModel alloc]initWithDictionary:dict1];
                    
                    [weakSelf.dataArray addObject:model];
                    
                    NSLog(@"name=%@",model.name);
                    NSLog(@"encrypt=%d",[model.encrypt intValue]);
                }
                

                
            }
            else if([[dict1 objectForKey:@"timestamp"] isEqualToString:_timeString] && ![_timeString isEqualToString:@""]) {
                
                if (_isEnctypt==NO) {
                    
                    if (![[dict1 objectForKey:@"encrypt"] isEqualToNumber:@(1)])
                    {
                        ProgramModel *model=[[ProgramModel alloc]initWithDictionary:dict1];
                        
                        [weakSelf.dataArray addObject:model];
                        
                        NSLog(@"name=%@",model.name);
                        NSLog(@"encrypt=%d",[model.encrypt intValue]);
                        
                    }
                    
                }else{
                    
                    ProgramModel *model=[[ProgramModel alloc]initWithDictionary:dict1];
                    
                    [weakSelf.dataArray addObject:model];
                    
                    NSLog(@"name=%@",model.name);
                    NSLog(@"encrypt=%d",[model.encrypt intValue]);
                }

            }
            
        }];
        
    }
    NSLog(@"读取缓存成功");
    
    if (_dataArray.count==0) {
        
        _midleLabel.text=@"暂无电视节目!";
        
         [_collectionView addSubview:_failImageView];
        
        [_failImageView mas_makeConstraints:^(MASConstraintMaker *make) {
            
            make.centerX.mas_equalTo(_collectionView.mas_centerX);
            make.centerY.mas_equalTo(_collectionView.mas_centerY);
            make.width.mas_equalTo(58);
            make.height.mas_equalTo(74);
        }];

    }else{
        
        _midleLabel.text=[NSString stringWithFormat:@"%d个电视节目,可点击观看",(int)_dataArray.count];
        
        [_failImageView removeFromSuperview];
    }

    [_collectionView reloadData];
}

- (void)viewDidLoad {
    [super viewDidLoad];
//    [BWListCache clearCacheListData:^{
//
//
//    }];
     _port=2000;
    
    self.title=@"指尖TV";
    
    self.isEnctypt=NO;
    
    //self.navigationController.navigationBar.barTintColor=RGBA_MD(0, 150, 255, 1);
    
    self.view.backgroundColor=RGBA_MD(244, 244, 244, 1);
    
    //self.navigationController.navigationBar.barTintColor=RGBA_MD(0, 150, 255, 1);
    
    self.navigationController.navigationBar.translucent = NO;
    
    [self setAutomaticallyAdjustsScrollViewInsets:NO];
    //--设置导航栏字体大小
    [self.navigationController.navigationBar setTitleTextAttributes:@{NSFontAttributeName:[UIFont systemFontOfSize:IPhone4_5_6_6P(19, 20, 21, 22)],NSForegroundColorAttributeName:[UIColor whiteColor]}];
    
   //   self.navigationItem.backBarButtonItem=[[UIBarButtonItem alloc]initWithImage:[UIImage imageNamed:@"back"] style:UIBarButtonItemStyleDone target:self action:nil];
    
    _dataArray=[NSMutableArray array];
    
    [self creatUI];
    
    _timeString=nil;
    
    _ipAddress=[self getLocalIP];
    
    //注册通知
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tongzhi:) name:@"changNotification" object:nil];
    
    //注册通知(等待接收消息)
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(changeRouterIP1:) name:@"changeRouterIP" object:nil];
}
- (void)dealloc {
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"changeRouterIP" object:nil];
    
    //移除监听者
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"changNotification" object:nil];
}

-(void)creatUI{
    
    //topLabel
    _topLabel=[[UILabel alloc]init];
    
    _topLabel.textAlignment=NSTextAlignmentLeft;
    
    _topLabel.textColor=[UIColor grayColor];
    
    _topLabel.font=[UIFont fontWithName:@"Arial Rounded MT Bold" size:IPhone4_5_6_6P(18, 19, 20, 21)];
    
    _topLabel.text=@"电视节目表";
    
    [self.view addSubview:_topLabel];
    
    [_topLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        
        make.left.mas_equalTo(20);
        make.top.mas_equalTo(0);
        make.height.mas_equalTo(30);
        make.right.mas_equalTo(-20);
    }];
    
    //节目显示文本
    _midleLabel=[[UILabel alloc]init];
    
    _midleLabel.textAlignment=NSTextAlignmentLeft;
    
    _midleLabel.textColor=[UIColor grayColor];
    
    _midleLabel.font=[UIFont systemFontOfSize:IPhone4_5_6_6P(17, 18, 29, 20)];
    
    _midleLabel.numberOfLines=0;
    
    [self.view addSubview:_midleLabel];
    
    [_midleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(_topLabel.mas_bottom).offset(0);
        make.height.mas_equalTo(30);
        make.right.mas_equalTo(-60);
        make.left.mas_equalTo(60);
    }];

    
    //自定义布局初始化
    CustomerScaleLayout *layout = [[CustomerScaleLayout alloc] init];
    
    [layout setScrollDirection:UICollectionViewScrollDirectionHorizontal]; //设置横向还是竖向
    self.collectionView = [[UICollectionView alloc]initWithFrame:CGRectMake(64, 64, self.view.frame.size.width-100, self.view.frame.size.height-100) collectionViewLayout:layout];
    
    [self.collectionView setTranslatesAutoresizingMaskIntoConstraints:NO];
    
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.collectionView.backgroundColor = RGBA_MD(220, 220, 220, 1);
    
    [self.view addSubview:self.collectionView];
    
    [_collectionView mas_makeConstraints:^(MASConstraintMaker *make) {
        
        make.top.equalTo(_midleLabel.mas_bottom).offset(5);
        make.height.mas_equalTo(MDXFrom6(120));
        make.left.mas_equalTo(50);
        make.right.mas_equalTo(-50);
    }];
    //设置圆角
    _collectionView.layer.cornerRadius=15;
    
    _collectionView.layer.masksToBounds=YES;
    //注册
    [self.collectionView registerClass:[CustomerCollectionViewCell class] forCellWithReuseIdentifier:cellName];
    
    _failImageView=[[UIImageView alloc]initWithFrame:CGRectMake(0 ,0 ,0 ,0)];
    
    _failImageView.backgroundColor=[UIColor clearColor];
    
    _failImageView.image=[UIImage imageNamed:@"wu"];

    if (_dataArray.count==0) {
        
        _midleLabel.text=@"暂无电视节目";
        
        [_collectionView addSubview:_failImageView];
        
        [_failImageView mas_makeConstraints:^(MASConstraintMaker *make) {
            
            make.centerX.mas_equalTo(_collectionView.mas_centerX);
            make.centerY.mas_equalTo(_collectionView.mas_centerY);
            make.width.mas_equalTo(58);
            make.height.mas_equalTo(74);
        }];
        
        
    }else{
        
        _midleLabel.text=[NSString stringWithFormat:@"%d个电视节目,请点击观看",(int)_dataArray.count];
        
        [_failImageView removeFromSuperview];
        
    }

    
    //底部view
    UIView *bottemView=[[UIView alloc]init];
    //bottemView.layer.borderWidth = 1;
    //bottemView.layer.borderColor = [RGBA_MD(220, 220, 220, 0.8) CGColor];
    [self.view addSubview:bottemView];
    
    [bottemView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.mas_equalTo(0);
        make.bottom.mas_equalTo(-30);
        make.height.mas_equalTo(40);
        make.right.mas_equalTo(0);
    }];
    //连接按钮
//    _connectButton=[UIButton buttonWithType:UIButtonTypeCustom];
//    
//    [_connectButton setTitleColor:RGBA_MD(0, 107, 255, 1) forState:UIControlStateNormal];
//    
//    [_connectButton setTitle:@"重新连接" forState:UIControlStateNormal];
//    
//    _connectButton.backgroundColor=[UIColor clearColor];
//    
//    _connectButton.titleLabel.textAlignment=NSTextAlignmentCenter;
//    
//    [_connectButton addTarget:self action:@selector(reConnectBtn:) forControlEvents:UIControlEventTouchUpInside];
//    
//    [bottemView addSubview:_connectButton];
//    
//    [_connectButton mas_makeConstraints:^(MASConstraintMaker *make) {
//        
//        make.width.mas_equalTo(100);
//        make.top.mas_equalTo(bottemView.mas_top);
//        make.height.mas_equalTo(bottemView.mas_height);
//        make.right.equalTo(bottemView.mas_centerX).offset(MDYFrom6(-50));
//    }];
//    
    //节目搜索
    _searchButton=[UIButton buttonWithType:UIButtonTypeCustom];
    
    [_searchButton setTitle:@"搜索节目" forState:UIControlStateNormal];
    
    _searchButton.backgroundColor=RGBA_MD(0, 150, 250, 1);
    
    _searchButton.titleLabel.textAlignment=NSTextAlignmentCenter;
    
    [_searchButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _searchButton.layer.masksToBounds=YES;
    
    _searchButton.layer.cornerRadius=5.0f;
    
    [_searchButton addTarget:self action:@selector(reSearchBtn:) forControlEvents:UIControlEventTouchUpInside];
    
    [bottemView addSubview:_searchButton];
    
    [_searchButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.width.mas_equalTo(_collectionView.mas_width);
        make.top.mas_equalTo(bottemView.mas_top);
        make.height.mas_equalTo(bottemView.mas_height);
        make.centerX.mas_equalTo(bottemView.mas_centerX);
    }];
    
    //顶部按钮，文本
    //topLabel
    _mySwitch= [[UISwitch alloc] initWithFrame:CGRectMake(10, 20, 0, 0)];
    
    _mySwitch.on =NO;
    //[sw setOn: animated:]
    //更改颜色
    _mySwitch.onTintColor = [UIColor greenColor];
    _mySwitch.tintColor = RGBA_MD(220, 220, 220, 1);
    _mySwitch.thumbTintColor = [UIColor whiteColor];
    //添加事件
    [_mySwitch addTarget:self action:@selector(switchConnect:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_mySwitch];
    //布局
    [_mySwitch mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(_collectionView.mas_left).offset(50);
        make.top.equalTo(_collectionView.mas_bottom).offset(10);
        make.height.mas_equalTo(20);
        make.width.mas_equalTo(40);
    }];
   //显示加密
    _encryptLabel=[[UILabel alloc]init];
    
    _encryptLabel.textAlignment=NSTextAlignmentLeft;
    
    _encryptLabel.textColor=[UIColor grayColor];
    
    _encryptLabel.font=[UIFont systemFontOfSize:MDXFrom6(21.0f)];
    
    _encryptLabel.text=@"显示加密节目(加密节目暂无法播放)";
    _encryptLabel.numberOfLines=1;
    
    [self.view addSubview:_encryptLabel];
    
    [_encryptLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        
        make.right.mas_equalTo(-40);
        make.top.equalTo(_collectionView.mas_bottom).offset(5);
        make.height.mas_equalTo(40);
        make.left.equalTo(_mySwitch.mas_right).offset(20);
    }];

    //显示加密按钮
//    _enctyptBtn=[UIButton buttonWithType:UIButtonTypeCustom];
//    
//    //_enctyptBtn.backgroundColor=[UIColor redColor];
//    
//    _enctyptBtn.titleLabel.textAlignment=NSTextAlignmentCenter;
    
//    [_enctyptBtn setTitleColor:RGBA_MD(0, 107, 255, 1) forState:UIControlStateNormal];
//    
//    _enctyptBtn.layer.masksToBounds=YES;
//    _enctyptBtn.layer.borderWidth=2.0f;
//    _enctyptBtn.layer.borderColor=[[UIColor blackColor]CGColor];
//    
//    [_enctyptBtn addTarget:self action:@selector(enctyptBtn:) forControlEvents:UIControlEventTouchUpInside];
//    
//    [self.view addSubview:_enctyptBtn];
//    
//    [_enctyptBtn mas_makeConstraints:^(MASConstraintMaker *make) {
//        make.width.mas_equalTo(32);
//        make.top.equalTo(_encryptLabel.mas_top).offset(3);
//        make.height.mas_equalTo(32);
//        make.right.equalTo(_encryptLabel.mas_left).offset(0);
//    }];
    
}

#pragma mark--是否显示加密节目
/**
 *switch开关点击事件
 */
- (void)switchConnect:(UISwitch*)sw{
    if (sw.on) {
        
        NSLog(@"on");
        
        _isEnctypt=YES;
        
        [self loadData];
        
    } else {
        
        NSLog(@"off");
        
        _isEnctypt=NO;
        
        [self loadData];
    }
}
/**
 *搜索按钮点击事件
 */
-(void)reSearchBtn:(UIButton *)sender{
    
    NSLog(@"前往搜索");
    BWSearchViewController *searchVC=[[BWSearchViewController alloc]init];
    
    searchVC.getStatus=sendStatus;
    
    [self.navigationController pushViewController:searchVC animated:YES];
}




#pragma mark --黄金三问
-(NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return _dataArray.count;
}

-(UICollectionViewCell*)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    ProgramModel *model = nil;
    
    if (self.dataArray.count > indexPath.item) {
        
        model = self.dataArray[indexPath.item];
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
    if (KAppDelegate.isConnect==YES) {
        
        _model = nil;
        
        if (self.dataArray.count > indexPath.row) {
            
            _model = self.dataArray[indexPath.row];
        }
        
        
        indicator = [[JQIndicatorView alloc] initWithType:1 tintColor:[UIColor orangeColor] size:CGSizeMake(MDXFrom6(100), MDXFrom6(200))];
        
        indicator.center = _collectionView.center;
        
        [self.view addSubview:indicator];
        
        [indicator mas_makeConstraints:^(MASConstraintMaker *make) {
            
            make.centerX.equalTo(_collectionView.mas_centerX).offset(100);
            make.centerY.equalTo(_collectionView.mas_centerY).offset(50);
            make.width.mas_equalTo(200);
            make.height.mas_equalTo(100);
        }];
        
        _collectionView.userInteractionEnabled=NO;
        
        _baseUrl=[NSString stringWithFormat:@"http://%@:8800/",KAppDelegate.routerIP];
        
        //节目播放post请求方法
        NSString *urlStr=[NSString stringWithFormat:@"%@play",_baseUrl];
        
        NSNumber *portNum=@(_port);
        
        NSNumber *freNum=@([_model.frequency integerValue]);
        
        NSDictionary *dict=@{@"frequency":freNum,@"sid":_model.sid,@"port":portNum};
        
        
        //    if ([_model.encrypt isEqualToNumber:@(1)]) {
        //
        //
        //    }else{
        
        [indicator startAnimating];
        
        [BWHttpRequest postWithUrl:urlStr params:dict netIdentifier:@"play" success:^(id response) {
            
            collectionView.userInteractionEnabled=YES;
            
            NSLog(@"---请求成功");
            
            [indicator stopAnimating];
            
            [indicator removeFromSuperview];
            
            _collectionView.userInteractionEnabled=YES;
            
            NSNumber *statusNum = @([response[@"status"] integerValue]);
            
            sendStatus = statusNum;
            
            NSLog(@"%@",statusNum);
            
            if ([statusNum isEqualToNumber:@(0)]) {
                
                idString=response[@"id"];
                
                NSLog(@"idString:%@",idString);
                
                urlPath=[NSString stringWithFormat:@"udp://%@:%u",_ipAddress,_port];//fixit 1234 to 2000
                
                NSLog(@"%@[Line %d]:%@",self,__LINE__,urlPath);
                NSLog(@"%@",urlPath.pathExtension);
                
                programName=_model.name;
                programFrequency=_model.frequency;
                
                //
                //                NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
                //
                //                // increase buffering for .wmv, it solves problem with delaying audio frames
                //                if ([_path.pathExtension isEqualToString:@"wmv"])
                //                    parameters[KxMovieParameterMinBufferedDuration] = @(5.0);
                //
                //                // disable deinterlacing for iPhone, because it's complex operation can cause stuttering
                //                if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone)
                //                    parameters[KxMovieParameterDisableDeinterlacing] = @(NO);
                //
                //                KxMovieViewController *vc = [KxMovieViewController movieViewControllerWithContentPath:_path parameters:parameters];
                //
                //                //传递id
                //                vc.getId=idString;
                //                //传递ip地址
                //                vc.getIpAddress=_ipAddress;
                //                //传递节目数组
                //                vc.getArr=self.dataArray;
                //
                //                vc.port=_port;
                //
                //                vc.getName=_model.name;
                //                vc.getFrequency=_model.frequency;
                //
                //                vc.modalTransitionStyle=UIModalTransitionStyleCrossDissolve;
                //
                //                [self presentViewController:vc animated:YES completion:nil];
                //                //[self.navigationController pushViewController:vc animated:YES];
                
                [self changProgram];
                
            }else if([statusNum isEqualToNumber:@(2)]){
                
                
                
                [LCProgressHUD showMessage:@"节目信息已过期"];
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
            
            collectionView.userInteractionEnabled=YES;
            
            NSLog(@"请求失败:%@", error.description);
            
            [indicator stopAnimating];
            
            [indicator removeFromSuperview];
            
            NSString *errorStr=[RequestSever getMsgWithError:error];
            
            UIAlertController * alertController = [UIAlertController alertControllerWithTitle:@"播放失败" message:errorStr preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDestructive handler:nil];
            
            [alertController addAction:cancelAction];
            
            [self presentViewController:alertController animated:YES completion:nil];
            
        } showHUD:NO];

       //}
    }else{
        
        [LCProgressHUD showMessage:@"连接网关错误,请检查wifi连接"];
        
        [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hidHUD) userInfo:nil repeats:NO];
    }
}
- (void)hidHUD {
    
    [LCProgressHUD hide];
}

#pragma mark--更换节目通知
-(void)tongzhi:(NSNotification *)text{
    
    view=[[UIView alloc]initWithFrame:CGRectMake(0, -44, KScreenWidth, KScreenHeight+44)];
    
    view.backgroundColor=[UIColor blackColor];
    
    [self.view addSubview:view];
    
    [view mas_makeConstraints:^(MASConstraintMaker *make) {
        
        make.right.mas_equalTo(0);
        make.left.mas_equalTo(0);
        make.bottom.mas_equalTo(0);
        make.top.mas_equalTo(0);
        
    }];
    
    self.navigationController.navigationBarHidden=YES;
    
    NSLog(@"＝＝＝＝＝＝通知:%@",text.userInfo[@"path"]);
    
    urlPath=text.userInfo[@"path"];
    idString=text.userInfo[@"idString"];
    programName=text.userInfo[@"name"];
    programFrequency=text.userInfo[@"frequency"];
    
    [self performSelector:@selector(changProgram) withObject:nil afterDelay:1];
}

-(void)changProgram{
    
    
    
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    
    // increase buffering for .wmv, it solves problem with delaying audio frames
    if ([urlPath.pathExtension isEqualToString:@"wmv"])
        parameters[KxMovieParameterMinBufferedDuration] = @(5.0);
    
    // disable deinterlacing for iPhone, because it's complex operation can cause stuttering
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone)
        parameters[KxMovieParameterDisableDeinterlacing] = @(NO);
    KxMovieViewController *vc = [KxMovieViewController movieViewControllerWithContentPath:urlPath parameters:parameters];
    
    [vc setPopPortBlock:^(NSInteger port) {
        
        _port=port;
    }];
    
    if (_port<2020) {
        
        ++_port;
    }else{
        
        _port=2000;
    }
    //传递端口号
    vc.port=_port;
    //传递ip地址
    vc.getIpAddress=_ipAddress;
    //传递节目数组
    vc.getArr=self.dataArray;
    
    vc.getId=idString;
    
    vc.getName=programName;
    
    vc.getFrequency=programFrequency;
    
    vc.modalTransitionStyle=UIModalTransitionStyleCrossDissolve;
    
    [self presentViewController:vc animated:NO completion:nil];
}

- (void)didReceiveMemoryWarning {
    
    [super didReceiveMemoryWarning];
    
}

//支持旋转
-(BOOL)shouldAutorotate{
    return YES;
}

//支持的方向
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
