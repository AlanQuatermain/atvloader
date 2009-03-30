//
//  ATVDownloadController.h
//  AwkwardTV
//
//  Created by Alan Quatermain on 11/04/07.
//  Copyright 2007 AwkwardTV. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <BackRow/BRLayerController.h>

typedef enum
{
    kPluginDownloadType,
    kScreenSaverDownloadType,
    kCodecDownloadType

} ATVDownloadType;

@class BRHeaderControl, BRTextControl, ATVProgressControl;

@interface ATVDownloadController : BRLayerController
{
    NSDictionary *          _downloadInfo;
    id                      _delegate;
    NSURLDownload *         _downloader;
    NSString *              _outputPath;
    ATVDownloadType         _type;
    long long               _totalLength;
    long long               _gotLength;
    BOOL                    _quitOnPop;

    BRHeaderControl *       _header;
    BRTextControl *         _sourceText;
    ATVProgressControl *    _progressBar;
}

+ (void) clearAllDownloadCaches;

- (id) initWithType: (ATVDownloadType) type
       downloadInfo: (NSDictionary *) dict
              scene: (BRRenderScene *) scene
           delegate: (id) obj;
- (void) dealloc;
- (void) cancelDownload;        // if possible, this will be resumable
- (void) deleteDownloadCache;   // remove downloaded data, no longer resumable

- (void) wasPushed;     // begin downloading
- (void) willBePopped;  // stop downloading, if in progress
- (BOOL) isNetworkDependent;

- (void) setTitle: (NSString *) title;
- (NSString *) title;

- (void) setSourceText: (NSString *) srcText;
- (NSString *) sourceText;

- (float) percentDownloaded;

@end
