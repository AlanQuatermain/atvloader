//
//  ATVDownloadController.m
//  AwkwardTV
//
//  Created by Alan Quatermain on 11/04/07.
//  Copyright 2007 AwkwardTV. All rights reserved.
//

#import "ATVDownloadController.h"
#import "BackRowUtils.h"
#import "ATVSetupHelper.h"
#import "ATVProgressControl.h"
#import "ATVLogger.h"
#import "ATVGZipper.h"
//#import "unzip.h"
#import <BackRow/BackRow.h>
#import <limits.h>

@interface ATVDownloadController (Private)

+ (NSString *) _downloadCachePath;
+ (NSString *) _downloadPathForURLString: (NSString *) urlstr;
- (NSString *) _titleForDownloadType;
- (NSString *) _installTitleForType;
- (BOOL) _beginDownload;
- (NSURLDownload *) _resumedDownloadForPath: (NSString *) path;
- (BOOL) _resumeDownload;
- (void) _storeResumeData;
- (void) _installItem;
- (BOOL) _decompressFileAtPath: (NSString *) path error: (NSError **) error;
- (NSString *) _locateInstallableFileWithStartingPath: (NSString *) path;

@end

@interface ATVDownloadController (ATVURLDownloadDelegate)

- (void) download: (NSURLDownload *) download
   decideDestinationWithSuggestedFilename: (NSString *) filename;
- (void) download: (NSURLDownload *) download didFailWithError: (NSError *) error;
- (void) download: (NSURLDownload *) download didReceiveDataOfLength: (unsigned) length;
- (void) download: (NSURLDownload *) download didReceiveResponse: (NSURLResponse *) response;
- (BOOL) download: (NSURLDownload *) download
   shouldDecodeSourceDataOfMIMEType: (NSString *) encodingType;
- (void) download: (NSURLDownload *) download
   willResumeWithResponse: (NSURLResponse *) response
         fromByte: (long long) startingByte;
- (void) downloadDidFinish: (NSURLDownload *) download;

@end

@implementation ATVDownloadController

+ (void) clearAllDownloadCaches
{
    [[NSFileManager defaultManager] removeFileAtPath: [self _downloadCachePath]
                                             handler: nil];
}

- (id) initWithType: (ATVDownloadType) type
       downloadInfo: (NSDictionary *) dict
              scene: (BRRenderScene *) scene
           delegate: (id) obj
{
    if ( [super initWithScene: scene] == nil )
        return ( nil );

    if ( (dict == nil) || (obj == nil) )
    {
        [self autorelease];
        return ( nil );
    }

    _downloadInfo = [dict retain];
    _delegate = [obj retain];
    _downloader = nil;
    _outputPath = nil;
    _type = type;

    _header = [[BRHeaderControl alloc] initWithScene: scene];
    _sourceText = [[BRTextControl alloc] initWithScene: scene];
    _progressBar = [[ATVProgressControl alloc] initWithScene: scene];

    NSRect masterFrame = [[self masterLayer] frame];
    NSRect frame = masterFrame;

    // header goes in a very specific place
    frame.origin.y = frame.size.height * 0.82f;
    frame.size.height = [[BRThemeInfo sharedTheme] listIconHeight];
    [_header setFrame: frame];

    // progress bar does, too (one-eight of the way up from the bottom)
    frame.size.width  = (masterFrame.size.width * 0.45f);
    frame.size.height = ceilf(frame.size.width * 0.068f);
    frame.origin.x = (masterFrame.size.width - frame.size.width) * 0.5f;
    frame.origin.y = (masterFrame.origin.y + (masterFrame.size.height * (1.0f / 8.0f)));
    [_progressBar setFrame: frame];

    [self setTitle: [self _titleForDownloadType]];
    [self setSourceText: [dict objectForKey: @"url"]];  // this lays itself out
    [_progressBar setCurrentValue: [_progressBar minValue]];

    [self addControl: _header];
    [self addControl: _sourceText];
    [self addControl: _progressBar];

    return ( self );
}

