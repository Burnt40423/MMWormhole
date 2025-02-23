//
// MMWormhole.m
//
// Copyright (c) 2014 Mutual Mobile (http://www.mutualmobile.com/)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "MMWormhole.h"

#if !__has_feature(objc_arc)
#error This class requires automatic reference counting
#endif

#include <CoreFoundation/CoreFoundation.h>

NS_ASSUME_NONNULL_BEGIN

static NSString * const MMWormholeNotificationName = @"MMWormholeNotificationName";

void wormholeNotificationCallback(CFNotificationCenterRef center,
                                  void * observer,
                                  CFStringRef name,
                                  void const * object,
                                  CFDictionaryRef userInfo);

@interface MMWormhole ()

@property (nonatomic, strong) NSMutableDictionary *listenerBlocks;

@end

@implementation MMWormhole

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

- (id)init {
    return nil;
}

#pragma clang diagnostic pop

- (instancetype)initWithApplicationGroupIdentifier:(nullable NSString *)identifier
                                 optionalDirectory:(nullable NSString *)directory {
    if ((self = [super init])) {
        
        if (NO == [[NSFileManager defaultManager] respondsToSelector:@selector(containerURLForSecurityApplicationGroupIdentifier:)]) {
            //Protect the user of a crash because of iOSVersion < iOS7
            return nil;
        }
        
        self.wormholeMessenger = [[MMWormholeFileTransiting alloc] initWithApplicationGroupIdentifier:[identifier copy]
                                                                                    optionalDirectory:[directory copy]];

        _listenerBlocks = [NSMutableDictionary dictionary];
        
        // Only respects notification coming from self.
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didReceiveMessageNotification:)
                                                     name:MMWormholeNotificationName
                                                   object:self];
    }
    
    return self;
}

- (instancetype)initWithApplicationGroupIdentifier:(nullable NSString *)identifier
                                 optionalDirectory:(nullable NSString *)directory
                                    transitingType:(MMWormholeTransitingType)transitingType {
    if ((self = [self initWithApplicationGroupIdentifier:identifier optionalDirectory:directory])) {
        switch (transitingType) {
            case MMWormholeTransitingTypeFile:
                // Default
                break;
            case MMWormholeTransitingTypeCoordinatedFile:
                self.wormholeMessenger = [[MMWormholeCoordinatedFileTransiting alloc] initWithApplicationGroupIdentifier:identifier
                                                                                                       optionalDirectory:directory];
                break;
            case MMWormholeTransitingTypeManifestFile:
                self.wormholeMessenger = [[MMWormholeManifestFileTransiting alloc] initWithApplicationGroupIdentifier:identifier
                                                                                                    optionalDirectory:directory];
                break;
            case MMWormholeTransitingTypeSessionContext:
#if ( defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 90000 )
                self.wormholeMessenger = [[MMWormholeSessionContextTransiting alloc] initWithApplicationGroupIdentifier:identifier
                                                                                                      optionalDirectory:directory];
#endif
                break;
            case MMWormholeTransitingTypeSessionFile:
#if ( defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 90000 )
                self.wormholeMessenger = [[MMWormholeSessionFileTransiting alloc] initWithApplicationGroupIdentifier:identifier
                                                                                                   optionalDirectory:directory];
#endif
                break;
            case MMWormholeTransitingTypeSessionMessage:
#if ( defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 90000 )
                self.wormholeMessenger = [[MMWormholeSessionMessageTransiting alloc] initWithApplicationGroupIdentifier:identifier
                                                                                                      optionalDirectory:directory];
#endif
                break;
            default:
                break;
        }
    }
    
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    CFNotificationCenterRef const center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterRemoveEveryObserver(center, (__bridge const void *)(self));
}


#pragma mark - Private Notification Methods

- (void)sendNotificationForMessageWithIdentifier:(nullable NSString *)identifier {
    CFNotificationCenterRef const center = CFNotificationCenterGetDarwinNotifyCenter();
    CFDictionaryRef const userInfo = NULL;
    BOOL const deliverImmediately = YES;
    CFStringRef str = (__bridge CFStringRef)identifier;
    CFNotificationCenterPostNotification(center, str, NULL, userInfo, deliverImmediately);
}

