//
//  ATVGZipper.m
//  AwkwardTV
//
//  Created by Alan Quatermain on 13/05/07.
//  Copyright 2007 AwkwwardTV. All rights reserved.
//

#import "ATVGZipper.h"
#import "ATVLogger.h"

@implementation ATVGZipper

+ (ATVGZipper *) gzipperForFileAtPath: (NSString *) path
{
    return ( [[[self alloc] initWithPath: path] autorelease] );
}

+ (NSString *) unzipFileAtPath: (NSString *) path error: (NSError **) error
{
    ATVGZipper * obj = [self gzipperForFileAtPath: path];
    return ( [obj unzip: error] );
}

- (id) initWithPath: (NSString *) path
{
    if ( [super init] == nil )
        return ( nil );

    _file = gzopen( [path fileSystemRepresentation], "rb" );
    if ( _file == NULL )
    {
        [self autorelease];
        return ( nil );
    }

    // work out the output filename
    NSString * ext = [path pathExtension];
    if ( [ext isEqualToString: @"tgz"] )
        _outPath = [[path stringByDeletingPathExtension]
                    stringByAppendingPathExtension: @"tar"];
    else
        _outPath = [path stringByDeletingPathExtension];

    [[NSFileManager defaultManager] createFileAtPath: _outPath
                                            contents: [NSData data]
                                          attributes: nil];
    _outfile = [[NSFileHandle fileHandleForWritingAtPath: _outPath] retain];
    if ( _outfile == nil )
    {
        [self autorelease];
        return ( nil );
    }

    return ( self );
}

- (void) dealloc
{
    if ( _file != 0 )
        gzclose( _file );
    [_outfile release];

    [super dealloc];
}

- (NSString *) unzip: (NSError **) error
{
    // pull out chunks, write to file, return file path at the end
    unsigned char buf[4096];
    int sizeRead = 0;

    ATVDebugLog( @"Un-gzipping file to path '%@'", _outPath );

    do
    {
        sizeRead = gzread( _file, buf, 4096 );
        ATVDebugLog( @"gzread(): %d bytes", sizeRead );

        if ( sizeRead > 0 )
        {
            NSData * data = [[NSData alloc] initWithBytes: buf length: sizeRead];
            [_outfile writeData: data];
            [data release];
        }

    } while ( sizeRead > 0 );

    [_outfile synchronizeFile];
    [_outfile closeFile];

    if ( sizeRead < 0 )
    {
        int err = 0;
        const char * errstr = gzerror( _file, &err );
        gzclose( _file );
        _file = 0;

        ATVErrorLog( @"gzread() returned error '%d' (%s)",
                     err, (errstr == NULL ? "<no message string>" : errstr) );

        if ( error != NULL )
        {
            NSString * nsErrstr;
            if ( errstr != NULL )
                nsErrstr = [NSString stringWithFormat: @"GZip: %@",
                            [NSString stringWithUTF8String: errstr]];
            else
                nsErrstr = [NSString stringWithFormat: @"GZip: error '%d'", err];

            NSDictionary * userInfo = [NSDictionary dictionaryWithObject: nsErrstr
                                         forKey: NSLocalizedFailureReasonErrorKey];

            *error = [NSError errorWithDomain: NSPOSIXErrorDomain
                                         code: err
                                     userInfo: userInfo];
        }

        return ( nil );
    }

    gzclose( _file );
    _file = 0;

    return ( _outPath );
}

@end
