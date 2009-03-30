//
//  ATVPluginIconPreviewController.m
//  AwkwardTV
//
//  Created by Alan Quatermain on 08/04/07.
//  Copyright 2007 AwkwardTV. All rights reserved.
//

#import "ATVPluginIconPreviewController.h"
#import "ATVLogger.h"
#import <BackRow/BackRow.h>
#import "BackRowUtils.h"

@interface ATVPluginIconPreviewController (Private)

- (void) _imageLoaded: (NSNotification *) obj;

- (void) setupSpinnerPanel;
- (void) setupImagePanel;

@end

@implementation ATVPluginIconPreviewController

- (id) initWithIconURL: (NSURL *) url scene: (BRRenderScene *) scene
{
    if ( [super initWithScene: scene] == nil )
        return ( nil );

    _imagePanel = [[BRPanel alloc] initWithScene: scene];
    _image = [[BRImageControl alloc] initWithScene: scene];

    BRImageManager * imageManager = [BRImageManager sharedInstance];
    _imageName = [[imageManager imageNameFromURL: url] retain];

    if ( [imageManager isImageAvailable: _imageName] == NO )
    {
        ATVDebugLog( @"Fetching image for name '%@'...", _imageName );
        // register for image notifications, then request the image
        // from the manager
        [[NSNotificationCenter defaultCenter] addObserver: self
                                                 selector: @selector(_imageLoaded:)
                                                     name: @"BRAssetImageUpdated"
                                                   object: nil];

        // ask the image manager to fetch this image and write it into
        // its cache
        [imageManager writeImageFromURL: url];

        // create the wait spinner in this case
        _spinner = [[BRWaitSpinnerControl alloc] initWithScene: scene];
        _spinnerPanel = [[BRPanel alloc] initWithScene: scene];
        [_spinnerPanel addControl: _spinner];
        [self addControl: _spinnerPanel];

        _loaded = NO;
    }
    else
    {
        // use the cached version
        [_image setImage: [imageManager imageNamed: _imageName]];
        ATVDebugLog( @"Cached version of image '%@' already loaded", _imageName );

        _loaded = YES;
    }

    // set image transparent, since we'll be fading ourselves
    [_image setAlphaValue: 0.0f];

    [_imagePanel addControl: _image];
    [self addControl: _imagePanel];

    return ( self );
}

- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [_imageName release];
    [_image release];
    [_spinner release];
    [_imagePanel release];
    [_spinnerPanel release];

    [super dealloc];
}

- (id) layer
{
    return ( [self masterLayer] );
}

- (void) activate
{
    if ( _loaded )
        [self setupImagePanel];
    else
        [self setupSpinnerPanel];
}

- (void) willLoseFocus
{
}

- (void) willRegainFocus
{
}

- (void) willDeactivate
{
    [_spinner stopSpinning];
    [[NSNotificationCenter defaultCenter] removeObserver: self
                                                    name: @"BRAssetImageUpdated"
                                                  object: nil];
}

- (void) deactivate
{
}

- (BOOL) fadeLayerIn
{
    return ( YES );
}

@end

@implementation ATVPluginIconPreviewController (Private)

- (void) _imageLoaded: (NSNotification *) obj
{
    ATVDebugLog( @"Received image load notification" );
    if ( _imageName == nil )
    {
        ATVDebugLog( @"We're not interested" );
        [[NSNotificationCenter defaultCenter] removeObserver: self
                                                        name: @"BRAssetImageUpdated"
                                                      object: nil];
        return;
    }

    NSDictionary * dict = [obj userInfo];
    ATVDebugLog( @"Notification asset is '%@'", [dict objectForKey: @"BRMediaAssetKey"] );
    if ( [_imageName isEqualToString: [dict objectForKey: @"BRMediaAssetKey"]] )
    {
        // this is us
        [[NSNotificationCenter defaultCenter] removeObserver: self
                                                        name: @"BRAssetImageUpdated"
                                                      object: nil];
        [_imageName release];
        _imageName = nil;

        [_image setImage: (CGImageRef) [dict objectForKey: @"BRImageKey"]];
        [_image setAlphaValue: 0.0f];
        [self setupImagePanel];
        [_imagePanel setAlphaValue: 0.0f];

        //_loaded = YES;

        // reset dimensions and fade in.
        //[self activate];

        // fade image in, fade spinner out
        BRValueAnimation * valanim;
        BRAggregateAnimation * animation;

        animation = [BRAggregateAnimation animationWithScene: [self scene]];
        [animation setDuration: [[BRThemeInfo sharedTheme] fadeThroughBlackDuration]];

        valanim = [BRValueAnimation fadeInAnimationWithTarget: _imagePanel
                                                        scene: [self scene]];
        [animation addAnimation: valanim];

        valanim = [BRValueAnimation fadeOutAnimationWithTarget: _spinnerPanel
                                                         scene: [self scene]];
        [animation addAnimation: valanim];

        [animation run];

        // stop the spinner
        [_spinner stopSpinning];
    }
}

- (void) setupImagePanel
{
    NSRect frame = [[self layer] frame];
    BRColumnLayoutManager * layout = [_imagePanel layoutManager];

    frame.size.width *= 0.83333333333f;
    [_imagePanel setFrame: frame];

    float border = (frame.size.width + frame.size.width) * 0.082f;
    [layout setHorizontalBorder: border];
    [_imagePanel pack];

    // show the image
    NSRect imgFrame = [_image frame];
    border = frame.size.height * 0.186f;
    border += (frame.size.height * 0.64f) * 0.5f;
    border += (imgFrame.size.height * -0.5f);
    [layout setVerticalBorder: border];

    [_imagePanel pack];
}

- (void) setupSpinnerPanel
{
    NSRect frame = [[self layer] frame];
    BRColumnLayoutManager * layout = [_spinnerPanel layoutManager];

    frame.size.width *= 0.83333333333f;
    [_spinnerPanel setFrame: frame];

    float border = (frame.size.width + frame.size.width) * 0.082f;
    [layout setHorizontalBorder: border];
    [_spinnerPanel pack];

    NSRect spinnerFrame = [_spinner frame];
    border = frame.size.height * 0.186f;
    border += (frame.size.height * 0.64f) * 0.5f;
    border += (spinnerFrame.size.height * -0.5f);
    [layout setVerticalBorder: border];
    [_spinner startSpinning];

    [_spinnerPanel pack];
}

@end