- (void) dealloc
{
    [self cancelDownload];

    [_downloader release];
    [_downloadInfo release];
    [_delegate release];
    [_outputPath release];
    [_header release];
    [_sourceText release];
    [_progressBar release];

    [super dealloc];
}

- (void) cancelDownload
{
    if ( _downloader != nil )
    {
        [_downloader cancel];
        [self _storeResumeData];
    }
}

- (void) deleteDownloadCache
{
    if ( _outputPath == nil )
        return;

    [[NSFileManager defaultManager] removeFileAtPath:
        [_outputPath stringByDeletingLastPathComponent]
                                             handler: nil];
}

- (void) wasPushed
{
    if ( [self _beginDownload] == NO )
    {
        [_header setTitle: @"Download Failed"];
        [_progressBar setPercentage: 0.0f];

        [[self scene] renderScene];
    }

    [super wasPushed];
}

- (void) willBePopped
{
    [self cancelDownload];

    if ( _quitOnPop == YES )
        [[BRAppManager sharedApplication] terminate];

    [super willBePopped];
}

- (BOOL) isNetworkDependent
{
    return ( YES );
}

- (void) setTitle: (NSString *) title
{
    [_header setTitle: title];
}

- (NSString *) title
{
    return ( [_header title] );
}

- (void) setSourceText: (NSString *) srcText
{
    [_sourceText setTextAttributes: [[BRThemeInfo sharedTheme] paragraphTextAttributes]];
    [_sourceText setText: srcText];

    // layout this item
    NSRect masterFrame = [[self masterLayer] frame];

    [_sourceText setMaximumSize: NSMakeSize(masterFrame.size.width * 0.66f,
                                            masterFrame.size.height)];

    NSSize txtSize = [_sourceText renderedSize];

    NSRect frame;
    frame.origin.x = (masterFrame.size.width - txtSize.width) * 0.5f;
    frame.origin.y = (masterFrame.size.height * 0.75f) - txtSize.height;
    frame.size = txtSize;
    [_sourceText setFrame: frame];
}

- (NSString *) sourceText
{
    return ( [_sourceText text] );
}

- (float) percentDownloaded
{
    return ( [_progressBar percentage] );
}

@end

@implementation ATVDownloadController (Private)

+ (NSString *) _downloadCachePath
{
    static NSString * __cachePath = nil;

    if ( __cachePath == nil )
    {
        NSArray * searchPath = NSSearchPathForDirectoriesInDomains( NSCachesDirectory,
            NSUserDomainMask, YES );

        if ( (searchPath != nil) && ([searchPath count] > 0) )
            __cachePath = [searchPath objectAtIndex: 0];
        else
            __cachePath = NSTemporaryDirectory( );

        __cachePath = [[__cachePath stringByAppendingPathComponent: @"ATVDownloads"] retain];

        // ensure that this folder exists
        [[NSFileManager defaultManager] createDirectoryAtPath: __cachePath
                                                   attributes: nil];
    }

    return ( __cachePath );
}

+ (NSString *) _downloadPathForURLString: (NSString *) urlstr
{
    NSString * cache = [self _downloadCachePath];
    NSString * name = [urlstr lastPathComponent];

    NSRange range = [name rangeOfString: @"?"];
    if ( range.location != NSNotFound )
        name = [name substringToIndex: range.location];

    NSString * folder = [[name stringByDeletingPathExtension]
                         stringByAppendingPathExtension: @"download"];

    return ( [NSString pathWithComponents: [NSArray arrayWithObjects: cache,
                                            folder, name, nil]] );
}

- (NSString *) _titleForDownloadType
{
    NSString * result = BRLocalizedString(@"Downloading...", @"Default download page title");

    switch ( _type )
    {
        case kPluginDownloadType:
            result = BRLocalizedString(@"Downloading Plugin...", @"Plugin download page title");
            break;
        case kScreenSaverDownloadType:
            result = BRLocalizedString(@"Downloading Screen Saver...", @"Screen saver download page title");
            break;
        case kCodecDownloadType:
            result = BRLocalizedString(@"Downloading QuickTime Codec...", @"Codec download page title");
            break;

        default:
            break;
    }

    return ( result );
}

