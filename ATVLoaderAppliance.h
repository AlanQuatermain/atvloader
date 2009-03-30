//
//  ATVLoaderAppliance.h
//  AwkwardTV
//
//  Created by Alan Quatermain on 02/04/07.
//  Copyright 2007 AwkwardTV. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <BackRow/BRAppliance.h>
#import <BackRow/BRMediaMenuController.h>

@interface ATVLoaderAppliance : BRAppliance
{
}

+ (NSString *) className;

- (id) init;
- (void) dealloc;
- (NSString *) moduleName;
+ (NSString *) moduleKey;
- (NSString *) moduleKey;
- (BRMenuController *) applianceControllerWithScene: (BRRenderScene *) scene;

@end
