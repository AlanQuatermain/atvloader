//
//  ATVSetupHelper.m
//  AwkwardTV
//
//  Created by Alan Quatermain on 11/04/07.
//  Copyright 2007 AwkwardTV. All rights reserved.
//

#import "ATVSetupHelper.h"
#import "ATVLogger.h"
#import "SetupHelper.h"
#import "BackRowUtils.h"

#import <sysexits.h>
#import <sys/errno.h>
#import <sys/stat.h>

static ATVSetupHelper * __ATVSetupHelper_singleton = nil;

static NSError * BuildNSError( int code, NSString * domain,
                               NSString * reason, NSString * suggestion )
{
    ATVDebugLog( @"Creating NSError: %d %@ %@ %@", code, domain, reason, suggestion );
    NSDictionary * userInfo;
    if ( suggestion != nil )
        userInfo = [NSDictionary dictionaryWithObjectsAndKeys: reason,
                    NSLocalizedFailureReasonErrorKey, suggestion,
                    NSLocalizedRecoverySuggestionErrorKey, nil];
    else
        userInfo = [NSDictionary dictionaryWithObjectsAndKeys: reason,
                    NSLocalizedFailureReasonErrorKey, nil];

    return ( [NSError errorWithDomain: domain code: code userInfo: userInfo] );
}

static BOOL CopyFile( NSString * sourcePath, NSString * destPath, NSError ** error )
{
    NSString * finalDest = [destPath stringByAppendingPathComponent:
        [sourcePath lastPathComponent]];
    NSString * tmpDest = [finalDest stringByAppendingPathExtension: @"tmp"];

    // this essentially uses the same engine as the Finder
    OSStatus err = FSPathCopyObjectSync( [sourcePath fileSystemRepresentation],
                                         [destPath fileSystemRepresentation],
                                         (CFStringRef) [tmpDest lastPathComponent],
                                         NULL, kFSFileOperationOverwrite );
    if ( err != noErr )
    {
        ATVErrorLog( @"Failed to copy files, err = %ld", err );
        if ( error != NULL )
        {
            *error = BuildNSError( err, NSOSStatusErrorDomain,
                                   BRLocalizedStringFromTableInBundle(@"CopyNewFileFailed", @"Errors", [ATVSetupHelper sharedInstance], @"Failed to copy a file"),
                                   [NSString stringWithFormat: @"Error = %ld", err] );
        }
        return ( NO );
    }

    // copied to temporary destination, now move any existing item out
    // of the way
    if ( [[NSFileManager defaultManager] fileExistsAtPath: finalDest] )
    {
        // move it out of the way
        NSString * movePath = [[finalDest stringByDeletingPathExtension]
                               stringByAppendingPathExtension: @"deleteme"];

        err = FSPathMoveObjectSync( [finalDest fileSystemRepresentation],
                                    [destPath fileSystemRepresentation],
                                    (CFStringRef) [movePath lastPathComponent],
                                    NULL, kFSFileOperationOverwrite );
        if ( err != noErr )
        {
            ATVErrorLog( @"Unable to move-aside existing object, err = %ld", err );
            if ( error != NULL )
            {
                *error = BuildNSError( err, NSOSStatusErrorDomain,
                                       BRLocalizedStringFromTableInBundle(@"MoveExistingFileFailed", @"Errors", [ATVSetupHelper sharedInstance], @"Failed to move an existing file out of the way"),
                                       [NSString stringWithFormat: @"Error = %ld", err] );
            }

            // delete tmp file
            [[NSFileManager defaultManager] removeFileAtPath: tmpDest handler: nil];

            // return error status
            return ( NO );
        }
    }

    // move copied item into place
    err = FSPathMoveObjectSync( [tmpDest fileSystemRepresentation],
                                [destPath fileSystemRepresentation],
                                (CFStringRef) [sourcePath lastPathComponent],
                                NULL, kFSFileOperationDefaultOptions );
    if ( err != noErr )
    {
        ATVErrorLog( @"Unable to move in new object, err = %ld", err );
        if ( error != NULL )
        {
            *error = BuildNSError( err, NSOSStatusErrorDomain,
                                   BRLocalizedStringFromTableInBundle(@"MoveNewFileFailed", @"Errors", [ATVSetupHelper sharedInstance], @"Failed to move the new file into place"),
                                   [NSString stringWithFormat: @"Error = %ld", err] );
        }

        [[NSFileManager defaultManager] removeFileAtPath: tmpDest handler: nil];
        return ( NO );
    }

    return ( YES );
}

