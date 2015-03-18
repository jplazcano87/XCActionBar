//
//  XCDeleteLineAction.m
//  PGXcodeActionBrowser
//
//  Created by Pedro Gomes on 17/03/2015.
//  Copyright (c) 2015 Pedro Gomes. All rights reserved.
//

#import "XCDeleteLineAction.h"

#import "XCIDEContext.h"
#import "XCIDEHelper.h"

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
@interface XCDeleteLineAction ()

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *hint;

@end

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
@implementation XCDeleteLineAction

@synthesize title, hint, subtitle;

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
- (instancetype)init
{
    if((self = [super init])) {
        self.title    = @"Delete Line(s)";
        self.subtitle = @"";
    }
    return self;
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
- (BOOL)executeWithContext:(id<XCIDEContext>)context
{
    NSTextView *textView = context.sourceCodeTextView;

    NSRange rangeForSelectedText  = [context retrieveTextSelectionRange];
    NSRange lineRangeForSelection = [textView.string lineRangeForRange:rangeForSelectedText];

    [textView.textStorage beginEditing];
    
    [textView insertText:@"" replacementRange:lineRangeForSelection];

    [textView.textStorage endEditing];

    return YES;
}

@end