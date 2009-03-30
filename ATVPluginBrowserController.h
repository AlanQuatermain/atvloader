//
//  ATVPluginBrowserController.h
//  AwkwardTV
//
//  Created by Alan Quatermain on 03/04/07.
//  Copyright 2007 AwkwardTV. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <BackRow/BackRow.h>
#import "ATVURLDataRetriever.h"

@class BRRenderScene;

@interface ATVPluginBrowserController : BRMediaMenuController
{
    NSArray *               _plugins;
    ATVURLDataRetriever *   _asyncLoader;
    NSString *              _imageName;
    NSDictionary *          _pluginInfo;
    NSArray *               _installedPlugins;
}

+ (NSString *) controllerLabel;

- (id) initWithPlugins: (NSArray *) plugins scene: (BRRenderScene *) scene;
- (void) dealloc;

- (BOOL) isNetworkDependent;

- (void) itemSelected: (long) row;
- (id <BRMediaPreviewController>) previewControllerForItem: (long) item;

- (long) itemCount;
- (id) itemForRow: (long) row;
- (NSString *) titleForRow: (long) row;
- (long) rowForTitle: (NSString *) title;

@end