- (NSString *) _installTitleForType
{
    NSString * result = BRLocalizedString(@"Installing...", @"Default install page title");

    switch ( _type )
    {
        case kPluginDownloadType:
            result = BRLocalizedString(@"Installing Plugin...", @"Plugin install page title");
            break;
        case kScreenSaverDownloadType:
            result = BRLocalizedString(@"Installing Screen Saver...", @"Screen saver install page title");
            break;
        case kCodecDownloadType:
            result = BRLocalizedString(@"Installing QuickTime Codec...", @"Codec install page title");
            break;
        default:
            break;
    }

    return ( result );
}

- (BOOL) _beginDownload
{
    if ( _downloader != nil )
        return ( NO );

    NSString * urlstr = [_downloadInfo objectForKey: @"url"];
    if ( urlstr == nil )
        return ( NO );

    if ( _outputPath != nil )
    {
        [_outputPath release];
        _outputPath = nil;
    }

    _outputPath = [[ATVDownloadController _downloadPathForURLString: urlstr] retain];

    // see if we've got something that's resumable
    if ( [self _resumeDownload] == YES )
        return ( YES );

    // didn't work, delete it and start a fresh download
    [self deleteDownloadCache];

    NSURL * url = [NSURL URLWithString: urlstr];
    if ( url == nil )
        return ( NO );

    NSMutableURLRequest * req = [NSMutableURLRequest requestWithURL: url
                                                        cachePolicy: NSURLRequestReloadIgnoringCacheData
                                                    timeoutInterval: 20.0];
    [req setValue: @"Mozilla/5.0 (AppleTV; U; Intel Mac OS X; ATVLoader)"
     forHTTPHeaderField: @"User-Agent"];

    // create the downloader
    _downloader = [[NSURLDownload alloc] initWithRequest: req delegate: self];
    if ( _downloader == nil )
        return ( NO );

    [_downloader setDeletesFileUponFailure: NO];

    return ( YES );
}


- (NSURLDownload *) _resumedDownloadForPath: (NSString *) path
{
    NSString * resumeDataPath = [[_outputPath stringByDeletingLastPathComponent]
                                 stringByAppendingPathComponent: @"ResumeData"];
    if ( [[NSFileManager defaultManager] fileExistsAtPath: resumeDataPath] == NO )
        return ( nil );

    NSData * resumeData = [NSData dataWithContentsOfFile: resumeDataPath];
    if ( [resumeData length] == 0 )
        return ( nil );

    NSURLDownload * result = [[NSURLDownload alloc] initWithResumeData: resumeData
                                                              delegate: self
                                                                  path: path];
    if ( result == nil )
        return ( nil );      // couldn't resume this download

    [result setDeletesFileUponFailure: NO];
    return ( result );
}

- (BOOL) _resumeDownload
{
    if ( _outputPath == nil )
        return ( NO );

    NSString * resumeDataPath = [[_outputPath stringByDeletingLastPathComponent]
                                 stringByAppendingPathComponent: @"ResumeData"];
    if ( [[NSFileManager defaultManager] fileExistsAtPath: resumeDataPath] == NO )
        return ( NO );

    NSData * resumeData = [NSData dataWithContentsOfFile: resumeDataPath];
    if ( [resumeData length] == 0 )
        return ( NO );

    _downloader = [[NSURLDownload alloc] initWithResumeData: resumeData
                                                   delegate: self
                                                       path: _outputPath];
    if ( _downloader == nil )
        return ( NO );      // couldn't resume this download

    [_downloader setDeletesFileUponFailure: NO];
    return ( YES );
}

- (void) _storeResumeData
{
    NSData * data = [_downloader resumeData];
    if ( data != nil )
    {
            // store this in the .download folder
        NSString * path = [[_outputPath stringByDeletingLastPathComponent]
                           stringByAppendingPathComponent: @"ResumeData"];
        [data writeToFile: path atomically: YES];
    }
}

