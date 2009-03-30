//
//  ATVProgressControl.h
//  AwkwardTV
//
//  Created by Alan Quatermain on 13/04/07.
//  Copyright 2007 AwkwardTV. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <BackRow/BRControl.h>

@class BRRenderLayer, BRProgressBarWidget, BRRenderScene;

@interface ATVProgressControl : BRControl
{
    BRRenderLayer *         _layer;
    BRProgressBarWidget *   _widget;
    float                   _maxValue;
    float                   _minValue;
}

- (id) initWithScene: (BRRenderScene *) scene;
- (void) dealloc;

- (void) setFrame: (NSRect) frame;
- (BRRenderLayer *) layer;

- (void) setMaxValue: (float) maxValue;
- (float) maxValue;

- (void) setMinValue: (float) minValue;
- (float) minValue;

- (void) setCurrentValue: (float) currentValue;
- (float) currentValue;

- (void) setPercentage: (float) percentage;
- (float) percentage;

@end
