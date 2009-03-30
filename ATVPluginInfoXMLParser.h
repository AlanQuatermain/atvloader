//
//  ATVPluginInfoXMLParser.h
//  AwkwardTV
//
//  Created by Alan Quatermain on 03/04/07.
//  Copyright 2007 AwkwardTV. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface ATVPluginInfoXMLParser : NSObject
{
    NSXMLParser *           _parser;
    NSMutableDictionary *   _rootDict;
    NSMutableDictionary *   _infoItem;
    NSMutableDictionary *   _englishItem;
    NSString *              _currentTag;
    NSMutableString *       _currentString;
    unsigned int            _insideLanguageItem:1;
    unsigned int            _insideEnglishLanguage:1;
    unsigned int            _insideChosenLanguage:1;
}

// just use this function
+ (NSDictionary *) pluginDetailsFromXMLData: (NSData *) data error: (NSError **) error;

- (id) initWithXMLData: (NSData *) data;
- (void) dealloc;
- (NSDictionary *) parseDetails: (NSError **) error;


// NSXMLParser delegate methods

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
    attributes:(NSDictionary *)attributeDict;

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName;

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string;

@end