- (void) _installItem
{
    [_header setTitle: [self _installTitleForType]];
    [[self scene] renderScene];

    BOOL installed = NO;
    BOOL requiredReboot = NO;

    NSError * error = nil;
    NSString * path = nil;
    if ( [self _decompressFileAtPath: _outputPath error: &error] )
        path = [self _locateInstallableFileWithStartingPath:
            [_outputPath stringByDeletingLastPathComponent]];

    if ( path != nil )
    {
        ATVLog( @"Found installable file '%@'", path );

        switch ( _type )
        {
            case kPluginDownloadType:
            {
                if ( [[path lastPathComponent] isEqualToString: @"AwkwardTV.frappliance"] )
                    installed = [[ATVSetupHelper sharedInstance] updateSelf: path
                                 error: &error];
                else
                    installed = [[ATVSetupHelper sharedInstance] installApplianceAtPath: path
                                 error: &error];
                requiredReboot = YES;
                break;
            }

            case kScreenSaverDownloadType:
            {
                installed = [[ATVSetupHelper sharedInstance] installScreenSaverAtPath: path
                             error: &error];
                break;
            }

            case kCodecDownloadType:
            {
                installed = [[ATVSetupHelper sharedInstance] installQTCodecAtPath: path
                             error: &error];
                break;
            }

            default:
                break;
        }
    }

    // remove the downloaded files now
    [self deleteDownloadCache];

    if ( installed )
    {
        if ( requiredReboot == NO )
        {
            // we just pop ourselves, nothing left to do
            [[self stack] popController];
        }
        else
        {
            // load the localized 'please restart' information from its
            // file
            [_header setTitle: BRLocalizedString(@"Installation Complete", @"Page title when installation is complete")];

            NSBundle * bundle = [NSBundle bundleForClass: [self class]];
            path = [bundle pathForResource: @"RestartWarning" ofType: @"txt"];
            [self setSourceText: [NSString stringWithContentsOfFile: path]];

            [[self scene] renderScene];
            _quitOnPop = YES;
        }
    }
    else
    {
        // an error occurred !
        id controller;
        if ( error == nil )
        {
            controller = [BRAlertController alertOfType: 2
                                                 titled: BRLocalizedString(@"Installation Failed", @"Alert dialog title")
                                            primaryText: BRLocalizedString(@"An error occurred during installation",@"Alert dialog primary string")
                                          secondaryText: @""
                                              withScene: [self scene]];
        }
        else
        {
            controller = [BRAlertController alertForError: error withScene: [self scene]];
        }

        [[self stack] swapController: controller];
    }
}

