//
//  RNFetchBlobNetwork.m
//  RNFetchBlob
//
//  Created by wkh237 on 2016/6/6.
//  Copyright © 2016 wkh237. All rights reserved.
//


#import <Foundation/Foundation.h>
#import "RNFetchBlobNetwork.h"

#import "RNFetchBlob.h"
#import "RNFetchBlobConst.h"
#import "RNFetchBlobProgress.h"

#if __has_include(<React/RCTAssert.h>)
#import <React/RCTRootView.h>
#import <React/RCTLog.h>
#import <React/RCTEventDispatcher.h>
#import <React/RCTBridge.h>
#else
#import "RCTRootView.h"
#import "RCTLog.h"
#import "RCTEventDispatcher.h"
#import "RCTBridge.h"
#endif

////////////////////////////////////////
//
//  HTTP request handler
//
////////////////////////////////////////

NSMapTable * expirationTable;

__attribute__((constructor))
static void initialize_tables() {
    if (expirationTable == nil) {
        expirationTable = [[NSMapTable alloc] init];
    }
}


@implementation RNFetchBlobNetwork


- (id)init {
    self = [super init];
    if (self) {
//        self.requestsTable = [NSMapTable mapTableWithKeyOptions:NSMapTableStrongMemory valueOptions:NSMapTableWeakMemory];
        
        self.taskQueue = [[NSOperationQueue alloc] init];
        self.taskQueue.qualityOfService = NSQualityOfServiceUtility;
        self.taskQueue.maxConcurrentOperationCount = 10;
        self.rebindProgressDict = [NSMutableDictionary dictionary];
        self.rebindUploadProgressDict = [NSMutableDictionary dictionary];
        self.requestDict = [NSMutableDictionary dictionary];
    }
    
    return self;
}

- (void)dealloc {
    [self.requestDict removeAllObjects];
}

+ (RNFetchBlobNetwork* _Nullable)sharedInstance {
    static id _sharedInstance = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        _sharedInstance = [[self alloc] init];
    });
    
    return _sharedInstance;
}

- (void) sendRequest:(__weak NSDictionary  * _Nullable )options
       contentLength:(long) contentLength
              bridge:(RCTBridge * _Nullable)bridgeRef
              taskId:(NSString * _Nullable)taskId
         withRequest:(__weak NSURLRequest * _Nullable)req
            callback:(_Nullable RCTResponseSenderBlock) callback
{
    RNFetchBlobRequest *request = [[RNFetchBlobRequest alloc] init];
    [request sendRequest:options
           contentLength:contentLength
                  bridge:bridgeRef
                  taskId:taskId
             withRequest:req
      taskOperationQueue:self.taskQueue
                callback:callback];
    
    @synchronized([RNFetchBlobNetwork class]) {
        [self.requestDict setObject:request forKey:taskId];
        [self checkProgressConfig];
    }
}

- (void) checkProgressConfig {
    //reconfig progress
    [self.rebindProgressDict enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, RNFetchBlobProgress * _Nonnull config, BOOL * _Nonnull stop) {
        [self enableProgressReport:key config:config];
    }];
    [self.rebindProgressDict removeAllObjects];
    
    //reconfig uploadProgress
    [self.rebindUploadProgressDict enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, RNFetchBlobProgress * _Nonnull config, BOOL * _Nonnull stop) {
        [self enableUploadProgress:key config:config];
    }];
    [self.rebindUploadProgressDict removeAllObjects];
}

- (void) enableProgressReport:(NSString *) taskId config:(RNFetchBlobProgress *)config
{
    if (config) {
        @synchronized ([RNFetchBlobNetwork class]) {
            if (![self.requestDict objectForKey:taskId]) {
                [self.rebindProgressDict setValue:config forKey:taskId];
            } else {
                [self.requestDict objectForKey:taskId].progressConfig = config;
            }
        }
    }
}

- (void) enableUploadProgress:(NSString *) taskId config:(RNFetchBlobProgress *)config
{
    if (config) {
        @synchronized ([RNFetchBlobNetwork class]) {
            if (![self.requestDict objectForKey:taskId]) {
                [self.rebindUploadProgressDict setValue:config forKey:taskId];
            } else {
                [self.requestDict objectForKey:taskId].uploadProgressConfig = config;
            }
        }
    }
}

- (void) cancelRequest:(NSString *)taskId
{
    NSURLSessionDataTask * task;
    
    @synchronized ([RNFetchBlobNetwork class]) {
        task = [self.requestDict objectForKey:taskId].task;
    }
    
    if (task && task.state == NSURLSessionTaskStateRunning) {
        [task cancel];
        [self.requestDict removeObjectForKey:taskId];
    }
}

// removing case from headers
+ (NSMutableDictionary *) normalizeHeaders:(NSDictionary *)headers
{
    NSMutableDictionary * mheaders = [[NSMutableDictionary alloc]init];
    for (NSString * key in headers) {
        [mheaders setValue:[headers valueForKey:key] forKey:[key lowercaseString]];
    }
    
    return mheaders;
}

// #115 Invoke fetch.expire event on those expired requests so that the expired event can be handled
+ (void) emitExpiredTasks
{
    @synchronized ([RNFetchBlobNetwork class]){
        NSEnumerator * emu =  [expirationTable keyEnumerator];
        NSString * key;
        
        while ((key = [emu nextObject]))
        {
            RCTBridge * bridge = [RNFetchBlob getRCTBridge];
            id args = @{ @"taskId": key };
            [bridge.eventDispatcher sendDeviceEventWithName:EVENT_EXPIRE body:args];
            
        }
        
        // clear expired task entries
        [expirationTable removeAllObjects];
        expirationTable = [[NSMapTable alloc] init];
    }
}

@end
