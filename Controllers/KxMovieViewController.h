//
//  ViewController.h
//  kxmovieapp
//
//  Created by Kolyvan on 11.10.12.
//  Copyright (c) 2012 Konstantin Boukreev . All rights reserved.
//
//  https://github.com/kolyvan/kxmovie
//  this file is part of KxMovie
//  KxMovie is licenced under the LGPL v3, see lgpl-3.0.txt

#import <UIKit/UIKit.h>
#import "ProgramModel.h"

@class KxMovieDecoder;

extern NSString * const KxMovieParameterMinBufferedDuration;    // Float
extern NSString * const KxMovieParameterMaxBufferedDuration;    // Float
extern NSString * const KxMovieParameterDisableDeinterlacing;   // BOOL

typedef void (^DoneCallbackBlock)();

@interface KxMovieViewController : BaseViewController<UITableViewDataSource, UITableViewDelegate>

+ (id) movieViewControllerWithContentPath: (NSString *) path
                               parameters: (NSDictionary *) parameters;

@property (readonly) BOOL playing;

//接收上层数组
@property (nonatomic ,strong)NSMutableArray *getArr;
@property (nonatomic ,copy)NSString *getPath;
@property (nonatomic ,copy)NSString *getId;
@property (nonatomic ,copy)NSString *getIpAddress;
@property (nonatomic ,assign)NSInteger port;
@property (nonatomic ,copy)NSString *getName;
@property (nonatomic , copy)NSString *getFrequency;


- (void) play;
- (void) pause;
@property (nonatomic , copy) void(^popPortBlock)(NSInteger port);
@property (readwrite, copy) DoneCallbackBlock doneCallback;


@end
