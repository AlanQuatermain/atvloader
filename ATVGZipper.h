//
//  ATVGZipper.h
//  AwkwardTV
//
//  Created by Alan Quatermain on 13/05/07.
//  Copyright 2007 AwkwwardTV. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <zlib.h>

@interface ATVGZipper : NSObject
{
    gzFile          _file;
    NSFileHandle *  _outfile;
    NSString *      _outPath;
}

+ (ATVGZipper *) gzipperForFileAtPath: (NSString *) path;
+ (NSString *) unzipFileAtPath: (NSString *) path error: (NSError **) error;

- (id) initWithPath: (NSString *) path;
- (void) dealloc;

- (NSString *) unzip: (NSError **) error;

@end