- (BOOL) _decompressFileAtPath: (NSString *) path error: (NSError **) error
{
    if ( path == nil )
        return ( NO );

    NSString * ext = [path pathExtension];

    NSTask * task = [[NSTask alloc] init];
    NSArray * args = nil;
    NSString * launch = nil;

    ATVLog( @"Decompressing file '%@'", path );

    if ( ( [ext isEqualToString: @"tgz"] ) ||
         ( [ext isEqualToString: @"gz"] ) )
    {
        path = [ATVGZipper unzipFileAtPath: path error: error];
        if ( path == nil )
            return ( NO );

        ext = [path pathExtension];
    }

    if ( [ext isEqualToString: @"tar"] )
    {
        ATVDebugLog( @"Using tar xvfp" );
        launch = @"/usr/bin/tar";
        args = [NSArray arrayWithObjects: @"xvfp", path, nil];
    }
    else if ( [ext isEqualToString: @"zip"] )
    {
        ATVDebugLog( @"Using unzip" );
//        launch = @"/usr/bin/unzip";
        launch = [[NSBundle bundleForClass: [self class]] pathForResource: @"unzip"
                  ofType: nil];
        args = [NSArray arrayWithObjects: path, nil];
    }

    if ( launch == nil )
    {
        ATVErrorLog( @"Unknown archive type" );
        [task release];
        return ( NO );
    }

    [task setLaunchPath: launch];
    [task setArguments: args];
    [task setCurrentDirectoryPath: [path stringByDeletingLastPathComponent]];

    ATVDebugLog( @"Set current directory '%@'", [task currentDirectoryPath] );

    [task launch];
    [task waitUntilExit];

    int status = [task terminationStatus];
    [task release];

    ATVLog( @"Task terminated with status '%d'", status );

    if ( status != 0 )
    {
        ATVErrorLog( @"Task failed" );
        if ( error != nil )
        {
            NSString * reasonFormat = BRLocalizedString(@"Unzip/untar failed with error '%d'", @"Failure reason string");
            NSDictionary * userInfo = [NSDictionary dictionaryWithObjectsAndKeys:
                                       [NSString stringWithFormat: reasonFormat, status],
                                       NSLocalizedFailureReasonErrorKey, nil];

            *error = [NSError errorWithDomain: NSPOSIXErrorDomain
                                         code: status
                                     userInfo: userInfo];
        }

        return ( NO );
    }
/*
    NSString * root = [path stringByDeletingLastPathComponent];

    // look for new items, since we know what should be there already
    NSArray * contents = [[NSFileManager defaultManager] directoryContentsAtPath: root];

    if ( contents == nil )
        return ( nil );

    NSString * result = nil;
    unsigned i, count = [contents count];
    for ( i = 0; i < count; i++ )
    {
        NSString * str = [contents objectAtIndex: i];

        if ( [str isEqualToString: @"ResumeData"] )
            continue;

        if ( [str isEqualToString: [path lastPathComponent]] )
            continue;

        // grrr, skip the resources directory included in zipped files
        if ( [str isEqualToString: @"__MACOSX"] )
            continue;

        // otherwise, this must be it
        ATVLog( @"Found decompressed item '%@'", str );
        result = [root stringByAppendingPathComponent: str];
        break;
    }
 */
    return ( YES );
}

- (NSString *) _locateInstallableFileWithStartingPath: (NSString *) path
{
    NSArray * subtree = nil;
    BOOL isDir = NO;
    if ( [[NSFileManager defaultManager] fileExistsAtPath: path isDirectory: &isDir] &&
         (isDir == YES) )
    {
        subtree = [[NSFileManager defaultManager] subpathsAtPath: path];
    }

    if ( subtree == nil )
        return ( nil );

    NSString * ext = nil;
    switch ( _type )
    {
        case kPluginDownloadType:
            ext = @"frappliance";
            break;
        case kScreenSaverDownloadType:
            ext = @"frss";
            break;
        case kCodecDownloadType:
            ext = @"component";
            break;

        default:
            break;
    }

    if ( ext == nil )
        return ( nil );

    NSArray * matches = [subtree pathsMatchingExtensions: [NSArray arrayWithObject: ext]];
    if ( (matches == nil) || ([matches count] == 0) )
        return ( nil );

    // find an item which doesn't include __MACOSX (will be
    // unnecesssary once I've got my own Unarchiver written)
    NSEnumerator * enumerator = [matches objectEnumerator];
    NSString * foundPath;
    while ( (foundPath = [enumerator nextObject]) != nil )
    {
        if ( [foundPath hasPrefix: @"._"] )
            continue;

        NSRange range = [foundPath rangeOfString: @"__MACOSX"];
        if ( range.location == NSNotFound )
            break;
    }

    if ( foundPath == nil )
        return ( nil );

    return ( [path stringByAppendingPathComponent: foundPath] );
}

@end

@implementation ATVDownloadController (ATVURLDownloadDelegate)

- (void) download: (NSURLDownload *) download
   decideDestinationWithSuggestedFilename: (NSString *) filename
{
    // in case of redirects from something like /dl.php?q=atvloader to
    // the actual location, we'll create a new item here and re-search
    // for resumable downloads
    NSString * newPath = [[ATVDownloadController _downloadPathForURLString: filename] retain];
    ATVDebugLog( @"Downloader suggests filename '%@'", filename );

    // delete current .download folder, etc.
    [self deleteDownloadCache];

    [_outputPath release];
    _outputPath = [newPath retain];

    NSURLDownload * resumed = [self _resumedDownloadForPath: newPath];
    if ( resumed != nil )
    {
        [_downloader cancel];
        [_downloader autorelease];
        _downloader = resumed;
        return;
    }

    // ensure the .download folder exists
    [[NSFileManager defaultManager] createDirectoryAtPath: [_outputPath stringByDeletingLastPathComponent]
                                               attributes: nil];

    ATVLog( @"Downloading file to '%@'", _outputPath );

    [download setDestination: _outputPath allowOverwrite: YES];
}