static BOOL ShouldSupplyNorootArg( NSString * path )
{
    BOOL result = NO;
    struct stat statBuf;

    // skanky test for Apple TV
    if ( [[NSFileManager defaultManager] fileExistsAtPath: @"/mnt/Scratch/Users/frontrow"] == NO )
    {
        if ( stat([path fileSystemRepresentation], &statBuf) != -1 )
        {
            // not setuid, or not setuid root, we use -noroot
            if ( (statBuf.st_mode & S_ISUID) != S_ISUID )
                result = YES;
            else if ( statBuf.st_uid != 0 )
                result = YES;
        }
    }

    return ( result );
}

@interface ATVSetupHelper (Private)

- (BOOL) _runHelperWithCommand: (ATVSetupHelperCommand *) cmd error: (NSError **) error;
- (NSString *) _pathForSSHDaemonBinary;
- (NSString *) _pathForSetupHelper;

@end

@implementation ATVSetupHelper

+ (id) singleton
{
    return ( __ATVSetupHelper_singleton );
}

+ (void) setSingleton: (id) obj
{
    __ATVSetupHelper_singleton = (ATVSetupHelper *) obj;
}

+ (BOOL) isSSHInstalled
{
    return ( [[NSFileManager defaultManager] fileExistsAtPath: @"/usr/sbin/sshd"] );
}

+ (BOOL) isSSHEnabled
{
    BOOL result = NO;

    if ( [self isSSHInstalled] == NO )
        return ( NO );

    NSDictionary * dict = [NSDictionary dictionaryWithContentsOfFile: @"/System/Library/LaunchDaemons/ssh.plist"];
    if ( dict != nil )
    {
        result = YES;
        NSNumber * num = (NSNumber *) [dict objectForKey: @"Disabled"];
        if ( num != nil )
            result = (![num boolValue]);
    }

    return ( result );
}

+ (BOOL) isAFPEnabled
{
    BOOL result = NO;

    NSString * str = [NSString stringWithContentsOfFile: @"/etc/hostconfig"];
    if ( str != nil )
    {
        NSRange range = [str rangeOfString: @"AFPSERVER=-YES-"];
        if ( range.location != NSNotFound )
            result = YES;
    }

    return ( result );
}

- (void) cleanUpReplacedItems
{
    ATVSetupHelperCommand cmd;
    cmd.cmdCode = kATVDeleteReplacedFiles;
    cmd.params.sourcePath[0] = '\0';

    (void) [self _runHelperWithCommand: &cmd error: nil];
}

- (BOOL) updateSelf: (NSString *) path error: (NSError **) error
{
    ATVSetupHelperCommand cmd;

    cmd.cmdCode = kATVUpdateSelf;
    strlcpy( cmd.params.sourcePath, [path UTF8String], PATH_MAX );

    return ( [self _runHelperWithCommand: &cmd error: error] );
}

- (BOOL) installApplianceAtPath: (NSString *) path error: (NSError **) error
{
    ATVSetupHelperCommand cmd;

    cmd.cmdCode = kATVInstallAppliance;
    strlcpy( cmd.params.sourcePath, [path UTF8String], PATH_MAX );

    return ( [self _runHelperWithCommand: &cmd error: error] );
}

- (BOOL) installScreenSaverAtPath: (NSString *) path error: (NSError **) error
{
    ATVSetupHelperCommand cmd;

    cmd.cmdCode = kATVInstallScreenSaver;
    strlcpy( cmd.params.sourcePath, [path UTF8String], PATH_MAX );

    return ( [self _runHelperWithCommand: &cmd error: error] );
}

- (BOOL) installQTCodecAtPath: (NSString *) path error: (NSError **) error
{
    // we'll copy into the user's home folder
    NSArray * list = NSSearchPathForDirectoriesInDomains( NSLibraryDirectory,
        NSUserDomainMask, YES );
    if ( (list == nil) || ([list count] == 0) )
    {
        // use the global folder instead
        ATVSetupHelperCommand cmd;

        cmd.cmdCode = kATVInstallQTCodec;
        strlcpy( cmd.params.sourcePath, [path UTF8String], PATH_MAX );

        return ( [self _runHelperWithCommand: &cmd error: error] );
    }

    NSString * dest = [[list objectAtIndex: 0] stringByAppendingPathComponent: @"QuickTime"];

    // ensure folder exists
    [[NSFileManager defaultManager] createDirectoryAtPath: dest
                                               attributes: nil];

    // copy in the file
    return ( CopyFile(path, dest, error) );
}

- (BOOL) installSSHDaemon: (NSError **) error
{
    NSString * path = [self _pathForSSHDaemonBinary];
    if ( path == nil )
    {
        ATVErrorLog( @"Couldn't find sshd within my bundle..." );
        if ( error != NULL )
        {
            *error = BuildNSError( ENOENT, NSPOSIXErrorDomain,
                                   BRLocalizedStringFromTable(@"NoSSHDBinaryToInstall", @"Errors", @"No sshd binary found to install"),
                                   nil );
        }
        return ( NO );
    }

    ATVSetupHelperCommand cmd;

    cmd.cmdCode = kATVSecureShellInstall;
    strlcpy( cmd.params.sourcePath, [path UTF8String], PATH_MAX );

    return ( [self _runHelperWithCommand: &cmd error: error] );
}

