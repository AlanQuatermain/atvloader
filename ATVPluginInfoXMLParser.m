//
//  ATVPluginInfoXMLParser.m
//  AwkwardTV
//
//  Created by Alan Quatermain on 03/04/07.
//  Copyright 2007 AwkwardTV. All rights reserved.
//

#import "ATVPluginInfoXMLParser.h"
#import "ATVLogger.h"
#import "BackRowUtils.h"

#if 0
# define _LOG   ATVLog
#else
# define _LOG   ATVDebugLog
#endif

@implementation ATVPluginInfoXMLParser

+ (NSDictionary *) pluginDetailsFromXMLData: (NSData *) data error: (NSError **) error
{
    ATVPluginInfoXMLParser * obj = [[[self alloc] initWithXMLData: data] autorelease];
    return ( [obj parseDetails: error] );
}

- (id) initWithXMLData: (NSData *) data
{
    if ( [super init] == nil )
        return ( nil );

    // there's an error in the test data......
    NSMutableData * mdata = [data mutableCopy];
    char * bytes = [mdata mutableBytes];
    char * loc = strnstr( bytes, ">>", [mdata length] );
    if ( loc != NULL )
        loc[1] = ' ';
    
    NSMutableString * str = [[NSMutableString alloc] initWithData: data
                                                         encoding: NSUTF8StringEncoding];
    _LOG( @"Original:\n%@", str );
    /*NSRange range = [str rangeOfString: @"<guid>>"];
    [str replaceCharactersInRange: range withString: @"<guid>"];*/
    [str replaceOccurrencesOfString: @"&" withString: @"%26"
                            options: 0 range: NSMakeRange(0, [str length])];
    _LOG( @"Fixed:\n%@", str );
    data = [str dataUsingEncoding: NSUTF8StringEncoding];

    _parser = [[NSXMLParser alloc] initWithData: data];
    [_parser setDelegate: self];
    [_parser setShouldProcessNamespaces: NO];
    [_parser setShouldResolveExternalEntities: NO];

    _rootDict = [[NSMutableDictionary alloc] init];
    _currentString = [[NSMutableString string] retain];

    return ( self );
}

- (void) dealloc
{
    [_parser release];
    [_rootDict release];
    [_infoItem release];
    [_currentTag release];
    [_currentString release];

    [super dealloc];
}

