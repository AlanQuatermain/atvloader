//
//  ATVPluginInfoController.m
//  AwkwardTV
//
//  Created by Alan Quatermain on 08/04/07.
//  Copyright 2007 AwkwardTV. All rights reserved.
//

#import "ATVPluginInfoController.h"
#import "ATVLogger.h"
#import "BackRowUtils.h"
#import <BackRow/BackRow.h>

static float spacerRatio = 0.019999999552965164f;
static float imageHeightRatio = 0.2f;

@interface BRVerticalScrollControl (AlanQuatermain_GetParagraphTextObject)

- (void) __quatermain_setParagraphAttributedString: (NSAttributedString *) string;

@end

@implementation BRVerticalScrollControl (AlanQuatermain_GetParagraphTextObject)

- (void) __quatermain_setParagraphAttributedString: (NSAttributedString *) string
{
    [_paragraphText setAttributedString: string];
    [self _updateScrollArrows];
}

@end

#pragma mark -

@interface ATVPluginInfoController (Private)

- (NSAttributedString *) _buildDocumentContentFromPluginInfo: (NSDictionary *) info;
- (NSSize) _scrollSizeForMasterFrame: (NSRect) masterFrame;
- (float) _imageHeightForMasterFrame: (NSRect) masterFrame;

@end

@implementation ATVPluginInfoController

+ (NSString *) controllerLabel
{
    return ( @"org.awkwardtv.loader.plugininfo" );
}

- (id) initWithScene: (BRRenderScene *) scene
{
    if ( [super initWithScene: scene] == nil )
        return ( nil );

    // this is the only 'required' component
    _document = [[BRVerticalScrollControl alloc] initWithScene: scene];

    [self addLabel: [ATVPluginInfoController controllerLabel]];

    return ( self );
}

- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver: self];

    [_header release];
    [_image release];
    [_document release];
    [_button release];

    [super dealloc];
}

- (NSDictionary *) pluginDownloadInfo
{
    id obj = [_pluginInfo objectForKey: @"enclosure"];

    if ( (obj == nil) || ([obj isKindOfClass: [NSDictionary class]] == NO) )
        return ( nil );

    return ( obj );
}

- (void) setHeaderTitle: (NSString *) title
{
    if ( _header == nil )
        _header = [[BRHeaderControl controlWithScene: [self scene]] retain];

    [_header setTitle: title];
}

- (void) setHeaderIcon: (BRTexture *) icon
      horizontalOffset: (float) hOffset
         kerningFactor: (float) kerning
{
    if ( _header == nil )
        _header = [[BRHeaderControl controlWithScene: [self scene]] retain];

    [_header setIcon: icon horizontalOffset: hOffset kerningFactor: kerning];
}

- (void) setImage: (CGImageRef) image
{
    if ( _image == nil )
        _image = [[BRImageControl alloc] initWithScene: [self scene]];

    float maxImageHeight = [self _imageHeightForMasterFrame: [[self masterLayer] frame]];
    float imageHeight = (float) CGImageGetHeight( image );

    if ( imageHeight > maxImageHeight )
    {
        // downsample the image to a smaller size
        NSSize smaller = { 0.0f, maxImageHeight };
        float ratio = imageHeight / maxImageHeight;
        smaller.width = ((float) CGImageGetWidth(image)) / ratio;

        [_image setImage: image downsampleTo: smaller];
    }
    else
    {
        [_image setImage: image];
    }
}

- (void) setImage: (CGImageRef) image downsampleTo: (NSSize) size
{
    if ( _image == nil )
        _image = [[BRImageControl alloc] initWithScene: [self scene]];

    float maxImageHeight = [self _imageHeightForMasterFrame: [[self masterLayer] frame]];
    float imageHeight = (float) CGImageGetHeight( image );

    if ( imageHeight > maxImageHeight )
    {
        // downsample the image to a smaller size
        NSSize smaller = { 0.0f, maxImageHeight };
        float ratio = imageHeight / maxImageHeight;
        smaller.width = ((float) CGImageGetWidth(image)) / ratio;

        [_image setImage: image downsampleTo: smaller];
    }
    else
    {
        [_image setImage: image downsampleTo: size];
    }
}

- (void) setImageReflectionAmount: (float) amount
{
    if ( _image == nil )
        _image = [[BRImageControl alloc] initWithScene: [self scene]];

    [_image setReflectionAmount: amount];
}

- (void) setImageReflectionOffset: (float) offset
{
    if ( _image == nil )
        _image = [[BRImageControl alloc] initWithScene: [self scene]];

    [_image setReflectionOffset: offset];
}

- (void) setPluginInfo: (NSDictionary *) info
{
    NSRect scrollFrame = [_document frame];
    NSRect masterFrame = [[self masterLayer] frame];

    scrollFrame.size = [self _scrollSizeForMasterFrame: masterFrame];
    [_document setFrame: scrollFrame];

    NSAttributedString * string = [self _buildDocumentContentFromPluginInfo: info];
    if ( string != nil )
        [_document __quatermain_setParagraphAttributedString: string];

    _pluginInfo = [info retain];
}