- (void)registerForNotificationsWithIdentifier:(nullable NSString *)identifier {
    [self unregisterForNotificationsWithIdentifier:identifier];
    
    CFNotificationCenterRef const center = CFNotificationCenterGetDarwinNotifyCenter();
    CFStringRef str = (__bridge CFStringRef)identifier;
    CFNotificationCenterAddObserver(center,
                                    (__bridge const void *)(self),
                                    wormholeNotificationCallback,
                                    str,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}

- (void)unregisterForNotificationsWithIdentifier:(nullable NSString *)identifier {
    CFNotificationCenterRef const center = CFNotificationCenterGetDarwinNotifyCenter();
    CFStringRef str = (__bridge CFStringRef)identifier;
    CFNotificationCenterRemoveObserver(center,
                                       (__bridge const void *)(self),
                                       str,
                                       NULL);
}

void wormholeNotificationCallback(CFNotificationCenterRef center,
                               void * observer,
                               CFStringRef name,
                               void const * object,
                               CFDictionaryRef userInfo) {
    NSString *identifier = (__bridge NSString *)name;
    NSObject *sender = (__bridge NSObject *)(observer);
    [[NSNotificationCenter defaultCenter] postNotificationName:MMWormholeNotificationName
                                                        object:sender
                                                      userInfo:@{@"identifier" : identifier}];
}

- (void)didReceiveMessageNotification:(NSNotification *)notification {
    NSDictionary *userInfo = notification.userInfo;
    NSString *identifier = [userInfo valueForKey:@"identifier"];
    
    if (identifier != nil) {
#if ( defined(__IPHONE_OS_VERSION_MAX_ALLOWED) && __IPHONE_OS_VERSION_MAX_ALLOWED >= 90000 && !TARGET_OS_SIMULATOR )
        if ([self.wormholeMessenger respondsToSelector:@selector(numberOfMessageItemsforIdentifier:)]) {
            NSInteger messageCount = [self.wormholeMessenger numberOfMessageItemsforIdentifier:identifier];
            for (int i = 0; i < messageCount; i++) {
                [self _sendNotificationForIdentifier:identifier];
            }
            return;
        }
#endif
        [self _sendNotificationForIdentifier:identifier];
    }
}

- (void)_sendNotificationForIdentifier:(NSString *)identifier {
    id messageObject = [self.wormholeMessenger messageObjectForIdentifier:identifier];
    [self notifyListenerForMessageWithIdentifier:identifier message:messageObject];
}

- (id)listenerBlockForIdentifier:(NSString *)identifier {
    return [self.listenerBlocks valueForKey:identifier];
}

- (void)notifyListenerForMessageWithIdentifier:(nullable NSString *)identifier message:(nullable id<NSCoding>)message {
    typedef void (^MessageListenerBlock)(id messageObject);

    MessageListenerBlock listenerBlock = [self listenerBlockForIdentifier:identifier];
    
    if (listenerBlock) {
        dispatch_async(dispatch_get_main_queue(), ^{
            listenerBlock(message);
        });
    }
}


#pragma mark - Public Interface Methods

- (void)passMessageObject:(nullable id <NSCoding>)messageObject identifier:(nullable NSString *)identifier {
    if ([self.wormholeMessenger writeMessageObject:messageObject forIdentifier:identifier]) {
        [self sendNotificationForMessageWithIdentifier:identifier];
    }
}


- (nullable id)messageWithIdentifier:(nullable NSString *)identifier {
    id messageObject = [self.wormholeMessenger messageObjectForIdentifier:identifier];
    
    return messageObject;
}

- (void)clearMessageContentsForIdentifier:(nullable NSString *)identifier {
    [self.wormholeMessenger deleteContentForIdentifier:identifier];
}

- (void)clearAllMessageContents {
    [self.wormholeMessenger deleteContentForAllMessages];
}

- (void)listenForMessageWithIdentifier:(nullable NSString *)identifier
                              listener:(nullable void (^)(__nullable id messageObject))listener {
    if (identifier != nil) {
        [self.listenerBlocks setValue:listener forKey:identifier];
        [self registerForNotificationsWithIdentifier:identifier];
    }
}

- (void)stopListeningForMessageWithIdentifier:(nullable NSString *)identifier {
    if (identifier != nil) {
        [self.listenerBlocks setValue:nil forKey:identifier];
        [self unregisterForNotificationsWithIdentifier:identifier];
    }
}

@end

NS_ASSUME_NONNULL_END
