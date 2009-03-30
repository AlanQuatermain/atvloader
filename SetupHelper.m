/*
 *  SetupHelper.m
 *  AwkwardTV
 *
 *  Created by Alan Quatermain on 11/04/07.
 *  Copyright 2007 AwkwardTV. All rights reserved.
 *
 */

#import "SetupHelper.h"
#import <sys/mount.h>
#import <signal.h>
#import <syslog.h>
#import <sysexits.h>
#import <stdio.h>
#import <unistd.h>

#import <CoreServices/CoreServices.h>
#import <Foundation/Foundation.h>

#import "ATVLogger.h"

#define UPGRADE_CHECK   0

#define LocalizedError(key, comment) \
    [ATVLoaderBundle( ) localizedStringForKey:(key) value:@"" table:@"Errors"]

static NSString * const kBackRowAppPath = @"/System/Library/CoreServices/BackRow.app";
static NSString * const kFinderAppPath = @"/System/Library/CoreServices/Finder.app";

static NSString * const kSSHLaunchPath = @"/System/Library/LaunchDaemons/ssh.plist";

static NSString * gContainerAppPath = nil;

static NSString * BackRowFinderPathForResource( NSString * name, NSString * type )
{
    NSString * appPath = gContainerAppPath;
    if ( appPath == nil )
    {
        appPath = kFinderAppPath;
        if ( [[NSFileManager defaultManager] fileExistsAtPath: kBackRowAppPath] )
            appPath = kBackRowAppPath;
    }

    NSString * result = [NSBundle pathForResource: name
                                           ofType: type
                                      inDirectory: appPath];

    if ( result == nil )
    {
        // try a non-Resources path, just inside Contents
        NSString * testPath = [appPath stringByAppendingPathComponent: @"Contents"];
        testPath = [testPath stringByAppendingPathComponent: name];
        if ( (type != nil) && ([type length] != 0) )
            testPath = [testPath stringByAppendingPathExtension: type];

        if ( [[NSFileManager defaultManager] fileExistsAtPath: testPath] )
            result = testPath;
    }

    return ( result );
}

static NSBundle * ATVLoaderBundle( void )
{
    return ( [NSBundle bundleWithPath: [NSString pathWithComponents:
        [NSArray arrayWithObjects: kFinderAppPath, @"Contents", @"PlugIns",
         @"AwkwardTV.frappliance", nil]]] );
}

static void PostNSError( int code, NSString * domain,
                         NSString * reason, NSString * suggestion )
{
    NSDictionary * userInfo;
    if ( suggestion != nil )
        userInfo = [NSDictionary dictionaryWithObjectsAndKeys: reason,
                    NSLocalizedFailureReasonErrorKey, suggestion,
                    NSLocalizedRecoverySuggestionErrorKey, nil];
    else
        userInfo = [NSDictionary dictionaryWithObjectsAndKeys: reason,
                    NSLocalizedFailureReasonErrorKey, nil];

    NSError * err = [NSError errorWithDomain: domain code: code userInfo: userInfo];
    [[NSFileHandle fileHandleWithStandardOutput] writeData:
        [NSArchiver archivedDataWithRootObject: err]];
}

static NSString * UserFolderForQTCodecs( void )
{
    NSString * result = NSHomeDirectoryForUser( @"frontrow" );
    return ( [result stringByAppendingPathComponent: [NSString pathWithComponents:
        [NSArray arrayWithObjects: @"Library", @"QuickTime", nil]]] );
}

