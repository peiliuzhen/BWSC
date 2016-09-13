//
//  BWProgramViewController.h
//  BWSC_AVS+_Player
//
//  Created by 裴留振 on 16/4/18.
//  Copyright © 2016年 裴留振. All rights reserved.
//

#import "BaseViewController.h"

@interface BWProgramViewController : BaseViewController
@property (nonatomic ,assign)NSInteger menuCount;

@property (nonatomic ,strong)NSArray *getKeyArr;

@property (nonatomic ,strong)NSString *timeString;

@end
