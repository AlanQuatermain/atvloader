//
//  ATVPluginInfoController.h
//  AwkwardTV
//
//  Created by Alan Quatermain on 08/04/07.
//  Copyright 2007 AwkwardTV. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <BackRow/BRLayerController.h>

@class BRHeaderControl, BRImageControl, BRVerticalScrollControl, BRButtonControl;
@class BRRenderScene, BRTexture;

@interface ATVPluginInfoController : BRLayerController
{
    BRHeaderControl *           _header;
    BRImageControl *            _image;
    BRVerticalScrollControl *   _document;
    BRButtonControl *           _button;

    NSDictionary *              _pluginInfo;
}

+ (NSString *) controllerLabel;

- (id) initWithScene: (BRRenderScene *) scene;
- (void) dealloc;

- (NSDictionary *) pluginDownloadInfo;

- (void) setHeaderTitle: (NSString *) title;
- (void) setHeaderIcon: (BRTexture *) icon
      horizontalOffset: (float) hOffset
         kerningFactor: (float) kerning;

- (void) setImage: (CGImageRef) image;
- (void) setImage: (CGImageRef) image downsampleTo: (NSSize) size;
- (void) setImageReflectionAmount: (float) amount;
- (void) setImageReflectionOffset: (float) offset;

// this is the same dictionary that gets downloaded from
// plugins.awkwardtv.org
- (void) setPluginInfo: (NSDictionary *) info;

- (void) setButtonTitle: (NSString *) title action: (SEL) action target: (id) target;

- (void) doLayout;

@end