#if UPGRADE_CHECK
static BOOL IsUpgradeFromExistingVersion( NSString * sourcePath, NSString * destPath )
{
    BOOL result = YES;

    @try
    {
        destPath = [destPath stringByAppendingPathComponent: [sourcePath lastPathComponent]];
        NSDictionary * src = [[NSBundle bundleWithPath: sourcePath] infoDictionary];
        NSDictionary * dst = [[NSBundle bundleWithPath: destPath] infoDictionary];

        if ( dst != nil )
        {
            NSString * srcVersion = [src objectForKey: @"CFBundleVersion"];
            NSString * dstVersion = [dst objectForKey: @"CFBundleVersion"];

            if ( [srcVersion compare: dstVersion options: NSNumericSearch] != NSOrderedAscending )
                result = NO;
        }
    }
    @catch(NSException * e)
    {
    }

    return ( result );
}
#else
#define IsUpgradeFromExistingVersion(a, b) YES
#endif
/*
static BOOL CopyFile( NSString * sourcePath, NSString * destPath )
{
    NSFileManager * fm = [NSFileManager defaultManager];

    if ( [fm fileExistsAtPath: sourcePath] == NO )
    {
        syslog( LOG_ERR, "No file at source path '%s'", [sourcePath UTF8String] );
        return ( NO );
    }

    NSString * newPath = [destPath stringByAppendingPathComponent:
        [sourcePath lastPathComponent]];

    if ( [fm copyPath: sourcePath toPath: newPath handler: nil] == NO )
    {
        syslog( LOG_ERR, "Copy '%s' to '%s' failed", [sourcePath UTF8String],
                [destPath UTF8String] );
        return ( NO );
    }

    return ( YES );
}
*/
static BOOL CopyFile( NSString * sourcePath, NSString * destPath, NSString ** targetPath )
{
    char * target = NULL;

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
        PostNSError( (int) err, NSOSStatusErrorDomain,
                     LocalizedError(@"CopyNewFileFailed", @"Failed to copy a file"),
                     [NSString stringWithFormat: @"Error = %ld", err] );
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
            PostNSError( err, NSOSStatusErrorDomain,
                         LocalizedError(@"MoveExistingFileFailed", @"Failed to move an existing file out of the way"),
                         [NSString stringWithFormat: @"Error = %ld", err] );

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
                                (targetPath == nil ? NULL : &target),
                                kFSFileOperationDefaultOptions );
    if ( err != noErr )
    {
        ATVErrorLog( @"Unable to move in new object, err = %ld", err );
        PostNSError( err, NSOSStatusErrorDomain,
                     LocalizedError(@"MoveNewFileFailed", @"Failed to move the new file into place"),
                     [NSString stringWithFormat: @"Error = %ld", err] );
        [[NSFileManager defaultManager] removeFileAtPath: tmpDest handler: nil];
        return ( NO );
    }

    if ( targetPath != nil )
    {
        *targetPath = [NSString stringWithUTF8String: target];
        free( target );
    }

    return ( YES );
}

static BOOL UpdateSelf( NSString * sourcePath )
{
    NSString * destPath = BackRowFinderPathForResource( @"PlugIns", nil );
    if ( destPath == nil )
    {
        ATVErrorLog( @"Couldn't get PlugIns destination path" );
        PostNSError( fnfErr, NSOSStatusErrorDomain,
                     LocalizedError(@"PlugInsFolderNotFound", @"Unable to locate the PlugIns folder"),
                     nil );
        return ( NO );
    }

    if ( IsUpgradeFromExistingVersion(sourcePath, destPath) == NO )
    {
        ATVErrorLog( @"Not an upgrade, cancelling installation" );
        PostNSError( EEXIST, NSPOSIXErrorDomain,
                     LocalizedError(@"ThisVersionAlreadyInstalled", @"Not installing because the same version is already installed"),
                     nil );
        return ( NO );
    }

    NSString * target = nil;
    if ( CopyFile(sourcePath, destPath, &target) == NO )
        return ( NO );

    // ensure that the helper in the new version is setuid properly
    NSBundle * b = [NSBundle bundleWithPath: target];
    NSString * helper = [b pathForResource: @"SetupHelper" ofType: nil];
    if ( helper == nil )
    {
        ATVErrorLog( @"Unable to locate new version of SetupHelper !" );
        return ( YES );     // well, it's there....
    }

    // ensure it's owned by the correct user
    chown( [helper fileSystemRepresentation], 0, 0 );

    // ensure it's setuid root on execution
    chmod( [helper fileSystemRepresentation], 04555 );

    return ( YES );
}

