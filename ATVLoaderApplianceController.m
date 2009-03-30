//
//  ATVLoaderApplianceController.m
//  AwkwardTV
//
//  Created by Alan Quatermain on 02/04/07.
//  Copyright 2007 AwkwardTV. All rights reserved.
//

#import "ATVLoaderApplianceController.h"
#import "BackRowUtils.h"
#import "ATVPluginListXMLParser.h"
#import "ATVPluginBrowserController.h"
#import "ATVSetupHelper.h"
#import "ATVLogger.h"

#import <BackRow/BackRow.h>

#define REALLY_CHANGE_THINGS    1
#define PRINT_KEY_CODES         0

@interface ATVLoaderApplianceController (MenuDataSource)

- (id) itemForRow: (long) row;
- (long) itemCount;
- (NSString *) titleForRow: (long) row;
- (long) rowForTitle: (NSString *) title;

@end

@interface ATVLoaderApplianceController (Private)

- (void) _setupMenuItems;

- (NSString *) _pathForBundleResource: (NSString *) name ofType: (NSString *) type;
- (CGImageRef) _pluginsPreviewImage;

- (id <BRMediaPreviewController>) _pluginsPreviewController;

- (BOOL) _sshEnabled;
- (BOOL) _afpEnabled;

- (BRLayerController *) _sshSetupController;
- (BRLayerController *) _afpSetupController;
- (BRLayerController *) _showAbout;
- (BRLayerController *) _quitBackRow;

- (void) _enableSSH: (id) sender;
- (void) _disableSSH: (id) sender;

- (void) _enableAFP: (id) sender;
- (void) _disableAFP: (id) sender;

- (BRLayerController *) _pluginChooserController;

// URL loader callbacks
- (void) failedToGetDataFromURL: (NSURL *) url error: (NSError *) error;
- (void) retrievedData: (NSData *) data fromURL: (NSURL *) url;

@end

@implementation ATVLoaderApplianceController

- (id) initWithScene: (BRRenderScene *) scene
{
    if ( [super initWithScene: scene] == nil )
        return ( nil );

    [self _setupMenuItems];

    BRListControl * list = [self list];
    [list setDatasource: self];
    [list setDividerIndex: 1];  // single folder item at top

    return ( self );
}

- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [_pluginChooserItem release];
    [_setupItems release];
    [_asyncLoader release];

    [super dealloc];
}

#if PRINT_KEY_CODES
- (BOOL) brEventAction: (BREvent *) event
{
    ATVLog( @"Received event: %@", [event description] );
    return ( [super brEventAction: event] );
}
#endif

- (BOOL) menuDisplaysLeftIcon
{
    return ( YES );
}

- (BOOL) isVolatile
{
    return ( YES );
}

- (long) defaultIndex
{
    return ( 0 );
}

- (id <BRMediaPreviewController>) previewControllerForItem: (long) index
{
    // no preview for the plugin chooser menu
    if ( index == 0 )
        return ( [self _pluginsPreviewController] );
/*
    // for the others, we get the appropriate custom preview
    // controller, which will show some informational text
    index--;

    if ( index < [_setupItems count] )
        return ( [self performSelector: [[_setupItems objectAtIndex: index]
                                         mediaPreviewSelector]] );
*/
    return ( nil );
}

- (void) itemSelected: (long) index
{
    //[self setSelectedObject: nil];

    BRLayerController * controller = nil;

    if ( index == 0 )
    {
        // this is the plugin chooser menu
        controller = [self _pluginChooserController];
    }
    else
    {
        index--;
        id obj = [_setupItems objectAtIndex: index];
        controller = [self performSelector: [obj menuActionSelector]];
    }

    if ( controller == nil )
        return;

    [[self stack] pushController: controller];
}

- (void) wasExhumedByPoppingController: (id) controller
{
    if ( [controller isMemberOfClass: [BRDocumentController class]] )
    {
        [_setupItems release];
        _setupItems = nil;
        [self _setupMenuItems];
    }

    [super wasExhumedByPoppingController: controller];
}

- (void) willBePopped
{
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [super willBePopped];
}

@end

@implementation ATVLoaderApplianceController (MenuDataSource)

- (id) itemForRow: (long) row
{
    id result = nil;

    // plugin chooser menu item
    if ( row == 0 )
        result = _pluginChooserItem;
    else
        result = [[_setupItems objectAtIndex: row - 1] menuItem];

    return ( result );
}

