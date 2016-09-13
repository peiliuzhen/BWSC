//
//  BWSearchViewController.h
//  BWSC_AVS+_Player
//
//  Created by 裴留振 on 16/4/14.
//  Copyright © 2016年 裴留振. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "CustomerCollectionViewCell.h"
#import "CustomerScaleLayout.h"
@interface BWSearchViewController : BaseViewController

@property (nonatomic , copy) void(^popKeyArrBlock)(NSMutableArray *keyArr);

@property (nonatomic , copy) void(^popTimeStringBlock)(NSString *timeString);

@property (nonatomic , strong)NSNumber *getStatus;
@end