static BOOL InstallAppliancePlugin( NSString * sourcePath )
{
    NSString * destPath = BackRowFinderPathForResource( @"PlugIns", nil );
    if ( destPath == nil )
    {
        ATVErrorLog( @"Couldn't get PlugIns destination path" );
        PostNSError( fnfErr, NSOSStatusErrorDomain,
                     LocalizedError(@"PlugInsFolderNotFound", @"Unable to locate the PlugIns folder"),
                     nil );
        return ( NO );
    }

    if ( IsUpgradeFromExistingVersion(sourcePath, destPath) == NO )
    {
        ATVErrorLog( @"Not an upgrade, cancelling installation" );
        PostNSError( EEXIST, NSPOSIXErrorDomain,
                     LocalizedError(@"ThisVersionAlreadyInstalled", @"Not installing because the same version is already installed"),
                     nil );
        return ( NO );
    }

    return ( CopyFile(sourcePath, destPath, NULL) );
}

static BOOL InstallScreenSaverPlugin( NSString * sourcePath )
{
    NSString * destPath = BackRowFinderPathForResource( @"ScreenSavers", nil );
    if ( destPath == nil )
    {
        ATVErrorLog( @"Couldn't get ScreenSavers destination path" );
        PostNSError( fnfErr, NSOSStatusErrorDomain,
                     LocalizedError(@"ScreenSaversFolderNotFound", @"Unable to locate the Screen Savers folder"),
                     nil );
        return ( NO );
    }

    if ( IsUpgradeFromExistingVersion(sourcePath, destPath) == NO )
    {
        PostNSError( EEXIST, NSPOSIXErrorDomain,
                     LocalizedError(@"ThisVersionAlreadyInstalled", @"Not installing because the same version is already installed"),
                     nil );
        return ( NO );
    }

    return ( CopyFile(sourcePath, destPath, NULL) );
}

static BOOL InstallQuickTimeCodec( NSString * sourcePath )
{
/*
    NSString * destPath = UserFolderForQTCodecs( );
    if ( destPath == nil )
    {
        syslog( LOG_ERR, "Couldn't get codec destination path" );
        return ( NO );
    }

    return ( CopyFile(sourcePath, destPath, NULL) );
 */
    return ( CopyFile(sourcePath, @"/Library/QuickTime", NULL) );
}

static BOOL InstallSecureShellDaemon( NSString * sourcePath )
{
    if ( CopyFile(sourcePath, @"/usr/sbin", NULL) == NO )
        return ( NO );

    // create /etc/sshd_config
    [[NSFileManager defaultManager] createFileAtPath: @"/etc/sshd_config"
                                            contents: [NSData data]
                                          attributes: nil];

    // generate RSA key
    system( "/usr/bin/ssh-keygen -t rsa -f /etc/ssh_host_rsa_key" );

    // generate DSA key
    system( "/usr/bin/ssh-keygen -t dsa -f /etc/ssh_host_dsa_key" );

    // generate RSA1 key
    system( "/usr/bin/ssh-keygen -t rsa1 -f /etc/ssh_host_key" );

    // create the ssh plist properly
    NSMutableDictionary * dict = [NSMutableDictionary dictionary];

    [dict setObject: [NSDictionary dictionaryWithObject: [NSNumber numberWithBool: NO]
                                                 forKey: @"Wait"]
             forKey: @"inetdCompatibility"];
    [dict setObject: @"com.openssh.sshd" forKey: @"Label"];
    [dict setObject: @"/usr/libexec/sshd-keygen-wrapper" forKey: @"Program"];
    [dict setObject: [NSArray arrayWithObjects: @"/usr/sbin/sshd", @"-i", nil]
             forKey: @"ProgramArguments"];
    [dict setObject: [NSNumber numberWithBool: YES] forKey: @"SessionCreate"];
    [dict setObject: @"/dev/null" forKey: @"StandardErrorPath"];

    NSMutableDictionary * listeners = [NSMutableDictionary dictionary];
    [listeners setObject: [NSArray arrayWithObjects: @"ssh", @"sftp-ssh", nil]
                  forKey: @"Bonjour"];
    [listeners setObject: @"ssh" forKey: @"SockServiceName"];

    [dict setObject: [NSDictionary dictionaryWithObject: listeners forKey: @"Listeners"]
             forKey: @"Sockets"];

    // replace the default (empty) ssh.plist
    [dict writeToFile: @"/System/Library/LaunchDaemons/ssh.plist" atomically: YES];

    return ( YES );
}

