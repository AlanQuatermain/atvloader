//
//  ATVLogger.m
//  AwkwardTV
//
//  Created by Alan Quatermain on 30/04/07.
//  Copyright 2007 AwkwardTV. All rights reserved.
//

#import "ATVLogger.h"

#if 0
#define LOG(A, args...) NSLog(@"ATVLogger: " A, ##args)
#else
#define LOG(A, args...)
#endif

static ATVLogger * __sharedAppLogger = nil;

static NSString * LogPathForApplicationName( NSString * appName )
{
    NSArray * searchPath = NSSearchPathForDirectoriesInDomains( NSLibraryDirectory,
        NSLocalDomainMask, YES );

    // first item should be /Library, which is what we want
    NSString * path = nil;
    if ( (searchPath == nil) || ([searchPath count] == 0) )
        path = @"/Library/Logs";
    else
        path = [[searchPath objectAtIndex: 0] stringByAppendingPathComponent: @"Logs"];

    return ( [[path stringByAppendingPathComponent: appName]
              stringByAppendingPathExtension: @"log"] );
}

@interface ATVLogger (Private)

- (BOOL) shouldRollLog;
- (void) rollLogFiles;

@end

@implementation ATVLogger

+ (ATVLogger *) log
{
    if ( __sharedAppLogger == nil )
    {
        NSString * appName;
        NSBundle * bundle = [NSBundle bundleForClass: [self class]];
        if ( bundle != nil )
        {
            appName = [[bundle executablePath] lastPathComponent];
        }
        else
        {
            char path[PATH_MAX];
            int len = PATH_MAX;
            _NSGetExecutablePath( path, &len );
            appName = [[NSString stringWithUTF8String: path] lastPathComponent];
        }

        __sharedAppLogger = [[ATVLogger alloc] initWithAppName: appName];
    }

    return ( __sharedAppLogger );
}

- (id) initWithAppName: (NSString *) name
{
    if ( [super init] == nil )
        return ( nil );

    LOG( @"Using app name '%@'", name );

    // default value, same as syslog's
    _level = LOG_INFO;

    // see if there's a value in the prefs
    NSNumber * num = (NSNumber *) CFPreferencesCopyAppValue( CFSTR("LogLevel"),
        CFSTR("org.awkwardtv.appliance.loader") );
    if ( num != nil )
        _level = [num intValue];

    LOG( @"Log level is %d", _level );

    _path = LogPathForApplicationName( name );
    LOG( @"Got log path '%@'", _path );
    if ( _path == nil )
    {
        [self autorelease];
        return ( nil );
    }

    [_path retain];

    // ensure the file exists already
    if ( [[NSFileManager defaultManager] fileExistsAtPath: _path] == NO )
    {
        [[NSFileManager defaultManager] createFileAtPath: _path
                                                contents: [NSData data]
                                              attributes: nil];
    }

    return ( self );
}

- (void) dealloc
{
    [_path release];
    [super dealloc];
}

- (void) setLogLevel: (int) level
{
    @synchronized(self)
    {
        _level = level;
    }
}

- (int) logLevel
{
    return ( _level );
}

- (void) appendLogEntry: (NSString *) format level: (int) level, ...
{
    va_list args;
    va_start( args, level );
    [self appendLogEntry: format level: level arguments: args];
    va_end( args );
}

- (void) appendLogEntry: (NSString *) format level: (int) level arguments: (va_list) args
{
    @synchronized(self)
    {
        if ( level <= _level )
        {
            if ( [self shouldRollLog] )
                [self rollLogFiles];

            NSString * entry = [[[NSString alloc] initWithFormat: format arguments: args] autorelease];
            LOG( @"Appending log entry '%@'", entry );
            if ( [entry hasSuffix: @"\n"] == NO )
                entry = [entry stringByAppendingString: @"\n"];

            NSFileHandle * fh = [NSFileHandle fileHandleForWritingAtPath: _path];
            [fh seekToEndOfFile];
            [fh writeData: [entry dataUsingEncoding: NSUTF8StringEncoding]];
            [fh synchronizeFile];
            [fh closeFile];
        }
    }
}

- (void) emptyLog
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

    @try
    {
        @synchronized(self)
        {
            // for every file matching name.X.log, delete them
            // for the main file, truncate it
            NSFileHandle * fh = [NSFileHandle fileHandleForUpdatingAtPath: _path];
            [fh truncateFileAtOffset: 0];
            [fh closeFile];

            NSMutableString * path = [NSMutableString string];
            NSString * base = [_path stringByDeletingLastPathComponent];
            int i;
            for ( i = 1; i < 10; i++ )
            {
                [path setString: base];
                [path appendFormat: @"%d.log", i];

                if ( [[NSFileManager defaultManager] fileExistsAtPath: path] == NO )
                    break;  // no more files to delete

                [[NSFileManager defaultManager] removeFileAtPath: path handler: nil];
            }
        }
    }
    @finally
    {
        [pool release];
    }
}

- (NSString *) logPath
{
    return ( [[_path retain] autorelease] );
}

@end

@implementation ATVLogger (Private)

- (BOOL) shouldRollLog
{
    NSDictionary * dict = [[NSFileManager defaultManager] fileAttributesAtPath: _path
                           traverseLink: NO];
    if ( dict == nil )
        return ( NO );

    if ( [dict fileSize] < 1024 * 1024 * 2 )
        return ( NO );

    return ( YES );
}

- (void) rollLogFiles
{
    // okay, so we go from .log to .1.log up to .9.log
    // If there's a .9.log, it gets deleted
    // anything below that gets moved up one notch
    // we attach a message to the current log to indicate that it was
    // rolled over, and put a similar message at the start of the new
    // logfile

    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

    @try
    {
        NSString * base = [_path stringByDeletingPathExtension];

        // delete last file, if it exists
        NSString * lastFile = [[base stringByAppendingPathExtension: @"9"]
                               stringByAppendingPathExtension: @"log"];
        [[NSFileManager defaultManager] removeFileAtPath: lastFile handler: nil];

        // for remaining files, move them around
        int i;
        for ( i = 8; i > 0; i-- )
        {
            NSString * srcPath = [[base stringByAppendingPathExtension:
                [NSString stringWithFormat: @"%d", i]] stringByAppendingPathExtension: @"log"];
            NSString * dstPath = [[base stringByAppendingPathExtension:
                [NSString stringWithFormat: @"%d", i+1]] stringByAppendingPathExtension: @"log"];

            [[NSFileManager defaultManager] movePath: srcPath toPath: dstPath handler: nil];
        }

        // now we move the current log our of the way

        // append a message first
        NSString * msg = [NSString stringWithFormat: @"***** Log rolled: %@ *****", [NSDate date]];
        NSFileHandle * fh = [NSFileHandle fileHandleForWritingAtPath: _path];
        [fh seekToEndOfFile];
        [fh writeData: [msg dataUsingEncoding: NSUTF8StringEncoding]];
        [fh closeFile];

        // move the file
        [[NSFileManager defaultManager] movePath: _path
                                          toPath: [[base stringByAppendingPathExtension: @"1"]
                                                   stringByAppendingPathExtension: @"log"]
                                         handler: nil];

        // create the new file
        [[NSFileManager defaultManager] createFileAtPath: _path
                                                contents: [[msg stringByAppendingString: @"\n"]
            dataUsingEncoding: NSUTF8StringEncoding]
                                              attributes: nil];

        // all done
    }
    @finally
    {
        [pool release];
    }
}

@end