- (NSDictionary *) parseDetails: (NSError **) error
{
    if ( [_parser parse] == NO )
    {
        if ( error != NULL )
        {
            NSMutableDictionary * userInfo = [NSMutableDictionary dictionary];
            [userInfo setObject: BRLocalizedString(@"Error parsing XML file", @"Parser error reason")
                         forKey: NSLocalizedFailureReasonErrorKey];
            [userInfo setObject: BRLocalizedString(@"XMLParserErrorSuggestion", @"Parser error suggestion")
                         forKey: NSLocalizedRecoverySuggestionErrorKey];

            NSError * parserError = [_parser parserError];
            *error = [NSError errorWithDomain: [parserError domain]
                                         code: [parserError code]
                                     userInfo: userInfo];

            _LOG( @"Error: %@", *error );
        }

        return ( nil );
    }

    // if we couldn't find any valid data for our chosen language, use
    // English instead
    if ( [_rootDict objectForKey: @"info"] == nil )
    {
        id obj = [_rootDict objectForKey: @"English"];
        if ( obj != nil )
            [_rootDict setObject: obj forKey: @"info"];
    }
    _LOG( @"Result dict: %@", _rootDict );

    return ( [NSDictionary dictionaryWithDictionary: _rootDict] );
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
    attributes:(NSDictionary *)attributeDict
{
    _LOG( @"Open Element: %@", elementName );
    if ( ([elementName isEqualToString: @"icon"]) ||
         ([elementName isEqualToString: @"screenshot"]) )
    {
        // add url attribute as value directly
        _LOG( @"...adding url" );
        [_rootDict setObject: [attributeDict objectForKey: @"url"]
                      forKey: elementName];
    }
    else if ( [elementName isEqualToString: @"enclosure"] )
    {
        // add the whole attribute dictionary here
        _LOG( @"...adding attribute dictionary" );
        [_rootDict setObject: attributeDict forKey: elementName];
    }
    else if ( [elementName isEqualToString: @"info"] )
    {
        // this is the info sub-dict; we want to only read the bits in
        // the language we're interested in

        // set this -- it acts as a flag so we know we're within 'info'
        _LOG( @"...entered localized info section" );
        _infoItem = [[NSMutableDictionary alloc] init];
    }
    else if ( _infoItem != nil )
    {
        // we're inside the info item
        if ( _insideLanguageItem == 0 )
        {
            // we're looking at an opening language tag, check it
            // against the current locale
            NSString * canon = [NSLocale canonicalLocaleIdentifierFromString: elementName];
            NSString * current = [[NSLocale currentLocale] objectForKey: NSLocaleLanguageCode];
            if ( (canon != nil) && (current != nil) &&
                 ([canon isEqualToString: current]) )
            {
                // we've found our language
                _LOG( @"...found current language" );
                _insideChosenLanguage = 1;
            }

            // always pull out the English variation, as a fallback
            if ( [elementName isEqualToString: @"English"] )
            {
                _LOG( @"...found english language" );
                _insideEnglishLanguage = 1;
                _englishItem = [[NSMutableDictionary alloc] init];
            }

            _insideLanguageItem = 1;
        }
        else
        {
            // already inside a language -- do we want to store it?
            if ( (_insideChosenLanguage) || (_insideEnglishLanguage) )
            {
                _LOG( @"...opening localized tag" );
                _currentTag = [elementName retain];
                [_currentString setString: @""];
            }
        }
    }
    else if ( [elementName isEqualToString: @"item"] == NO )
    {
        // anything else, except for the root item: we open a new tag
        _LOG( @"...opening tag" );
        _currentTag = [elementName retain];
        [_currentString setString: @""];
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName
  namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    _LOG( @"Close Element: %@", elementName );
    if ( _currentTag != nil )
    {
        if ( [_currentString length] != 0 )
        {
            NSCharacterSet * validSet = [[NSCharacterSet whitespaceAndNewlineCharacterSet] invertedSet];
            NSRange range = [_currentString rangeOfCharacterFromSet: validSet];

            if ( range.location != NSNotFound )
            {
                _LOG( @"Storing current tag" );
                // note to self: don't store the mutable string object
                // itself. That's a bad idea...
                NSString * store = [NSString stringWithString: _currentString];

                // where is the current tag ?
                if ( _insideLanguageItem )
                {
                    if ( _insideChosenLanguage )
                        [_infoItem setObject: store forKey: _currentTag];
                    if ( _insideEnglishLanguage )
                        [_englishItem setObject: store forKey: _currentTag];
                }
                else if ( [_currentTag isEqualToString: @"pubDate"] )
                {
                    [_rootDict setObject: [NSDate dateWithNaturalLanguageString: store]
                                  forKey: _currentTag];
                }
                else
                {
                    [_rootDict setObject: store forKey: _currentTag];
                }
            }
            else
            {
                _LOG( @"String contains only whitespace, ignoring" );
            }
        }

        _LOG( @"...closing tag" );
        [_currentTag release];
        _currentTag = nil;
    }
    else if ( _insideLanguageItem )
    {
        // not closing a monitored tag, but inside a language. This
        // means we're leaving the section for this language
        _insideLanguageItem = 0;

        if ( _insideChosenLanguage )
            [_rootDict setObject: _infoItem forKey: @"info"];
        if ( _insideEnglishLanguage )
            [_rootDict setObject: _englishItem forKey: @"English"];

        _insideChosenLanguage = 0;
        _insideEnglishLanguage = 0;
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    _LOG( @"Found characters: %@", string );
    if ( _currentTag != nil )
    {
        // undo any URL-encoding on the characters here
        NSString * store = [string stringByReplacingPercentEscapesUsingEncoding: NSUTF8StringEncoding];
        if ( [store isEqualToString: string] == NO )
            _LOG( @"Parsed percent-escape codes to create string '%@'", store );

        _LOG( @"Appending characters for key %@", _currentTag );

        if ( _currentString == nil )
            _currentString = [[NSMutableString alloc] initWithString: store];
        else
            [_currentString appendString: store];
    }
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError
{
    _LOG( @"Parse Error: %@", parseError );
}

- (void)parser:(NSXMLParser *)parser validationErrorOccurred:(NSError *)validationError
{
    _LOG( @"Validation Error: %@", validationError );
}

@end