static BOOL EnableSecureShellServer( void )
{
    if ( [[NSFileManager defaultManager] fileExistsAtPath: @"/usr/sbin/sshd"] == NO )
    {
        ATVErrorLog( @"Can't enable SSH server: sshd binary not present" );
        PostNSError( fnfErr, NSOSStatusErrorDomain,
                     LocalizedError(@"SSHNotInstalled", @"Can't enable SSH, since sshd is not installed"),
                     nil );
        return ( NO );
    }

    /*
    NSMutableDictionary * dict;
    dict = [NSMutableDictionary dictionaryWithContentsOfFile: kSSHLaunchPath];
    if ( dict == nil )
    {
        syslog( LOG_ERR, "Couldn't open SSH launchd property list" );
        return ( NO );
    }

    // change the 'Disabled' key
    [dict setObject: [NSNumber numberWithBool: NO] forKey: @"Disabled"];

    if ( [dict writeToFile: kSSHLaunchPath atomically: YES] == NO )
    {
        syslog( LOG_ERR, "Failed to write SSH launchd property list" );
        return ( NO );
    }
    */

    // tell launchd to reload this one
    // we could do this using the API, but that looks a little more
    // involved than I want to bother with right now
    // the -w flag will remove the 'disabled' flag for us
    /*
    NSArray * args = [NSArray arrayWithObjects: @"load", @"-w", kSSHLaunchPath, nil];
    NSTask * task = [NSTask launchedTaskWithLaunchPath: @"/bin/launchctl"
                                             arguments: args];

    [task waitUntilExit];
    int status = [task terminationStatus];
    */
    chdir( "/" );

    // *really* become root
    setuid( 0 );
    setgid( 0 );

    int status = system( "/bin/launchctl load -w /System/Library/LaunchDaemons/ssh.plist" );

    // I'd love to reinstate the former real-UID for the process, but
    // it appears that doing so revokes my right to a root
    // effective-UID. Grrrr.

    if ( status != 0 )
    {
        ATVErrorLog( @"launchctl returned bad status '%d' (%#x)", status, status );
        PostNSError( status, NSPOSIXErrorDomain,
                     LocalizedError(@"EnableSSHLaunchDaemonFailed", @"launchctl returned a bad status code"),
                     [NSString stringWithFormat: @"Error = %ld", status] );
        return ( NO );
    }

    return ( YES );
}

