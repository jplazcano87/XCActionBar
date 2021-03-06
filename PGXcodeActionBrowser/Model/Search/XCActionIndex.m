//
//  XCActionIndex.m
//  XCActionBar
//
//  Created by Pedro Gomes on 11/03/2015.
//  Copyright (c) 2015 Pedro Gomes. All rights reserved.
//

#import "XCUtils.h"

#import "XCActionProvider.h"
#import "XCActionIndex.h"
#import "XCActionInterface.h"

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
@interface XCActionIndex () <XCActionProviderDelegate>

@property (nonatomic, strong) dispatch_queue_t      indexerQueue;
@property (nonatomic, strong) NSMutableDictionary   *providers;
@property (nonatomic, strong) NSArray               *index;

@end

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
@implementation XCActionIndex

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
- (instancetype)init
{
    if((self = [super init])) {
        self.indexerQueue = dispatch_queue_create("org.pedrogomes.XCActionBar.ActionIndexer", DISPATCH_QUEUE_CONCURRENT);
        self.providers    = [NSMutableDictionary dictionary];
    }
    return self;
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
- (id<NSCopying>)registerProvider:(id<XCActionProvider>)provider
{
    NSString *token = [[NSUUID UUID] UUIDString];

    @synchronized(self) {
        self.providers[token] = provider;
    }
    
    return token;
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
- (void)deregisterProvider:(id<NSCopying>)providerToken;
{
    @synchronized(self) {
        [self.providers removeObjectForKey:providerToken];
    }
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
- (void)updateWithCompletionHandler:(PGGeneralCompletionHandler)completionHandler
{
    ////////////////////////////////////////////////////////////////////////////////
    // Build All Actions
    ////////////////////////////////////////////////////////////////////////////////
    dispatch_group_t group = dispatch_group_create();
    
    for(id<XCActionProvider> provider in [self.providers allValues]) {
        dispatch_group_enter(group);
        
        [provider prepareActionsOnQueue:self.indexerQueue completionHandler:^{
            dispatch_group_leave(group);
        }];
    }

    ////////////////////////////////////////////////////////////////////////////////
    // When done, collect all actions into our internal index
    ////////////////////////////////////////////////////////////////////////////////
    XCDeclareWeakSelf(weakSelf);

    dispatch_group_enter(group);
    dispatch_barrier_async(self.indexerQueue, ^{
        [weakSelf rebuildIndex];
        dispatch_group_leave(group);
    });
    
    dispatch_group_notify(group, dispatch_get_main_queue(), completionHandler);
}

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
- (NSArray *)lookup:(NSString *)query
{
    NSArray *queryComponents       = [query componentsSeparatedByString:@" "];
    NSUInteger queryComponentCount = queryComponents.count;
    
    ////////////////////////////////////////////////////////////////////////////////
    // this is highly inefficient - obviously just a first pass to get the core feature working
    ////////////////////////////////////////////////////////////////////////////////
    NSMutableArray *matches = [NSMutableArray array];

    for(id<XCActionInterface> action in self.index) {

        NSString *stringToMatch = action.title;

        ////////////////////////////////////////////////////////////////////////////////
        // Search Title and Title's subwords
        ////////////////////////////////////////////////////////////////////////////////
        BOOL        foundMatch    = NO;
        NSUInteger  matchLocation = 0;

        while(query.length <= stringToMatch.length) {
            NSRange range = [stringToMatch rangeOfString:query
                                                 options:(NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch)
                                                   range:NSMakeRange(0, query.length)];
            if(range.location != NSNotFound) {
                [matches addObject:action];
                action.searchQueryMatchRanges = @[[NSValue valueWithRange:NSMakeRange(matchLocation, query.length)]];
                foundMatch = YES;
                break;
            }
            NSRange rangeForNextMatch = [stringToMatch rangeOfString:@" "];
            if(rangeForNextMatch.location == NSNotFound) break;
            if(rangeForNextMatch.location + 1 > stringToMatch.length) break;
            
            matchLocation += rangeForNextMatch.location + 1;
            stringToMatch = [stringToMatch substringFromIndex:rangeForNextMatch.location + 1];
        }
        
        if(foundMatch == YES) continue;
        if(queryComponentCount < 2) continue;

        ////////////////////////////////////////////////////////////////////////////////
        // Run additional sub-word prefix search
        // This allows us to match partial prefixes matches such as:
        // "Sur wi d q" would match "Surround with double quotes"
        ////////////////////////////////////////////////////////////////////////////////
        NSMutableArray *ranges  = [NSMutableArray array];

        NSArray *candidateComponents = [action.title componentsSeparatedByString:@" "];
        if(queryComponentCount > candidateComponents.count) continue;
        
        matchLocation = 0;
        
        BOOL foundPartialMatch = NO;
        for(int i = 0; i < queryComponentCount; i++) {
            foundPartialMatch = NO;
            
            NSString *subQuery = queryComponents[i];
            NSString *subMatch = candidateComponents[i];
            
            if(subQuery.length > subMatch.length) break;
            
            NSRange range = [subMatch rangeOfString:subQuery
                                            options:(NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch)
                                              range:NSMakeRange(0, subQuery.length)];
            foundPartialMatch = (range.location != NSNotFound);
            if(foundPartialMatch == NO) break;

            [ranges addObject:[NSValue valueWithRange:NSMakeRange(matchLocation, subQuery.length)]];
            matchLocation += (subMatch.length + 1);
        }
        
        if(foundPartialMatch == YES) {
            action.searchQueryMatchRanges = ranges;
            [matches addObject:action];
            continue;
        }
        
        ////////////////////////////////////////////////////////////////////////////////
        // No matches ...
        // lets try the action's group instead
        ////////////////////////////////////////////////////////////////////////////////
//        if(foundMatch == NO) {
//            if(str.length > action.group.length) continue;
//
//            NSRange range = [action.group rangeOfString:str
//                                                options:(NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch)
//                                                  range:NSMakeRange(0, str.length)];
//            if(range.location != NSNotFound) {
//                [matches addObject:action];
//            }
//        }
    }
    
    return [NSArray arrayWithArray:matches];
}

#pragma mark - PGActionProviderDelegate

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
- (void)actionProviderDidNotifyOfIndexRebuildNeeded:(id<XCActionProvider>)provider
{
    XCLog(@"<IndexRebuildNeeded>, <provider=%@>", provider);
    
    XCDeclareWeakSelf(weakSelf);
    
    void (^RegisterProviderDelegates)(id<XCActionProviderDelegate> delegate) = ^(id delegate){
        NSArray *providers = nil;
        @synchronized(self) {
            providers = [[weakSelf.providers allValues] copy];
        }

        for(id<XCActionProvider> provider in providers) {
            [provider setDelegate:delegate];
        }
    };
    
    RegisterProviderDelegates(nil);
    
    [self updateWithCompletionHandler:^{
        RegisterProviderDelegates(weakSelf);
    }];
}

#pragma mark - Helpers

////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
- (void)rebuildIndex
{
    NSArray *providers = nil;
    @synchronized(self) {
        providers = [[self.providers allValues] copy];
    }
    
    NSMutableArray *actionIndex = [NSMutableArray array];
    for(id<XCActionProvider> provider in providers) { @autoreleasepool {
//        NSString *hashForProvider = XCHashObject(provider);
        NSArray  *actions         = [provider findAllActions];
//        for(id action in actions) {
//            NSString *hashForAction = XCHashObject(action);
//            XCLog(@"<action=%@>, <hash=%@>", action, hashForAction);
//        }
        
        [actionIndex addObjectsFromArray:actions];
    }}
    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"title" ascending:YES];
    [actionIndex sortUsingDescriptors:@[sortDescriptor]];
    
    self.index = [NSArray arrayWithArray:actionIndex];;
}

@end