- (void) setButtonTitle: (NSString *) title action: (SEL) action target: (id) target
{
    if ( _button == nil )
        _button = [[BRButtonControl alloc] initWithScene: [self scene]
                                         masterLayerSize: [[self masterLayer] frame].size];

    [_button setTitle: title];
    [_button setAction: action];
    [_button setTarget: target];
}

- (void) doLayout
{
    NSRect masterFrame = [[self masterLayer] frame];

    float spacer = masterFrame.size.height * spacerRatio;
    float nextYOffset = 0.0f;

    if ( _header != nil )
    {
        NSRect centerRect = [[BRThemeInfo sharedTheme]
                             centeredMenuHeaderFrameForMasterFrame: masterFrame];
        [_header setFrame: centerRect];
        [self addControl: _header];

        nextYOffset = centerRect.origin.y - spacer;
    }

    if ( _image != nil )
    {
        NSRect imageFrame;
        imageFrame.size = [_image pixelBounds];
        if ( imageFrame.size.height > 0.0f )
        {
            imageFrame.origin.x = (masterFrame.size.width / 2.0f) - (imageFrame.size.width / 2.0f);
        }
        else
        {
            imageFrame.size.height = [self _imageHeightForMasterFrame: masterFrame];
            imageFrame.origin.x = (masterFrame.size.width / 5.0f) * 2.0f;
        }

        imageFrame.origin.y = nextYOffset - imageFrame.size.height;

        [_image setFrame: imageFrame];
        [self addControl: _image];

        nextYOffset = imageFrame.origin.y - spacer;
    }

    if ( _document != nil )
    {
        NSRect scrollFrame;
        scrollFrame.size = [self _scrollSizeForMasterFrame: masterFrame];
        scrollFrame.origin.x = (masterFrame.size.width - scrollFrame.size.width) * 0.5f;
        scrollFrame.origin.y = nextYOffset - scrollFrame.size.height;

        [_document setFrame: scrollFrame];
        [self addControl: _document];

        nextYOffset = scrollFrame.origin.y - spacer;
    }

    if ( _button != nil )
    {
        NSRect buttonFrame = [_button frame];
        [_button setYPosition: nextYOffset - buttonFrame.size.height];
        [self addControl: _button];
    }

    if ( _document == nil )
        return;

    NSRect docFrame = [_document frame];
    NSRect textFrame = [_document paragraphTextFrame];
    float scrollerOffset = (textFrame.size.width * 0.5f) + docFrame.origin.x;

    if ( _header != nil )
    {
        NSRect headerFrame = [_header frame];
        headerFrame.origin.x += (headerFrame.size.width * -0.5f) + scrollerOffset;
        [_header setFrame: headerFrame];
    }

    if ( _image != nil )
    {
        NSRect imageFrame = [_image frame];
        imageFrame.origin.x = (imageFrame.size.width * -0.5f) + scrollerOffset;
        [_image setFrame: imageFrame];
    }

    if ( _button != nil )
    {
        NSRect buttonFrame = [_button frame];
        buttonFrame.origin.x = (buttonFrame.size.width * -0.5f) + scrollerOffset;
        [_button setFrame: buttonFrame];
    }
}

@end

@implementation ATVPluginInfoController (Private)

#define APPEND_STRING(str, attr) \
    { \
        NSAttributedString * a = [[NSAttributedString alloc] initWithString: str attributes: attr]; \
        [content appendAttributedString: a]; \
        [a release]; \
    }