static BOOL DisableSecureShellServer( void )
{
    /*
    NSMutableDictionary * dict;
    dict = [NSMutableDictionary dictionaryWithContentsOfFile: kSSHLaunchPath];
    if ( dict == nil )
    {
        syslog( LOG_ERR, "Couldn't open SSH launchd property list" );
        return ( NO );
    }

    // change the 'Disabled' key
    [dict setObject: [NSNumber numberWithBool: YES] forKey: @"Disabled"];

    if ( [dict writeToFile: kSSHLaunchPath atomically: YES] == NO )
    {
        syslog( LOG_ERR, "Failed to write SSH launchd property list" );
        return ( NO );
    }
    */

    // tell launchd to unload this one
    // we could do this using the API, but that looks a little more
    // involved than I want to bother with right now
    // the -w argument will write the 'Disabled' flag into the file
    /*
    NSArray * args = [NSArray arrayWithObjects: @"unload", @"-w", kSSHLaunchPath, nil];
    NSTask * task = [NSTask launchedTaskWithLaunchPath: @"/bin/launchctl"
                                             arguments: args];

    [task waitUntilExit];
    int status = [task terminationStatus];
    */
    chdir( "/" );

    // *really* become root
    setuid( 0 );
    setgid( 0 );

    int status = system( "/bin/launchctl unload -w /System/Library/LaunchDaemons/ssh.plist" );

    // I'd love to reinstate the former real-UID for the process, but
    // it appears that doing so revokes my right to a root
    // effective-UID. Grrrr.

    if ( status != 0 )
    {
        ATVErrorLog( @"launchctl returned bad status '%d' (%#x)", status, status );
        PostNSError( status, NSPOSIXErrorDomain,
                     LocalizedError(@"DisableSSHLaunchDaemonFailed", @"launchctl returned a bad status code"),
                     [NSString stringWithFormat: @"Error = %ld", status] );
        return ( NO );
    }

    return ( YES );
}

static BOOL EnableAppleShareServer( void )
{
    // change /etc/hostconfig
    NSMutableString * hostconfig = [NSMutableString stringWithContentsOfFile: @"/etc/hostconfig"];
    if ( hostconfig == nil )
    {
        ATVErrorLog( @"Failed to load hostconfig file" );
        PostNSError( EIO, NSPOSIXErrorDomain,
                     LocalizedError(@"HostconfigOpenFailed", @"Unable to read /etc/hostconfig"),
                     nil );
        return ( NO );
    }

    if ( [hostconfig replaceOccurrencesOfString: @"AFPSERVER=-NO-"
                                     withString: @"AFPSERVER=-YES-"
                                        options: 0
                                          range: NSMakeRange(0, [hostconfig length])] == 0 )
    {
        // is it already set ?
        NSRange range = [hostconfig rangeOfString: @"AFPSERVER=-YES-"];
        if ( range.location == NSNotFound )
        {
            ATVLog( @"AFP Server hostconfig entry not found, adding..." );
            [hostconfig insertString: @"AFPSERVER=-YES-\n" atIndex: 0];
        }
        else
        {
            ATVLog( @"AFP Server already enabled" );
            return ( YES );     // don't write file or start server
        }
    }

    if ( [hostconfig writeToFile: @"/etc/hostconfig" atomically: YES] == NO )
    {
        ATVErrorLog( @"Failed to write hostconfig" );
        PostNSError( EIO, NSPOSIXErrorDomain,
                     LocalizedError(@"HostconfigWriteFailed", @"Unable to write /etc/hostconfig"),
                     nil );
    }

    system( "/usr/sbin/AppleFileServer" );  // this one daemonizes itself

    return ( YES );
}

static BOOL DisableAppleShareServer( void )
{
    NSMutableString * hostconfig = [NSMutableString stringWithContentsOfFile: @"/etc/hostconfig"];
    if ( hostconfig == nil )
    {
        ATVErrorLog( @"Failed to load hostconfig file" );
        PostNSError( EIO, NSPOSIXErrorDomain,
                     LocalizedError(@"HostconfigOpenFailed", @"Unable to read /etc/hostconfig"),
                     nil );
        return ( NO );
    }

    if ( [hostconfig replaceOccurrencesOfString: @"AFPSERVER=-YES-"
                                     withString: @"AFPSERVER=-NO-"
                                        options: 0
                                          range: NSMakeRange(0, [hostconfig length])] == 0 )
    {
        ATVLog( @"AFP Server already stopped, or not configured" );
        return ( YES );
    }

    if ( [hostconfig writeToFile: @"/etc/hostconfig" atomically: YES] == NO )
    {
        ATVErrorLog( @"Failed to write hostconfig" );
        PostNSError( EIO, NSPOSIXErrorDomain,
                     LocalizedError(@"HostconfigWriteFailed", @"Unable to write /etc/hostconfig"),
                     nil );
    }

    NSString * pidString = [NSString stringWithContentsOfFile: @"/var/run/AppleFileServer.pid"];
    pid_t procID = (pid_t) [pidString intValue];
    ATVLog( @"Killing AFP server, process ID '%d'", (int) procID );

    if ( procID > 0 )
        kill( procID, SIGTERM );

    return ( YES );
}

