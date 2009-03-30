//
//  ATVURLDataRetriever.m
//  AwkwardTV
//
//  Created by Alan Quatermain on 03/04/07.
//  Copyright 2007 AwkwardTV. All rights reserved.
//

#import "ATVURLDataRetriever.h"
#import "ATVLogger.h"

@implementation ATVURLDataRetriever

+ (ATVURLDataRetriever *) fetchDataFromURL: (NSURL *) url
                               forDelegate: (id) delegate
{
    ATVURLDataRetriever * obj = [[self alloc] initWithURL: url delegate: delegate];
    return ( [obj autorelease] );
}

- (id) initWithURL: (NSURL *) url delegate: (id) delegate
{
    if ( [super init] == nil )
        return ( nil );

    _url = [url retain];
    _delegate = delegate;

    NSMutableURLRequest * request = [NSMutableURLRequest requestWithURL: url
                                                            cachePolicy: NSURLRequestReloadIgnoringCacheData
                                                        timeoutInterval: 20.0];
    [request setValue: @"Mozilla/5.0 (AppleTV; U; Intel Mac OS X; ATVLoader)"
   forHTTPHeaderField: @"User-Agent"];

    // create the connection, which will start loading the data
    _urlConnection = [[NSURLConnection alloc] initWithRequest: request
                                                     delegate: self];

    if ( _urlConnection == nil )
    {
        [self autorelease];
        return ( nil );
    }

    _receivedData = [[NSMutableData data] retain];

    return ( self );
}

- (void) dealloc
{
    [self stopDownloading];
    [_url release];
    [_urlConnection release];
    [_receivedData release];
    [super dealloc];
}

- (void) stopDownloading
{
    [_urlConnection cancel];
}

- (void) connection: (NSURLConnection *) connection
 didReceiveResponse: (NSURLResponse *) response
{
    // like the example, we'll just be dumb & empty our data
    [_receivedData setLength: 0];
}

- (void) connection: (NSURLConnection *) connection
     didReceiveData: (NSData *) data
{
    [_receivedData appendData: data];
}

- (void) connection: (NSURLConnection *) connection
   didFailWithError: (NSError *) error
{
    if ( [_delegate respondsToSelector: @selector(failedToGetDataFromURL:error:)] )
        [_delegate failedToGetDataFromURL: _url error: error];
}

- (void) connectionDidFinishLoading: (NSURLConnection *) connection
{
    if ( [_delegate respondsToSelector: @selector(retrievedData:fromURL:)] )
        [_delegate retrievedData: _receivedData fromURL: _url];
}

@end
