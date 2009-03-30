//
//  ATVPluginBrowserController.m
//  AwkwardTV
//
//  Created by Alan Quatermain on 03/04/07.
//  Copyright 2007 AwkwardTV. All rights reserved.
//

#import "ATVPluginBrowserController.h"
#import "ATVURLDataRetriever.h"
#import "ATVPluginInfoXMLParser.h"
#import "ATVPluginIconPreviewController.h"
#import "ATVPluginInfoController.h"
#import "ATVDownloadController.h"
#import "ATVRebootWarningController.h"
#import "ATVLogger.h"
#import "BackRowUtils.h"
#import <BackRow/BackRow.h>

@interface ATVPluginBrowserController (Private)

- (NSURL *) infoURLForPluginAtIndex: (long) index;
- (CGImageRef) _listIconImage;

// url background loader callbacks
- (void) failedToGetDataFromURL: (NSURL *) url error: (NSError *) error;
- (void) retrievedData: (NSData *) data fromURL: (NSURL *) url;

- (void) _installPlugin: (id) sender;
- (void) _pluginInstallAllowed: (id) sender;

- (BRLayerController *) _pluginInfoControllerWithInfo: (NSDictionary *) info
                                                image: (CGImageRef) image;

- (void) _gotScreenshot: (NSNotification *) obj;

@end

@implementation ATVPluginBrowserController

+ (NSString *) controllerLabel
{
    return ( @"org.awkwardtv.loader.pluginbrowser" );
}

- (id) initWithPlugins: (NSArray *) plugins scene: (BRRenderScene *) scene
{
    if ( [super initWithScene: scene] == nil )
        return ( nil );

    _plugins = [plugins retain];

    _installedPlugins = [[[BRApplianceManager sharedManager] applianceInfoList] copy];

    [[self list] setDatasource: self];
    [self setListTitle: BRLocalizedString( @"DownloadNewPlugins", @"Download Plugins menu title" )];

    CGImageRef listIcon = [self _listIconImage];
    BRTexture * tex = [BRBitmapTexture textureWithImage: listIcon
                                                context: [[self scene] resourceContext]
                                                 mipmap: YES];
    [self setListIcon: tex];

    [self addLabel: [ATVPluginBrowserController controllerLabel]];

    return ( self );
}

- (void) dealloc
{
    [_plugins release];
    [_asyncLoader release];
    [_installedPlugins release];
    [_imageName release];
    [_pluginInfo release];

    [super dealloc];
}

- (BOOL) isNetworkDependent
{
    return ( YES );
}

- (void) itemSelected: (long) row
{
    if ( row >= [_plugins count] )
        return;

    if ( _asyncLoader != nil )
    {
        ATVErrorLog( @"Already downloading plugin info !" );
        return;
    }

    // load the data for this plugin
    _asyncLoader = [ATVURLDataRetriever fetchDataFromURL: [self infoURLForPluginAtIndex: row]
                                             forDelegate: self];

    if ( _asyncLoader == nil )
        return;

    [_asyncLoader retain];

    // show a 'waiting' message
    NSString * title = [BRLocalizedStringManager
                        backRowLocalizedStringForKey: @"WaitPleaseWait" inFile: nil];

    NSString * msg = BRLocalizedString( @"LoadingPluginInfo", @"Shown while waiting for individual plugin info to download" );

    id controller = [[BRTextWithSpinnerController alloc]
                     initWithScene: [self scene]
                             title: title
                              text: msg
                          showBack: NO
                isNetworkDependent: YES];

    [controller autorelease];
    [controller showProgress: YES];

    [[self stack] pushController: controller];
}

- (id <BRMediaPreviewController>) previewControllerForItem: (long) index
{
    ATVDebugLog( @"-previewControllerForItem: %u called", (unsigned) index );
    if ( index >= [_plugins count] )
        return ( nil );

    // create a URL for the plugin's icon
    id str = [[_plugins objectAtIndex: index] objectForKey: @"icon"];
    ATVDebugLog( @"Got icon object '%@'", str );
    if ( (str == nil) || ([str length] == 0) )
        return ( nil );

    NSURL * url = [NSURL URLWithString: str];
    if ( url == nil )
        return ( nil );

    id controller = [[ATVPluginIconPreviewController alloc] initWithIconURL: url
                     scene: [self scene]];
    return ( [controller autorelease] );
}