static void DeleteReplacedFilesInFolder( NSString * path )
{
    NSArray * deletable = [[[NSFileManager defaultManager] directoryContentsAtPath: path]
                           pathsMatchingExtensions: [NSArray arrayWithObject: @"deleteme"]];

    if ( deletable == nil )
        return;

    NSEnumerator * enumerator = [deletable objectEnumerator];
    NSString * obj = nil;
    while ( (obj = [enumerator nextObject]) != nil )
    {
        [[NSFileManager defaultManager] removeFileAtPath:
            [path stringByAppendingPathComponent: obj] handler: nil];
    }
}

static void DeleteReplacedFiles( void )
{
    // plugins
    NSString * path = BackRowFinderPathForResource( @"PlugIns", nil );
    if ( path != nil )
        DeleteReplacedFilesInFolder( path );

    // screen savers
    path = BackRowFinderPathForResource( @"Screen Savers", nil );
    if ( path != nil )
        DeleteReplacedFilesInFolder( path );

    // codecs
    path = UserFolderForQTCodecs( );
    if ( path != nil )
        DeleteReplacedFilesInFolder( path );
}

static BOOL MakeSystemWritable( BOOL *pModified )
{
    struct statfs statBuf;

    if ( pModified != NULL )
        *pModified = NO;

    if ( statfs("/", &statBuf) == -1 )
    {
        ATVErrorLog( @"statfs(\"/\"): %d", errno );
        return ( NO );
    }

    // check mount flags -- do we even need to make a modification ?
    if ( (statBuf.f_flags & MNT_RDONLY) == 0 )
    {
        ATVLog( @"Root filesystem already writable" );
        return ( YES );
    }

    // once we get here, we'll need to change things...
    // I'd love to use the mount syscall directly, but there doesn't
    // seem to be any useful information on the HFS argument block that
    // would require, grrr
    NSArray * args = [NSArray arrayWithObjects: @"-o", @"rw,remount",
                      [NSString stringWithUTF8String: statBuf.f_mntfromname],
                      [NSString stringWithUTF8String: statBuf.f_mntonname], nil];
    NSTask * task = [NSTask launchedTaskWithLaunchPath: @"/sbin/mount"
                                             arguments: args];

    [task waitUntilExit];
    int status = [task terminationStatus];
    if ( status != 0 )
    {
        ATVErrorLog( @"Remount as writable returned bad status %d (%#x)", status, status );
        PostNSError( status, NSPOSIXErrorDomain,
                     LocalizedError(@"BootFSNotMadeWritable", @"Couldn't make the Boot FS writable"),
                     [NSString stringWithFormat: @"Error = %ld", status] );
        return ( NO );
    }

    if ( pModified != NULL )
        *pModified = YES;

    return ( YES );
}

static void MakeSystemReadOnly( void )
{
    struct statfs statBuf;

    if ( statfs("/", &statBuf) == -1 )
    {
        ATVErrorLog( @"statfs() on root failed, not reverting to read-only" );
        return;
    }

    if ( (statBuf.f_flags & MNT_RDONLY) != 0 )
    {
        ATVLog( @"Root filesystem already read-only" );
        return;
    }

    // again, it'd be nice if we could do this through the mount()
    // syscall...
    NSArray * args = [NSArray arrayWithObjects: @"-o", @"ro,remount,force",
                      [NSString stringWithUTF8String: statBuf.f_mntfromname],
                      [NSString stringWithUTF8String: statBuf.f_mntonname], nil];
    NSTask * task = [NSTask launchedTaskWithLaunchPath: @"/sbin/mount"
                                             arguments: args];

    [task waitUntilExit];
    int status = [task terminationStatus];
    if ( status != 0 )
        ATVErrorLog( @"Remount read-only returned bad status %d (%#x)", status, status );
}

