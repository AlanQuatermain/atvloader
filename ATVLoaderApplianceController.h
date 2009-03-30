//
//  ATVLoaderApplianceController.h
//  AwkwardTV
//
//  Created by Alan Quatermain on 02/04/07.
//  Copyright 2007 AwkwardTV. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <BackRow/BackRow.h>

#import "ATVURLDataRetriever.h"

@class BRRenderScene;

// this menu controller will include a folder-type item for a plugin
// browser/selector interface, a separator, and some setup items,
// including SSH enable/disable and AFP enable/disable
@interface ATVLoaderApplianceController : BRMediaMenuController
{
    unsigned int            _pluginListRequested:1;
    BRAdornedMenuItemLayer *_pluginChooserItem;
    NSArray *               _setupItems;
    ATVURLDataRetriever *   _asyncLoader;
}

- (id) initWithScene: (BRRenderScene *) scene;
- (void) dealloc;

- (BOOL) menuDisplaysLeftIcon;
- (BOOL) isVolatile;
- (long) defaultIndex;

- (id <BRMediaPreviewController>) previewControllerForItem: (long) index;

- (void) itemSelected: (long) index;
- (void) wasExhumedByPoppingController: (id) controller;
- (void) willBePopped;

@end