- (BOOL) enableSSHService: (BOOL) enable error: (NSError **) error
{
    ATVSetupHelperCommand cmd;

    cmd.cmdCode = kATVSecureShellChange;
    cmd.params.enable = enable;

    return ( [self _runHelperWithCommand: &cmd error: error] );
}

- (BOOL) enableAFPService: (BOOL) enable error: (NSError **) error
{
    ATVSetupHelperCommand cmd;

    cmd.cmdCode = kATVAppleShareChange;
    cmd.params.enable = enable;

    return ( [self _runHelperWithCommand: &cmd error: error] );
}

@end

@implementation ATVSetupHelper (Private)

- (BOOL) _runHelperWithCommand: (ATVSetupHelperCommand *) cmd error: (NSError **) error
{
    NSString * helperPath = [self _pathForSetupHelper];
    if ( helperPath == nil )
    {
        ATVErrorLog( @"Couldn't get setup helper tool path" );
        return ( NO );
    }

    NSTask * task = [[NSTask alloc] init];

    [task setLaunchPath: helperPath];
    [task setStandardInput: [NSPipe pipe]];
    [task setStandardOutput: [NSPipe pipe]];
    [task setStandardError: [NSFileHandle fileHandleWithNullDevice]];

    NSFileHandle * input = [[task standardInput] fileHandleForWriting];
    NSFileHandle * output = [[task standardOutput] fileHandleForReading];

    NSMutableArray * args = [NSMutableArray arrayWithObjects: @"-approot",
                             [[NSBundle mainBundle] bundlePath], nil];

    if ( ShouldSupplyNorootArg([args objectAtIndex: 1]) )
        [args addObject: @"-noroot"];

    [task setArguments: args];

    [task launch];

    // write the data through the pipe
    [input writeData: [NSData dataWithBytes: cmd length: sizeof(ATVSetupHelperCommand)]];
    [input closeFile];

    // wait for the task to exit, then get the result
    [task waitUntilExit];
    int status = [task terminationStatus];

    if ( status != 0 )
        ATVErrorLog( @"SetupHelper returned bad status %d (%#x)",
                     status, status );

    switch ( status )
    {
        case EX_SOFTWARE:
        {
            // grab data from the output pipe
            NSData * data = [output readDataToEndOfFile];
            id obj = [NSUnarchiver unarchiveObjectWithData: data];

            if ( (obj != nil) && ([obj isKindOfClass: [NSError class]]) )
            {
                // log it
                ATVErrorLog( @"SetupHelper returned NSError: %@", obj );

                // return it
                if ( error != NULL )
                    *error = obj;
            }
            else
            {
                if ( obj == nil )
                    ATVErrorLog( @"Got nil error object from SetupHelper" );
                else
                    ATVErrorLog( @"Got unexpected object '%@' from SetupHelper", obj );
            }

            break;
        }

        case EX_NOPERM:
        {
            ATVErrorLog( @"SetupHelper is not running as root" );
            if ( error != NULL )
                *error = BuildNSError( EPERM, NSPOSIXErrorDomain,
                                       BRLocalizedStringFromTable(@"SetupHelperNotRoot", @"Errors", @"SetupHelper is not running as the root user"),
                                       BRLocalizedStringFromTable(@"ReinstallPatchstick", @"Errors", @"Re-run Patchstick process to reinstall plugin") );
            break;
        }

        case EX_NOINPUT:
        {
            ATVErrorLog( @"SetupHelper could not read command" );
            if ( error != NULL )
                *error = BuildNSError( EIO, NSPOSIXErrorDomain,
                                       BRLocalizedStringFromTable(@"SetupHelperNoCommand", @"Errors", @"Setup Helper couldn't read command"),
                                       BRLocalizedStringFromTable(@"TryAgain", @"Errors", @"Try running the command again") );
            break;
        }

        default:
            break;
    }

    [task release];

    return ( status == 0 );
}

- (NSString *) _pathForSSHDaemonBinary
{
    NSBundle * bundle = [NSBundle bundleForClass: [self class]];
    if ( bundle == nil )
        return ( nil );

    return ( [bundle pathForResource: @"sshd" ofType: nil] );
}

- (NSString *) _pathForSetupHelper
{
    static NSString * __path;

    if ( __path == nil )
    {
        NSBundle * bundle = [NSBundle bundleForClass: [self class]];
        if ( bundle != nil )
            __path = [[bundle pathForResource: @"SetupHelper" ofType: nil] retain];
    }

    return ( __path );
}

@end
