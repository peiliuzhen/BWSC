//
//  ViewController.m
//  Demo_kvo
//
//  Created by 裴留振 on 16/4/26.
//  Copyright © 2016年 裴留振. All rights reserved.
//

#import "ViewController.h"
#import "dataModel.h"

@interface ViewController ()
{
    dataModel *stockForKVO;
    
    UILabel *myLabel;
    
    float f;
    
}

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    stockForKVO = [[dataModel alloc] init];
    
    f=10;
    [stockForKVO setValue:@"searph" forKey:@"stockName"];
    [stockForKVO setValue:[NSString stringWithFormat:@"%f",f] forKey:@"price"];
    [stockForKVO addObserver:self forKeyPath:@"price" options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld context:NULL];
    
    myLabel = [[UILabel alloc]initWithFrame:CGRectMake(100, 100, 100, 30 )];
    myLabel.textColor = [UIColor redColor];
    myLabel.text = [NSString stringWithFormat:@"%@",[stockForKVO valueForKey:@"price"]];
    [self.view addSubview:myLabel];
    UIButton * b = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    b.frame = CGRectMake(100, 300, 100, 30);
    b.backgroundColor=[UIColor blueColor];
    [b addTarget:self action:@selector(buttonAction) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:b];
}

-(void) buttonAction
{
    f+=10;
    
    [stockForKVO setValue:[NSString stringWithFormat:@"%f",f] forKey:@"price"];
}

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if([keyPath isEqualToString:@"price"])
    {
        myLabel.text = [NSString stringWithFormat:@"%@",[stockForKVO valueForKey:@"price"]];
    }
}

- (void)dealloc
{
    
    [stockForKVO removeObserver:self forKeyPath:@"price"];

}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
