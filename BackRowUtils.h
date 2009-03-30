/*
 *  BackRowUtils.h
 *  AwkwardTV
 *
 *  Created by Alan Quatermain on 02/04/07.
 *  Copyright 2007 AwkwardTV. All rights reserved.
 *
 */

#import <syslog.h>
#import <Foundation/Foundation.h>
#import <BackRow/BRLocalizedStringManager.h>

// BackRow-supplied logging routines
void BRLog( NSString * format, ... );
void BRDebugLog( NSString * format, ... );
void BRSystemLog( int level, NSString * format, ... );
void BRSystemLogv( int level, NSString * format, va_list args );

// other BackRow public functions
CGImageRef CreateImageForURL( CFURLRef imageURL );

NSData * CreateBitmapDataFromAttributedString( CFAttributedStringRef string,
                                               UInt32 width, UInt32 height );
NSSize GetBoundsFromAttributedStringWithConstraint( NSAttributedString * string,
    float width, float height, /*CTFramesetterRef*/CFTypeRef framesetter,
    /*CTTypesetterRef*/CFTypeRef typesetter,
    BOOL *typesetterRequestsMoreLinesThanFramesetter );

// plugin-based NSLocalizedString macros
// use genstrings -s BRLocalizedString -o <Language>.lproj to generate Localized.strings
#define BRLocalizedString(key, comment) \
    [BRLocalizedStringManager appliance:self localizedStringForKey:(key) inFile:nil]
#define BRLocalizedStringFromTable(key, tbl, comment) \
    [BRLocalizedStringManager appliance:self localizedStringForKey:(key) inFile:(tbl)]
#define BRLocalizedStringFromTableInBundle(key, tbl, obj, comment) \
    [BRLocalizedStringManager appliance:(obj) localizedStringForKey:(key) inFile:(tbl)]
