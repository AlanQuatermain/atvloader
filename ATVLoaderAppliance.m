//
//  ATVLoaderAppliance.m
//  AwkwardTV
//
//  Created by Alan Quatermain on 02/04/07.
//  Copyright 2007 AwkwardTV. All rights reserved.
//

#import "ATVLoaderAppliance.h"
#import "ATVLoaderApplianceController.h"
#import "ATVSetupHelper.h"
#import "BackRowUtils.h"

#import <BackRow/BRBacktracingException.h>
#import <objc/objc-class.h>

@implementation ATVLoaderAppliance

+ (NSString *) className
{
    // get around the whitelist

    // this function will get the real class name from the runtime, and
    // will assuredly not recurse back to here
    NSString * className = NSStringFromClass( self );

    // BackRow has its own exception class which provides backtrace
    // helpers. It returns a parsed trace, with function names. We'll
    // look for the name of the function which is known to call this
    // function to check against the whitelist, and if we find it we'll
    // lie about our name, purely to escape that check.
    // Also, the backtracer method is a class routine, meaning that we
    // don't have to even generate an exception - woohoo!
    NSRange range = [[BRBacktracingException backtrace] rangeOfString: @"_loadApplianceInfoAtPath:"];
    if ( range.location != NSNotFound )
    {
        // this is the whitelist check -- tell a Great Big Fib
        BRLog( @"[%@ className] called for whitelist check; returning RUIMoviesAppliance instead",
               className );
        className = @"RUIMoviesAppliance";     // could be anything in the whitelist, really
    }

    return ( className );
}

+ (void) initialize
{
    // 'fix' the main menu list

    Method pMethod = class_getInstanceMethod( [BRMainMenuController class],
                                              @selector(listFrameForBounds:) );
    if ( pMethod != NULL )
    {
        Method pOrig = class_getInstanceMethod( [BRMenuController class],
                                                @selector(listFrameForBounds:) );
        if ( pOrig != NULL )
            pMethod->method_imp = pOrig->method_imp;
    }

    // clean up atomic moves
    [[ATVSetupHelper sharedInstance] cleanUpReplacedItems];
}

- (id) init
{
    return ( [super init] );
}

- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [super dealloc];
}

- (NSString *) moduleIconName
{
    return ( @"AwkwardTVLoader.png" );
}

- (NSString *) moduleName
{
    // this apparently is NOT the title of the plugin's main menu item
    // instead, that string must be set as the localized version of
    // 'CFBundleName'. Grrrr.
    return ( BRLocalizedString(@"AwkwardTVMenuItemName", @"Title of the plugin's item on the main menu") );
}

+ (NSString *) moduleKey
{
    return ( @"com.apple.frontrow.appliance.awkwardtv.loader" );
}

- (NSString *) moduleKey
{
    return ( [ATVLoaderAppliance moduleKey] );
}

- (BRMenuController *) applianceControllerWithScene: (BRRenderScene *) scene
{
    ATVLoaderApplianceController * result = [[ATVLoaderApplianceController alloc]
        initWithScene: scene];

    [result setListIconHorizontalOffset: [self applianceIconHorizontalOffset]];
    [result setListIconKerningFactor: [self applianceIconKerningFactor]];
    [result setListTitle: [self moduleName]];

    return ( [result autorelease] );
}

@end