- (long) itemCount
{
    return ( [_plugins count] );
}

- (id) itemForRow: (long) row
{
    if ( row >= [_plugins count] )
        return ( nil );

    NSDictionary * pluginDict = [_plugins objectAtIndex: row];
    BRTextMenuItemLayer * result = [BRTextMenuItemLayer menuItemWithScene: [self scene]];

    NSString * title = [pluginDict objectForKey: @"title"];

    // find out if it's an update from an installed version
    NSString * version = [pluginDict objectForKey: @"version"];

    // see if it's installed already
    NSEnumerator * enumerator = [_installedPlugins objectEnumerator];
    NSDictionary * obj = nil;
    NSString * cfBundleName = nil;

    while ( (obj = [enumerator nextObject]) != nil )
    {
        if ( [[obj objectForKey: @"FRApplianceName"] caseInsensitiveCompare: title] == NSOrderedSame )
            break;

        if ( [[obj objectForKey: @"FRApplianceName"] caseInsensitiveCompare:
            [pluginDict objectForKey: @"shortname"]] == NSOrderedSame )
            break;

        // No CFBundleName in the Apple plugins
        cfBundleName = [obj objectForKey: @"CFBundleName"];
        if ( cfBundleName != nil )
        {
            if ( [cfBundleName caseInsensitiveCompare: title] == NSOrderedSame )
            {
                break;
            }

            if ( [cfBundleName caseInsensitiveCompare:
                [pluginDict objectForKey: @"shortname"]] == NSOrderedSame )
            {
                break;
            }

            cfBundleName = nil;
        }

        // nasty horrible evil hack
        cfBundleName = [obj objectForKey: @"ATVPluginShortName"];
        if ( cfBundleName != nil )
        {
            if ( [cfBundleName caseInsensitiveCompare:
                [pluginDict objectForKey: @"shortname"]] == NSOrderedSame )
            {
                break;
            }

            cfBundleName = nil;
        }
    }

    if ( obj != nil )
    {
        NSString * oldVersion = [obj objectForKey: @"CFBundleShortVersionString"];
        if ( oldVersion == nil )
            oldVersion = [obj objectForKey: @"CFBundleVersion"];

        if ( [version compare: oldVersion options: NSNumericSearch] == NSOrderedDescending )
        {
            // set a right-hand string noting the upgrade
            [result setRightJustifiedText: BRLocalizedString(@"Updated", @"Text tag for updated plugin list items")];
        }
    }

    // do this at the end, otherwise it won't render the
    // right-justified text string
    [result setTitle: title];

    return ( result );
}

- (NSString *) titleForRow: (long) row
{
    if ( row >= [_plugins count] )
        return ( nil );

    return ( [[_plugins objectAtIndex: row] objectForKey: @"title"] );
}

- (long) rowForTitle: (NSString *) title
{
    long result = -1;

    long i, count = [_plugins count];
    for ( i = 0; i < count; i++ )
    {
        if ( [title isEqualToString: [self titleForRow: i]] )
        {
            result = i;
            break;
        }
    }

    return ( result );
}

@end

@implementation ATVPluginBrowserController (Private)

- (NSURL *) infoURLForPluginAtIndex: (long) index
{
    NSString * name = [[_plugins objectAtIndex: index] objectForKey: @"shortname"];
    NSString * base = @"http://plugins.awkwardtv.org/xml/";

    return ( [NSURL URLWithString: [NSString stringWithFormat: @"%@?p=%@", base, name]] );
}

- (CGImageRef) _listIconImage
{
    static NSURL * imageURL = nil;

    if ( imageURL == nil )
    {
        NSBundle * bundle = [NSBundle bundleForClass: [self class]];
        NSString * path = [bundle pathForResource: @"BrowserListIcon" ofType: @"png"];

        if ( path != nil )
            imageURL = [[NSURL alloc] initFileURLWithPath: path];
    }

    if ( imageURL == nil )
        return ( NULL );

    return ( CreateImageForURL((CFURLRef)imageURL) );
}

