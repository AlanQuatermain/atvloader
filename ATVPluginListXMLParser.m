//
//  ATVPluginListXMLParser.m
//  AwkwardTV
//
//  Created by Alan Quatermain on 03/04/07.
//  Copyright 2007 AwkwardTV. All rights reserved.
//

#import "ATVPluginListXMLParser.h"
#import "ATVLogger.h"

@implementation ATVPluginListXMLParser

+ (NSArray *) pluginListFromXMLData: (NSData *) data error: (NSError **) error;
{
    ATVPluginListXMLParser * obj = [[[self alloc] initWithXMLData: data] autorelease];
    return ( [obj parseList: error] );
}

- (id) initWithXMLData: (NSData *) data
{
    if ( [super init] == nil )
        return ( nil );

    _parser = [[NSXMLParser alloc] initWithData: data];
    [_parser setDelegate: self];
    [_parser setShouldProcessNamespaces: NO];
    [_parser setShouldResolveExternalEntities: NO];

    _rootList = [[NSMutableArray alloc] init];

    return ( self );
}

- (void) dealloc
{
    [_parser release];
    [_rootList release];
    [_currentItem release];
    [_currentTag release];

    [super dealloc];
}

- (NSArray *) parseList: (NSError **) error
{
    if ( [_parser parse] == NO )
    {
        *error = [_parser parserError];
        return ( nil );
    }

    ATVDebugLog( @"Result List: %@", _rootList );

    return ( [NSArray arrayWithArray: _rootList] );
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
    attributes:(NSDictionary *)attributeDict
{
    ATVDebugLog( @"Open Element: %@", elementName );
    if ( [elementName isEqualToString: @"item"] )
    {
        // opening a new item in the list
        ATVDebugLog( @"...opening a new item" );
        _currentItem = [[NSMutableDictionary alloc] init];
    }
    else if ( [elementName isEqualToString: @"icon"] )
    {
        ATVDebugLog( @"...storing icon URL" );
        [_currentItem setObject: [attributeDict objectForKey: @"url"]
                         forKey: elementName];
    }
    else if ( _currentItem != nil )
    {
        // something to go inside an item
        ATVDebugLog( @"...adding a new key" );
        _currentTag = [elementName retain];
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    ATVDebugLog( @"Close Element: %@", elementName );
    if ( ([elementName isEqualToString: @"item"]) && (_currentItem != nil) )
    {
        // store the current item to the list
        ATVDebugLog( @"...closing the current item" );
        ATVDebugLog( @"Item: %@", _currentItem );
        [_rootList addObject: _currentItem];
        [_currentItem release];
        _currentItem = nil;
    }
    else if ( _currentTag != nil )
    {
        // turn this off so we know we're outside the tag next time
        ATVDebugLog( @"...closing key" );
        [_currentTag release];
        _currentTag = nil;
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    ATVDebugLog( @"Found Characters: %@", string );
    if ( (_currentTag != nil) && (_currentItem != nil) )
    {
        // found some text inside a tag, inside an item
        // store into the item's dictionary
        ATVDebugLog( @"...setting value for key %@", _currentTag );
        [_currentItem setObject: string forKey: _currentTag];
    }
}

@end