- (void) download: (NSURLDownload *) download didFailWithError: (NSError *) error
{
    [self _storeResumeData];

    ATVErrorLog( @"Download encountered error '%d' (%@)", [error code],
                 [error localizedDescription] );

    // show an alert for the returned error (hopefully it has nice
    // localized reasons & such...)
    BRAlertController * obj = [BRAlertController alertForError: error
                                                     withScene: [self scene]];
    [[self stack] swapController: obj];
}

- (void) download: (NSURLDownload *) download didReceiveDataOfLength: (unsigned) length
{
    _gotLength += (long long) length;
    float percentage = 0.0f;

    if ( _totalLength == 0 )
    {
        // bump up the max value a bit
        percentage = [_progressBar percentage];
        if ( percentage >= 95.0f )
            [_progressBar setMaxValue: [_progressBar maxValue] + (float) (length << 3)];
    }

    [_progressBar setCurrentValue: _gotLength];
}

- (void) download: (NSURLDownload *) download didReceiveResponse: (NSURLResponse *) response
{
    _totalLength = 0;
    _gotLength = 0;

    ATVDebugLog( @"Received NSURLResponse:\n%@", response );
    ATVDebugLog( @"Response filename is %@", [response suggestedFilename] );
/*
    NSString * newPath = [[ATVDownloadController _downloadPathForURLString:
        [response suggestedFilename]] retain];

    // delete current .download folder, etc.
    [self deleteDownloadCache];

    NSURLDownload * resumed = [self _resumedDownloadForPath: newPath];
    if ( resumed != nil )
    {
        [_outputPath release];
        _outputPath = [newPath retain];

        [_downloader cancel];
        [_downloader autorelease];
        _downloader = resumed;
        return;
    }

    // ensure the .download folder exists
    [[NSFileManager defaultManager] createDirectoryAtPath: [_outputPath stringByDeletingLastPathComponent]
                                               attributes: nil];

    ATVLog( @"Downloading file to '%@'", _outputPath );

    [download setDestination: _outputPath allowOverwrite: YES];
*/
    if ( [response expectedContentLength] != NSURLResponseUnknownLength )
    {
        _totalLength = [response expectedContentLength];
        [_progressBar setMaxValue: (float) _totalLength];
    }
    else
    {
        // an arbitrary number -- one megabyte
        [_progressBar setMaxValue: 1024.0f * 1024.0f];
    }
}

- (BOOL) download: (NSURLDownload *) download
   shouldDecodeSourceDataOfMIMEType: (NSString *) encodingType
{
    return ( NO );
}

- (void) download: (NSURLDownload *) download
   willResumeWithResponse: (NSURLResponse *) response
                 fromByte: (long long) startingByte
{
    _totalLength = 0;
    _gotLength = (long long) startingByte;

    if ( [response expectedContentLength] != NSURLResponseUnknownLength )
    {
        // the expected length here is remaining length, not total
        _totalLength = _gotLength + [response expectedContentLength];
        [_progressBar setMaxValue: (float) _totalLength];
    }
    else
    {
        // an arbitrary number
        [_progressBar setMaxValue: (float) (_gotLength << 1)];
    }

    // reset current value as appropriate
    [_progressBar setCurrentValue: (float) _gotLength];
}

- (void) downloadDidBegin: (NSURLDownload *) download
{
    _gotLength = 0;
}

- (void) downloadDidFinish: (NSURLDownload *) download
{
    // completed the download, now go & do stuff with it
    [_progressBar setPercentage: 100.0f];
    [self _installItem];
}

@end