- (NSAttributedString *) _buildDocumentContentFromPluginInfo: (NSDictionary *) info
{
    // I would be putting some things in bold, but it turns out
    // paragraphs are rendered using LucidaGrande-Bold already, doh
    NSMutableDictionary * boldAttrs = [[[BRThemeInfo sharedTheme] paragraphTextAttributes] mutableCopy];
    NSMutableDictionary * plainAttrs;

    ATVDebugLog( @"Got text attributes: %@", boldAttrs );

    // set our attributes to natural alignment rather than centered
    [boldAttrs setObject: [NSNumber numberWithInt: NSNaturalTextAlignment]
                  forKey: @"CTTextAlignment"];
    [boldAttrs setObject: [NSNumber numberWithInt: NSLineBreakByWordWrapping]
                  forKey: @"CTLineBreakMode"];

    ATVDebugLog( @"Modified text attributes: %@", boldAttrs );

    // now copy this to form the basis of some non-bold attributes
    plainAttrs = [boldAttrs mutableCopy];

    // change the font there to one which isn't bold
    // this set of attributes
    [plainAttrs setObject: [[[BRThemeInfo sharedTheme] iconMessageBodyAttributes]
                            objectForKey: @"NSFont"]
                   forKey: @"NSFont"];

    ATVDebugLog( @"Plain text attributes: %@", plainAttrs );

    NSDictionary * localized = [info objectForKey: @"info"];

    ATVDebugLog( @"In _buildDocumentContentFromPluginInfo:" );

    NSMutableAttributedString * content = [[NSMutableAttributedString alloc] init];
    id obj;
    NSString * spacer = @"";

    obj = [localized objectForKey: @"subtitle"];
    if ( obj != nil )
    {
        ATVDebugLog( @"Adding subtitle '%@'", obj );
        APPEND_STRING(obj, boldAttrs);
        spacer = @"\n\n";
    }

    obj = [info objectForKey: @"category"];
    if ( obj != nil )
    {
        ATVDebugLog( @"Adding category '%@'", obj );
        NSString * str = [NSString stringWithFormat: @"%@%@: ", spacer,
                          BRLocalizedString(@"Category", @"'category' plugin info leader")];
        APPEND_STRING(str, boldAttrs);
        APPEND_STRING(obj, plainAttrs);
        spacer = @"\n";
    }

    obj = [info objectForKey: @"author"];
    if ( obj != nil )
    {
        ATVDebugLog( @"Adding author '%@'", obj );
        NSString * str = [NSString stringWithFormat: @"%@%@: ", spacer,
                          BRLocalizedString(@"Author", @"'author' plugin info leader")];
        APPEND_STRING(str, boldAttrs);
        APPEND_STRING(obj, plainAttrs);
        spacer = @"\n";
    }

    obj = [info objectForKey: @"version"];
    if ( obj != nil )
    {
        ATVDebugLog( @"Adding version '%@'", obj );
        NSString * str = [NSString stringWithFormat: @"%@%@: ", spacer,
                          BRLocalizedString(@"Version", @"'version' plugin info leader")];
        APPEND_STRING(str, boldAttrs);
        APPEND_STRING(obj, plainAttrs);
        spacer = @"\n";
    }

    obj = [info objectForKey: @"pubDate"];
    if ( obj != nil )
    {
        ATVDebugLog( @"Adding pubDate '%@'", obj );
        NSString * str = [NSString stringWithFormat: @"%@%@: ", spacer,
                          BRLocalizedString(@"Last Updated", @"'pubDate' plugin info leader")];
        APPEND_STRING(str, boldAttrs);

        str = [NSString stringWithFormat: @"%@", obj];
        APPEND_STRING(str, plainAttrs);
        spacer = @"\n";
    }

    obj = [info objectForKey: @"copyright"];
    if ( obj != nil )
    {
        ATVDebugLog( @"Adding copyright '%@'", obj );
        NSString * str = [NSString stringWithFormat: @"%@%@: ", spacer,
                          BRLocalizedString(@"Copyright", @"'copyright' plugin info leader")];
        APPEND_STRING(str, boldAttrs);
        APPEND_STRING(obj, plainAttrs);
        spacer = @"\n";
    }

    obj = [info objectForKey: @"license"];
    if ( obj != nil )
    {
        ATVDebugLog( @"Adding license '%@'", obj );
        NSString * str = [NSString stringWithFormat: @"%@%@: ", spacer,
                          BRLocalizedString(@"License", @"'license' plugin info leader")];
        APPEND_STRING(str, boldAttrs);
        APPEND_STRING(obj, plainAttrs);
        spacer = @"\n";
    }

    obj = [info objectForKey: @"url"];
    if ( obj != nil )
    {
        ATVDebugLog( @"Adding url '%@'", obj );
        NSString * str = [NSString stringWithFormat: @"%@%@: ", spacer,
                          BRLocalizedString(@"Author's URL", @"'url' plugin info leader")];
        APPEND_STRING(str, boldAttrs);
        APPEND_STRING(obj, plainAttrs);
        spacer = @"\n";
    }

    if ( content != nil )
        spacer = @"\n\n";

    obj = [localized objectForKey: @"summary"];
    if ( obj != nil )
    {
        ATVDebugLog( @"Adding summary '%@'", obj );
        NSString * str = [NSString stringWithFormat: @"%@%@", spacer, obj];
        APPEND_STRING(str, plainAttrs);
        spacer = @"\n\n";
    }

    obj = [localized objectForKey: @"description"];
    if ( obj != nil )
    {
        ATVDebugLog( @"Adding description '%@'", obj );
        NSString * str = [NSString stringWithFormat: @"%@%@", spacer, obj];
        APPEND_STRING(str, plainAttrs);
    }

    // remember to release our custom attributes
    [boldAttrs release];
    [plainAttrs release];

    return ( [content autorelease] );
}

- (NSSize) _scrollSizeForMasterFrame: (NSRect) frame
{
    // gleaned from BRDocumentController -- these values are probably
    // compile-time calculations, i.e. "4.0f / 1.839f" in code.
    NSSize result = NSMakeSize(frame.size.width * 0.723f, //0.7229999899864197f,
                               frame.size.height * 0.57f); //0.5699999928474426f);

    if ( _image != nil )
    {
        result.height -= [self _imageHeightForMasterFrame: frame];
        result.height -= frame.size.height * spacerRatio;
    }

    return ( result );
}

- (float) _imageHeightForMasterFrame: (NSRect) frame
{
    return ( ceilf(frame.size.height * imageHeightRatio) );
}

@end