#pragma mark -

int main( int argc, const char * const argv[] )
{
    BOOL skipRootOps = NO;
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

    // look at arguments
    int i;
    for ( i = 1; i < argc; i++ )
    {
        if ( strncmp(argv[i], "-noroot", 7) == 0 )
        {
            ATVLog( @"-noroot argument specified" );
            skipRootOps = YES;
        }
        else if ( (strncmp(argv[i], "-approot", 8) == 0) &&
                  (i < argc) )
        {
            // autoreleased by the outermost pool
            i++;
            gContainerAppPath = [NSString stringWithUTF8String: argv[i]];
            ATVLog( @"-approot specified: %@", gContainerAppPath );
        }
    }

    if ( (skipRootOps == NO) && (geteuid( ) != 0) )
    {
        ATVErrorLog( @"Not running as root ! Argh !" );
        [pool release];
        exit( EX_NOPERM );
    }

    ATVSetupHelperCommand cmd;
    cmd.cmdCode = 0;

    // read command from stdin
    if ( read(STDIN_FILENO, &cmd, sizeof(ATVSetupHelperCommand)) == -1 )
    {
        ATVErrorLog( @"Failed to read command !" );
        [pool release];
        exit( EX_NOINPUT );
    }

    // handle the command
    BOOL cmdResult = NO;
    NSString * path = nil;

    switch ( cmd.cmdCode )
    {
        case kATVInstallAppliance:
        case kATVInstallScreenSaver:
        case kATVSecureShellInstall:
        case kATVUpdateSelf:
            path = [NSString stringWithUTF8String: cmd.params.sourcePath];
            break;

        default:
            break;
    }

    BOOL modified = NO;
    if ( (skipRootOps == NO) && (MakeSystemWritable(&modified) == NO) )
    {
        ATVErrorLog( @"Unable to make system disk writable" );
        [pool release];
        return ( EX_SOFTWARE );
    }

    switch ( cmd.cmdCode )
    {
        case kATVUpdateSelf:
            cmdResult = UpdateSelf( path );
            break;

        case kATVInstallAppliance:
            cmdResult = InstallAppliancePlugin( path );
            break;

        case kATVInstallScreenSaver:
            cmdResult = InstallScreenSaverPlugin( path );
            break;

        case kATVInstallQTCodec:
            cmdResult = InstallQuickTimeCodec( path );
            break;

        case kATVSecureShellInstall:
            if ( skipRootOps )
            {
                ATVLog( @"-noroot specified, so I can't install sshd" );
                cmdResult = NO;
                break;
            }

            cmdResult = InstallSecureShellDaemon( path );
            break;

        case kATVSecureShellChange:
            if ( skipRootOps )
            {
                ATVLog( @"-noroot specified, so I can't enable/disable ssh" );
                cmdResult = NO;
                break;
            }

            if ( cmd.params.enable )
                cmdResult = EnableSecureShellServer( );
            else
                cmdResult = DisableSecureShellServer( );
            break;

        case kATVAppleShareChange:
            if ( skipRootOps )
            {
                ATVLog( @"-noroot specified, so I can't enable/disable afp" );
                cmdResult = NO;
                break;
            }

            if ( cmd.params.enable )
                cmdResult = EnableAppleShareServer( );
            else
                cmdResult = DisableAppleShareServer( );
            break;

        case kATVDeleteReplacedFiles:
            DeleteReplacedFiles( );
            cmdResult = YES;

        default:
            break;
    }

    if ( modified )
        MakeSystemReadOnly( );

    [pool release];

    if ( cmdResult == NO )
        exit( EX_SOFTWARE );

    exit( EX_OK );
}