- (void) failedToGetDataFromURL: (NSURL *) url error: (NSError *) error
{
    // show an error alert
    id controller = [BRAlertController alertForError: error withScene: [self scene]];
    id current = [[self stack] peekController];

    // if we're currently waiting, replace that controller. Otherwise,
    // pile this one on top of the current one
    if ( [current isMemberOfClass: [BRTextWithSpinnerController class]] )
    {
        [current showProgress: NO];
        [[self stack] swapController: controller];
    }
    else
    {
        [[self stack] pushController: controller];
    }

    // done with the loader now
    [_asyncLoader release];
    _asyncLoader = nil;
}

- (void) retrievedData: (NSData *) data fromURL: (NSURL *) url
{
    // don't do anything if the UI is not in the waiting state
    id currentController = [[self stack] peekController];
    if ( [currentController isMemberOfClass: [BRTextWithSpinnerController class]] == NO )
        return;

    // loaded the data, now parse it
    NSError * error = nil;
    NSDictionary * details = [ATVPluginInfoXMLParser pluginDetailsFromXMLData: data error: &error];
    id controller = nil;

    if ( (error != nil) || (details == nil) )
    {
        // setup an error dialog controller
        controller = [BRAlertController alertForError: error withScene: [self scene]];
    }
    else
    {
        /*
        // put up an alert containing the plugin info itself
        NSDictionary * info = [details objectForKey: @"info"];
        NSString * description = [NSString stringWithFormat: @"%@\n\n%@",
                                  [info objectForKey: @"summary"],
                                  [info objectForKey: @"description"]];

        controller = [BRAlertController alertOfType: 1
                                             titled: [details objectForKey: @"title"]
                                        primaryText: [info objectForKey: @"subtitle"]
                                      secondaryText: description
                                          withScene: [self scene]];
         */

        // see if we already have the screenshot downloaded, or if we
        // need one at all
        NSString * screenStr = [details objectForKey: @"screenshot"];
        NSURL * imageURL = nil;
        if ( (screenStr != nil) && ([screenStr length] != 0) )
            imageURL = [NSURL URLWithString: screenStr];

        if ( imageURL == nil )
        {
            // just get a non-image controller now
            controller = [self _pluginInfoControllerWithInfo: details image: NULL];
        }
        else
        {
            // see if we have the image already
            BRImageManager * manager = [BRImageManager sharedInstance];
            screenStr = [manager imageNameFromURL: imageURL];
            if ( [manager isImageAvailable: screenStr] )
            {
                // grab the image and use immediately
                controller = [self _pluginInfoControllerWithInfo: details
                                                           image: [manager imageNamed: screenStr]];
            }
            else
            {
                // start a load request for the image and return a wait
                // controller
                [[NSNotificationCenter defaultCenter] addObserver: self
                                                         selector: @selector(_gotScreenshot:)
                                                             name: @"BRAssetImageUpdated"
                                                           object: nil];
                if ( _imageName != nil )
                    [_imageName release];
                _imageName = [screenStr retain];

                if ( _pluginInfo != nil )
                    [_pluginInfo release];
                _pluginInfo = [details retain];

                [manager writeImageFromURL: imageURL];

                    // show a 'waiting' message
                NSString * title = [BRLocalizedStringManager
                                    backRowLocalizedStringForKey: @"WaitPleaseWait" inFile: nil];

                NSString * msg = BRLocalizedString( @"LoadingPluginImages", @"Shown while waiting for individual plugin images to download" );

                controller = [[BRTextWithSpinnerController alloc]
                              initWithScene: [self scene]
                                      title: title
                                       text: msg
                                   showBack: NO
                         isNetworkDependent: YES];

                [controller showProgress: YES];
                [controller autorelease];
            }
        }
    }

    // switch controllers
    if ( controller != nil )
        [[self stack] swapController: controller];
    else
        [[self stack] popController];   // handle allocation errors somehow

    // done with the loader now
    [_asyncLoader release];
    _asyncLoader = nil;
}

