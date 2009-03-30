//
//  ATVPluginListXMLParser.h
//  AwkwardTV
//
//  Created by Alan Quatermain on 03/04/07.
//  Copyright 2007 AwkwardTV. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface ATVPluginListXMLParser : NSObject
{
    NSXMLParser *           _parser;
    NSMutableArray *        _rootList;
    NSMutableDictionary *   _currentItem;
    NSString *              _currentTag;
}

// just use this function
+ (NSArray *) pluginListFromXMLData: (NSData *) data error: (NSError **) error;

- (id) initWithXMLData: (NSData *) data;
- (void) dealloc;
- (NSArray *) parseList: (NSError **) error;


// NSXMLParser delegate methods

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
    attributes:(NSDictionary *)attributeDict;

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName;

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string;

@end
