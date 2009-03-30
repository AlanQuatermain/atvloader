//
//  ATVRebootWarningController.m
//  AwkwardTV
//
//  Created by Alan Quatermain on 16/04/07.
//  Copyright 2007 AwkwardTV. All rights reserved.
//

#import "ATVRebootWarningController.h"
#import "BackRowUtils.h"
#import <BackRow/BackRow.h>

@implementation ATVRebootWarningController

- (void) dealloc
{
    [_header dealloc];
    [_message dealloc];
    [_button dealloc];

    [super dealloc];
}

- (void) setTitle: (NSString *) title
{
    if ( _header == nil )
    {
        _header = [[BRHeaderControl alloc] initWithScene: [self scene]];
        [self addControl: _header];
    }

    [_header setTitle: title];
}

- (NSString *) title
{
    return ( [_header title] );
}

- (void) setMessage: (NSString *) message
{
    if ( _message == nil )
    {
        _message = [[BRTextControl alloc] initWithScene: [self scene]];
        [self addControl: _message];
    }

    [_message setTextAttributes: [[BRThemeInfo sharedTheme] paragraphTextAttributes]];
    [_message setText: message];
}

- (NSString *) message
{
    return ( [_message text] );
}

- (void) setButtonTitle: (NSString *) title
                 action: (SEL) action
                 target: (id) target
{
    if ( _button == nil )
    {
        _button = [[BRButtonControl alloc] initWithScene: [self scene]
                                         masterLayerSize: [[self masterLayer] frame].size];
        [self addControl: _button];
    }

    [_button setTitle: title];
    [_button setAction: action];
    [_button setTarget: target];
}

- (NSString *) buttonTitle
{
    return ( [_button title] );
}

- (SEL) buttonAction
{
    return ( [_button action] );
}

- (id) buttonTarget
{
    return ( [_button target] );
}

- (void) doLayout
{
    NSRect masterFrame = [[self masterLayer] frame];
    NSRect frame = masterFrame;

    // these are all setup pretty much the same as the download
    // controller
    if ( _header != nil )
    {
        frame.origin.y = frame.size.height * 0.82f;
        frame.size.height = [[BRThemeInfo sharedTheme] listIconHeight];
        [_header setFrame: frame];
    }

    if ( _message != nil )
    {
        [_message setMaximumSize: NSMakeSize(masterFrame.size.width * 0.66f,
                                             masterFrame.size.height)];
        frame.size = [_message renderedSize];
        frame.origin.x = (masterFrame.size.width - frame.size.width) * 0.5f;
        frame.origin.y = (masterFrame.size.height * 0.75f) - frame.size.height;
        [_message setFrame: frame];
    }

    if ( _button != nil )
    {
        // one-eighth of the way up the screen
        [_button setYPosition: masterFrame.origin.y +
         (masterFrame.size.height * (1.0f / 8.0f))];
    }
}

@end
