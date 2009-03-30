//
//  ATVRebootWarningController.h
//  AwkwardTV
//
//  Created by Alan Quatermain on 16/04/07.
//  Copyright 2007 AwkwardTV. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <BackRow/BRLayerController.h>

@class BRRenderScene, BRHeaderControl, BRTextControl, BRButtonControl;

@interface ATVRebootWarningController : BRLayerController
{
    BRHeaderControl *   _header;
    BRTextControl *     _message;
    BRButtonControl *   _button;
}

- (void) dealloc;

- (void) setTitle: (NSString *) title;
- (NSString *) title;

- (void) setMessage: (NSString *) message;
- (NSString *) message;

- (void) setButtonTitle: (NSString *) title
                 action: (SEL) action
                 target: (id) target;
- (NSString *) buttonTitle;
- (SEL) buttonAction;
- (id) buttonTarget;

- (void) doLayout;

@end