- (long) itemCount
{
    return ( [_setupItems count] + 1 );
}

- (NSString *) titleForRow: (long) row
{
    // plugin chooser menu item
    if ( row == 0 )
        return ( [[_pluginChooserItem textItem] title] );

    row--;
    if ( row >= [_setupItems count] )
        return ( nil );

    id obj = [[_setupItems objectAtIndex: row] menuItem];
    if ( [obj isKindOfClass: [BRAdornedMenuItemLayer class]] )
        return ( [[obj textItem] title] );

    return ( [obj title] );
}

- (long) rowForTitle: (NSString *) title
{
    long result = -1;
    long i, count = [self itemCount];
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

@implementation ATVLoaderApplianceController (Private)

- (void) _setupMenuItems
{
    BRAdornedMenuItemLayer * item = nil;
    BRMenuItemMediator * mediator = nil;
    NSString * title = nil;
    id icon = nil;

    if ( _pluginChooserItem == nil )
    {
        item = [BRAdornedMenuItemLayer adornedNetworkMenuItemWithScene: [self scene]];
        title = BRLocalizedString( @"DownloadNewPlugins", @"Download Plugins menu title" );
        [[item textItem] setTitle: title];
        _pluginChooserItem = [item retain];
    }

    if ( _setupItems == nil )
    {
        NSMutableArray * array = [NSMutableArray array];

        item = [BRAdornedMenuItemLayer adornedMenuItemWithScene: [self scene]];

        BOOL enabled = [self _sshEnabled];
        if ( enabled )
        {
            icon = [[BRThemeInfo sharedTheme] unplayedPodcastImageForScene: [self scene]];
            title = BRLocalizedString( @"SSHEnabled", @"SSH Menu item title when SSH server is enabled" );
        }
        else
        {
            icon = [[BRThemeInfo sharedTheme] playedPodcastImageForScene: [self scene]];
            title = BRLocalizedString( @"SSHDisabled", @"SSH Menu item title when SSH server is disabled" );
        }

        [[item textItem] setTitle: title];
        [item setLeftIcon: icon];

        mediator = [[[BRMenuItemMediator alloc] initWithMenuItem: item] autorelease]; 
        [mediator setMenuActionSelector: @selector(_sshSetupController)];

        [array addObject: mediator];

        item = [BRAdornedMenuItemLayer adornedMenuItemWithScene: [self scene]];

        enabled = [self _afpEnabled];
        if ( enabled )
        {
            icon = [[BRThemeInfo sharedTheme] unplayedPodcastImageForScene: [self scene]];
            title = BRLocalizedString( @"AFPEnabled", @"SSH Menu item title when AFP server is enabled" );
        }
        else
        {
            icon = [[BRThemeInfo sharedTheme] playedPodcastImageForScene: [self scene]];
            title = BRLocalizedString( @"AFPDisabled", @"SSH Menu item title when AFP server is disabled" );
        }

        [[item textItem] setTitle: title];
        [item setLeftIcon: icon];

        mediator = [[[BRMenuItemMediator alloc] initWithMenuItem: item] autorelease];
        [mediator setMenuActionSelector: @selector(_afpSetupController)];

        [array addObject: mediator];

        BRTextMenuItemLayer * about = [BRTextMenuItemLayer menuItemWithScene: [self scene]];
        [about setTitle: BRLocalizedString(@"About", @"About menu item title")];

        mediator = [[[BRMenuItemMediator alloc] initWithMenuItem: about] autorelease];
        [mediator setMenuActionSelector: @selector(_showAbout)];

        [array addObject: mediator];

        if ( [[RUIPreferenceManager sharedPreferences] boolForKey: @"ShowQuitMenuItem"
                                                        forDomain: @"org.awkwardtv.appliance.loader"
                                         withValueForMissingPrefs: NO] )
        {
            // add something which will quit the ATV UI *properly*
            BRTextMenuItemLayer * txt = [BRTextMenuItemLayer menuItemWithScene: [self scene]];
            [txt setTitle: BRLocalizedString(@"Quit", @"Quit")];

            mediator = [[[BRMenuItemMediator alloc] initWithMenuItem: txt] autorelease];
            [mediator setMenuActionSelector: @selector(_quitBackRow)];

            [array addObject: mediator];
        }

        _setupItems = [[NSArray alloc] initWithArray: array];
        [[self list] reload];
    }
}

- (NSString *) _pathForBundleResource: (NSString *) name ofType: (NSString *) type
{
    NSBundle * bundle = [NSBundle bundleForClass: [self class]];
    return ( [bundle pathForResource: name ofType: type] );
}

- (CGImageRef) _pluginsPreviewImage
{
    static NSURL * imageURL = nil;

    if ( imageURL == nil )
    {
        NSString * path = [self _pathForBundleResource: @"BrowserPreviewIcon" ofType: @"png"];

        if ( path != nil )
            imageURL = [[NSURL alloc] initFileURLWithPath: path];
    }

    if ( imageURL == nil )
        return ( NULL );

    return ( CreateImageForURL((CFURLRef)imageURL) );
}

- (id <BRMediaPreviewController>) _pluginsPreviewController
{
    ATVDebugLog( @"Fetching Plugins Preview Controller" );

    // get the image location in our bundle
    CGImageRef image = [self _pluginsPreviewImage];

    BRImageAndSyncingPreviewController * result = [[[BRImageAndSyncingPreviewController alloc]
        initWithScene: [self scene]] autorelease];

    [result setImage: image];
    [result setHasSyncProgress: NO];
/*
    BRSimpleMediaAsset * asset = [[[BRSimpleMediaAsset alloc] initWithMediaURL:
        [NSURL fileURLWithPath: path]] autorelease];

    id controller = [BRMediaPreviewControllerFactory previewControllerForAsset: asset
                     withDelegate: nil scene: [self scene]];
*/
    return ( result );
}

- (BOOL) _sshEnabled
{
#if REALLY_CHANGE_THINGS
    return ( [ATVSetupHelper isSSHEnabled] );
#else
    return ( [[RUIPreferenceManager sharedPreferences] boolForKey: @"AwkwardSSHEnabled"
                                                        forDomain: @"org.awkwardtv.servers"
                                         withValueForMissingPrefs: NO] );
#endif
}

- (BOOL) _afpEnabled
{
#if REALLY_CHANGE_THINGS
    return ( [ATVSetupHelper isAFPEnabled] );
#else
    return ( [[RUIPreferenceManager sharedPreferences] boolForKey: @"AwkwardAFPEnabled"
                                                        forDomain: @"org.awkwardtv.servers"
                                         withValueForMissingPrefs: NO] );
#endif
}

- (BRLayerController *) _sshSetupController
{
    // SSH help file path
    NSString * path = [self _pathForBundleResource: @"SSHInfo" ofType: @"txt"];
    if ( path == nil )
        return ( nil );

    BRDocumentController * result = [[BRDocumentController alloc] initWithScene: [self scene]];

    // by default uses Unicode (UTF-16), which is what we used when
    // creating the file
    [result setDocumentPath: path];

    if ( [self _sshEnabled] )
    {
        [result setHeaderTitle: BRLocalizedString(@"Disable SSH Server", @"Disable SSH Document Header")];
        [result setButtonTitle: BRLocalizedString(@"Disable", @"Disable Service Button Title")
                        action: @selector(_disableSSH:)
                        target: self];
    }
    else
    {
        [result setHeaderTitle: BRLocalizedString(@"Enable SSH Server", @"Enable SSH Document Header")];
        [result setButtonTitle: BRLocalizedString(@"Enable", @"Enable Service Button Title")
                        action: @selector(_enableSSH:)
                        target: self];
    }

    [result doLayout];

    return ( [result autorelease] );
}

- (BRLayerController *) _afpSetupController
{
    // AFP help file path
    NSString * path = [self _pathForBundleResource: @"AFPInfo" ofType: @"txt"];
    if ( path == nil )
        return ( nil );

    BRDocumentController * result = [[BRDocumentController alloc] initWithScene: [self scene]];

    // default encoding used is Unicode (UTF-16), which is what we use
    // for our files
    [result setDocumentPath: path];

    if ( [self _afpEnabled] )
    {
        [result setHeaderTitle: BRLocalizedString(@"Disable AFP Server", @"Disable AFP Document Header")];
        [result setButtonTitle: BRLocalizedString(@"Disable", @"Disable Service Button Title")
                        action: @selector(_disableAFP:)
                        target: self];
    }
    else
    {
        [result setHeaderTitle: BRLocalizedString(@"Enable AFP Server", @"Enable AFP Document Header")];
        [result setButtonTitle: BRLocalizedString(@"Enable", @"Enable Service Button Title")
                        action: @selector(_enableAFP:)
                        target: self];
    }

    [result doLayout];

    return ( [result autorelease] );
}

- (BRLayerController *) _showAbout
{
    // 'About' file path
    NSString * path = [self _pathForBundleResource: @"About" ofType: @"txt"];
    if ( path == nil )
        return ( nil );

    BRDocumentController * result = [[BRDocumentController alloc] initWithScene: [self scene]];

    // by default uses Unicode (UTF-16), which is what we used when
    // creating the file
    [result setDocumentPath: path];

    [result setHeaderTitle: BRLocalizedString(@"About ATVLoader", @"'About' document header")];
    [result setHeaderIcon: [self listIcon]
         horizontalOffset: [self listIconHorizontalOffset]
            kerningFactor: [self listIconKerningFactor]];

    [result doLayout];

    return ( [result autorelease] );
}

- (BRLayerController *) _quitBackRow
{
    [[BRAppManager sharedApplication] terminate];
    return ( nil );
}

- (void) _enableSSH: (id) sender
{
#if REALLY_CHANGE_THINGS
    BOOL done = YES;

    NSError * error = nil;
    if ( [ATVSetupHelper isSSHInstalled] == NO )
        done = [[ATVSetupHelper sharedInstance] installSSHDaemon: &error];

    if ( done )
        done = [[ATVSetupHelper sharedInstance] enableSSHService: YES error: &error];

    if ( done )
    {
        [[self stack] popController];
    }
    else
    {
        id obj;

        if ( error == nil )
        {
            obj = [BRAlertController alertOfType: 2
                                          titled: BRLocalizedString(@"SSH Enable Failed", @"Alert dialog title")
                                     primaryText: BRLocalizedString(@"SSHEnableFailedPrimary", @"Alert dialog primary string")
                                   secondaryText: BRLocalizedString(@"SSHEnableFailedSecondary", @"Alert dialog secondary string")
                                       withScene: [self scene]];
        }
        else
        {
            obj = [BRAlertController alertForError: error withScene: [self scene]];
        }

        [[self stack] swapController: obj];
    }
#else
    // for now, we just set the flag in the preferences
    [[RUIPreferenceManager sharedPreferences] setBool: YES
                                               forKey: @"AwkwardSSHEnabled"
                                            forDomain: @"org.awkwardtv.servers"
                                                 sync: YES];
    [[self stack] popController];
#endif
}

- (void) _disableSSH: (id) sender
{
#if REALLY_CHANGE_THINGS
    NSError * error = nil;
    if ( [[ATVSetupHelper sharedInstance] enableSSHService: NO error: &error] )
    {
        [[self stack] popController];
    }
    else
    {
        id obj;

        if ( error == nil )
        {
            obj = [BRAlertController alertOfType: 2
                                          titled: BRLocalizedString(@"SSH Disable Failed", @"Alert dialog title")
                                     primaryText: BRLocalizedString(@"SSHDisableFailedPrimary", @"Alert dialog primary string")
                                   secondaryText: BRLocalizedString(@"SSHDisableFailedSecondary", @"Alert dialog secondary string")
                                       withScene: [self scene]];
        }
        else
        {
            obj = [BRAlertController alertForError: error withScene: [self scene]];
        }

        [[self stack] swapController: obj];
    }
#else
    [[RUIPreferenceManager sharedPreferences] setBool: NO
                                               forKey: @"AwkwardSSHEnabled"
                                            forDomain: @"org.awkwardtv.servers"
                                                 sync: YES];
    [[self stack] popController];
#endif
}

- (void) _enableAFP: (id) sender
{
#if REALLY_CHANGE_THINGS
    NSError * error = nil;
    if ( [[ATVSetupHelper sharedInstance] enableAFPService: YES error: &error] )
    {
        [[self stack] popController];
    }
    else
    {
        id obj;

        if ( error == nil )
        {
            obj = [BRAlertController alertOfType: 2
                                          titled: BRLocalizedString(@"AFP Enable Failed", @"Alert dialog title")
                                     primaryText: BRLocalizedString(@"AFPEnableFailedPrimary", @"Alert dialog primary string")
                                   secondaryText: BRLocalizedString(@"AFPEnableFailedSecondary", @"Alert dialog secondary string")
                                       withScene: [self scene]];
        }
        else
        {
            obj = [BRAlertController alertForError: error withScene: [self scene]];
        }

        [[self stack] swapController: obj];
    }
#else
    [[RUIPreferenceManager sharedPreferences] setBool: YES
                                               forKey: @"AwkwardAFPEnabled"
                                            forDomain: @"org.awkwardtv.servers"
                                                 sync: YES];
    [[self stack] popController];
#endif
}

- (void) _disableAFP: (id) sender
{
#if REALLY_CHANGE_THINGS
    NSError * error = nil;
    if ( [[ATVSetupHelper sharedInstance] enableAFPService: NO error: &error] )
    {
        [[self stack] popController];
    }
    else
    {
        id obj;

        if ( error == nil )
        {
            obj = [BRAlertController alertOfType: 2
                                          titled: BRLocalizedString(@"AFP Disable Failed", @"Alert dialog title")
                                     primaryText: BRLocalizedString(@"AFPDisableFailedPrimary", @"Alert dialog primary string")
                                   secondaryText: BRLocalizedString(@"AFPDisableFailedSecondary", @"Alert dialog secondary string")
                                       withScene: [self scene]];
        }
        else
        {
            obj = [BRAlertController alertForError: error withScene: [self scene]];
        }

        [[self stack] swapController: obj];
    }
#else
    [[RUIPreferenceManager sharedPreferences] setBool: NO
                                               forKey: @"AwkwardAFPEnabled"
                                            forDomain: @"org.awkwardtv.servers"
                                                 sync: YES];
    [[self stack] popController];
#endif
}

- (BRLayerController *) _pluginChooserController
{
    if ( [[BRInternetAvailabilityMonitor sharedInstance] isInternetAvailable] == NO )
        return ( [BRInternetRequiredController layerControllerWithScene: [self scene]] );

    // for now let's just return an error alert controller
    /*
    return ( [BRAlertController alertOfType: 1
                                     titled: BRLocalizedString( @"UnimplementedFeature", @"" )
                                primaryText: BRLocalizedString( @"UnimplementedPrimary", @"" )
                              secondaryText: BRLocalizedString( @"UnimplementedSecondary", @"" )
                                  withScene: [self scene]] );
     */

    // start fetching the available plugin list
    if ( _asyncLoader != nil )
    {
        ATVErrorLog( @"Plugin browser already selected !" );
        return ( nil );
    }

    // load the plugin list
    if ( [[RUIPreferenceManager sharedPreferences] boolForKey: @"ViewUnreleasedPlugins"
                                                    forDomain: @"org.awkwardtv.appliance.loader"
                                     withValueForMissingPrefs: NO] )
    {
        _asyncLoader = [ATVURLDataRetriever fetchDataFromURL:
            [NSURL URLWithString: @"http://plugins.awkwardtv.org/xml/?notpublic=1"]
                                                 forDelegate: self];
    }
    else
    {
        _asyncLoader = [ATVURLDataRetriever fetchDataFromURL:
            [NSURL URLWithString: @"http://plugins.awkwardtv.org/xml/"]
                                                 forDelegate: self];
    }

    if ( _asyncLoader == nil )
        return ( nil );

    [_asyncLoader retain];

    // return a 'waiting' message
    NSString * title = [BRLocalizedStringManager
                        backRowLocalizedStringForKey: @"WaitPleaseWait" inFile: nil];

    NSString * msg = BRLocalizedString( @"LoadingPluginList", @"Shown while waiting for plugin list to download" );

    id controller = [[BRTextWithSpinnerController alloc]
                     initWithScene: [self scene]
                             title: title
                              text: msg
                          showBack: NO
                isNetworkDependent: YES];

    [controller autorelease];
    [controller showProgress: YES];

    return ( controller );
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
    NSArray * list = [ATVPluginListXMLParser pluginListFromXMLData: data error: &error];
    id controller = nil;

    if ( (error != nil) || (list == nil) )
    {
        // setup an error dialog controller
        controller = [BRAlertController alertForError: error withScene: [self scene]];
    }
    else
    {
        // setup our plugin list controller
        controller = [[ATVPluginBrowserController alloc] initWithPlugins: list
                                                                   scene: [self scene]];
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

@end
