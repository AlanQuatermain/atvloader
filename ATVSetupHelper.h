//
//  ATVSetupHelper.h
//  AwkwardTV
//
//  Created by Alan Quatermain on 11/04/07.
//  Copyright 2007 AwkwardTV. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <BackRow/BRSingleton.h>

@interface ATVSetupHelper : BRSingleton
{
}

+ (id) singleton;
+ (void) setSingleton: (id) singleton;

+ (BOOL) isSSHInstalled;
+ (BOOL) isSSHEnabled;
+ (BOOL) isAFPEnabled;

- (void) cleanUpReplacedItems;

- (BOOL) updateSelf: (NSString *) path error: (NSError **) error;

- (BOOL) installApplianceAtPath: (NSString *) path error: (NSError **) error;
- (BOOL) installScreenSaverAtPath: (NSString *) path error: (NSError **) error;
- (BOOL) installQTCodecAtPath: (NSString *) path error: (NSError **) error;

- (BOOL) installSSHDaemon: (NSError **) error;

- (BOOL) enableSSHService: (BOOL) enable error: (NSError **) error;
- (BOOL) enableAFPService: (BOOL) enable error: (NSError **) error;

@end