- (void) _installPlugin: (id) sender
{
    /*
    BRLog( @"I'd install a plugin at this point, but I won't right now." );

    id obj = [BRAlertController alertOfType: 1
                                     titled: BRLocalizedString( @"UnimplementedFeature", @"" )
                                primaryText: BRLocalizedString( @"UnimplementedPrimary", @"" )
                              secondaryText: BRLocalizedString( @"UnimplementedSecondary", @"" )
                                  withScene: [self scene]];

    [[self stack] swapController: obj];
    */
    id controller = [[self stack] peekController];
    if ( [controller isMemberOfClass: [ATVPluginInfoController class]] == NO )
        return;

    // we're downloading a plugin, so put up a warning and ask if the
    // user is willing to restart after installing
    ATVRebootWarningController * obj = [[ATVRebootWarningController alloc]
                                        initWithScene: [self scene]];

    [obj setTitle: BRLocalizedString(@"RebootWarningTitle", @"Title for Advance Reboot Warning alert")];

    NSBundle * bundle = [NSBundle bundleForClass: [self class]];
    NSString * path = [bundle pathForResource: @"AdvPluginReboot" ofType: @"txt"];
    if ( path != nil )
        [obj setMessage: [NSString stringWithContentsOfFile: path]];

    [obj setButtonTitle: BRLocalizedString(@"OK", @"Button Title")
                 action: @selector(_pluginInstallAllowed:)
                 target: self];

    [obj doLayout];

    [[self stack] pushController: obj];
}

- (void) _pluginInstallAllowed: (id) sender
{
#pragma unused(sender)
    id controller = [[self stack] peekController];
    if ( [controller isMemberOfClass: [ATVRebootWarningController class]] == NO )
        return;

    // locate the info controller (we pull info from it)
    // the API changes between BackRow v2.0 and v2.1
    if ( [[self stack] respondsToSelector: @selector(controllerLabelled:)] )
        controller = [[self stack] controllerLabelled: [ATVPluginInfoController controllerLabel]];
    else
        controller = [[self stack] controllerLabelled: [ATVPluginInfoController controllerLabel]
                                              deepest: NO];

    if ( controller == nil )
    {
        [[self stack] popController];
        return;
    }

    // grab the plugin info
    NSDictionary * dict = [controller pluginDownloadInfo];
    if ( dict == nil )
        return;

    // setup the download controller
    controller = [[ATVDownloadController alloc] initWithType: kPluginDownloadType
                                                downloadInfo: dict
                                                       scene: [self scene]
                                                    delegate: self];

    // replace everything above ourselves with this new controller
    [[self stack] replaceControllersAboveLabel: [ATVPluginBrowserController controllerLabel]
                                withController: controller];
}

- (BRLayerController *) _pluginInfoControllerWithInfo: (NSDictionary *) info
                                                image: (CGImageRef) image
{
    ATVPluginInfoController * controller;
    controller = [[ATVPluginInfoController alloc] initWithScene: [self scene]];

    if ( controller != nil )
    {
        [controller setHeaderTitle: [info objectForKey: @"title"]];

        if ( image != NULL )
            [controller setImage: image];

        [controller setButtonTitle: BRLocalizedString(@"Install", @"'Install plugin' button title")
                            action: @selector(_installPlugin:)
                            target: self];

        [controller setPluginInfo: info];

        // Note to self: don't forget this!
        [controller doLayout];
    }

    return ( [controller autorelease] );
}

- (void) _gotScreenshot: (NSNotification *) obj
{
    if ( _imageName == nil )
    {
        [[NSNotificationCenter defaultCenter] removeObserver: self
                                                        name: @"BRAssetImageUpdated"
                                                      object: nil];
        return;
    }

    NSDictionary * userInfo = [obj userInfo];
    if ( [_imageName isEqualToString: [userInfo objectForKey: @"BRMediaAssetKey"]] )
    {
        [[NSNotificationCenter defaultCenter] removeObserver: self
                                                        name: @"BRAssetImageUpdated"
                                                      object: nil];

        [_imageName release];
        _imageName = nil;

        id controller = [[self stack] peekController];
        if ( [controller isMemberOfClass: [BRTextWithSpinnerController class]] )
        {
            CGImageRef image = (CGImageRef) [userInfo objectForKey: @"BRImageKey"];
            controller = [self _pluginInfoControllerWithInfo: _pluginInfo
                                                       image: image];
        }
        else
        {
            controller = nil;
        }

        [_pluginInfo release];
        _pluginInfo = nil;

        if ( controller != nil )
            [[self stack] swapController: controller];
        else
            [[self stack] popController];
    }
}

@end
