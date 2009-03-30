//
//  ATVPluginIconPreviewController.h
//  AwkwardTV
//
//  Created by Alan Quatermain on 08/04/07.
//  Copyright 2007 AwkwardTV. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <BackRow/BRLayerController.h>
#import <BackRow/BRMediaPreviewControllerProtocol.h>

@class BRImageControl, BRRenderScene, BRPanel, BRWaitSpinnerControl;

@interface ATVPluginIconPreviewController : BRLayerController <BRMediaPreviewController>
{
    NSString *              _imageName;
    BRPanel *               _imagePanel;
    BRPanel *               _spinnerPanel;
    BRImageControl *        _image;
    BRWaitSpinnerControl *  _spinner;
    BOOL                    _loaded;
}

- (id) initWithIconURL: (NSURL *) url scene: (BRRenderScene *) scene;
- (void) dealloc;

- (id) layer;
- (void) activate;
- (void) willLoseFocus;
- (void) willRegainFocus;
- (void) willDeactivate;
- (void) deactivate;
- (BOOL) fadeLayerIn;

@end
