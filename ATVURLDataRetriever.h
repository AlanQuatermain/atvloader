//
//  ATVURLDataRetriever.h
//  AwkwardTV
//
//  Created by Alan Quatermain on 03/04/07.
//  Copyright 2007 AwkwardTV. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface ATVURLDataRetriever : NSObject
{
    NSURLConnection *   _urlConnection;
    NSMutableData *     _receivedData;
    NSURL *             _url;
    id                  _delegate;
}

// simple one-shot method to deal with everything below
+ (ATVURLDataRetriever *) fetchDataFromURL: (NSURL *) url
                               forDelegate: (id) delegate;

- (id) initWithURL: (NSURL *) url delegate: (id) delegate;
- (void) dealloc;

- (void) stopDownloading;


// NSURLConnection delegate methods

- (void) connection: (NSURLConnection *) connection
 didReceiveResponse: (NSURLResponse *) response;

- (void) connection: (NSURLConnection *) connection
     didReceiveData: (NSData *) data;

- (void) connection: (NSURLConnection *) connection
   didFailWithError: (NSError *) error;

- (void) connectionDidFinishLoading: (NSURLConnection *) connection;

@end

@interface NSObject (ATVURLDataRetrieverDelegate)

- (void) failedToGetDataFromURL: (NSURL *) url error: (NSError *) error;
- (void) retrievedData: (NSData *) data fromURL: (NSURL *) url;

@end
