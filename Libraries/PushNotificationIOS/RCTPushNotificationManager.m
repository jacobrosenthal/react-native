/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "RCTPushNotificationManager.h"

#import "RCTBridge.h"
#import "RCTEventDispatcher.h"
#import "RCTConvert.h"

#if __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_8_0

#define UIUserNotificationTypeAlert UIRemoteNotificationTypeAlert
#define UIUserNotificationTypeBadge UIRemoteNotificationTypeBadge
#define UIUserNotificationTypeSound UIRemoteNotificationTypeSound
#define UIUserNotificationTypeNone  UIRemoteNotificationTypeNone
#define UIUserNotificationType      UIRemoteNotificationType

#endif

NSString *const RCTLocalNotificationReceived = @"LocalNotificationReceived";
NSString *const RCTRemoteNotificationReceived = @"RemoteNotificationReceived";
NSString *const RCTRemoteNotificationsRegistered = @"RemoteNotificationsRegistered";

@implementation RCTPushNotificationManager
{
  NSDictionary *_initialNotification;
}

RCT_EXPORT_MODULE()

@synthesize bridge = _bridge;

- (instancetype)init
{
  if ((self = [super init])) {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleLocalNotificationReceived:)
                                                 name:RCTLocalNotificationReceived
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleRemoteNotificationReceived:)
                                                 name:RCTRemoteNotificationReceived
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleRemoteNotificationsRegistered:)
                                                 name:RCTRemoteNotificationsRegistered
                                               object:nil];
  }
  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setBridge:(RCTBridge *)bridge
{
  _bridge = bridge;
  _initialNotification = [bridge.launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey] copy];
}

+ (void)application:(UIApplication *)application didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings
{
  if ([application respondsToSelector:@selector(registerForRemoteNotifications)]) {
    [application registerForRemoteNotifications];
  }
}

+ (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
  NSMutableString *hexString = [NSMutableString string];
  const unsigned char *bytes = [deviceToken bytes];
  for (int i = 0; i < [deviceToken length]; i++) {
    [hexString appendFormat:@"%02x", bytes[i]];
  }
  NSDictionary *userInfo = @{
    @"deviceToken" : [hexString copy]
  };
  [[NSNotificationCenter defaultCenter] postNotificationName:RCTRemoteNotificationsRegistered
                                                      object:self
                                                    userInfo:userInfo];
}

+ (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)notification
{
  [[NSNotificationCenter defaultCenter] postNotificationName:RCTRemoteNotificationReceived
                                                      object:self
                                                    userInfo:notification];
}

+ (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification
{
  NSMutableDictionary *notificationDict = [NSMutableDictionary dictionaryWithDictionary:notification.userInfo];
  [notificationDict setObject:notification.alertBody forKey:@"alertBody"];
  [[NSNotificationCenter defaultCenter] postNotificationName:RCTLocalNotificationReceived
                                                      object:self
                                                    userInfo:notificationDict];
}

- (void)handleLocalNotificationReceived:(NSNotification *)notification
{
  [_bridge.eventDispatcher sendDeviceEventWithName:@"localNotificationReceived"
                                              body:[notification userInfo]];
}

- (void)handleRemoteNotificationReceived:(NSNotification *)notification
{
  [_bridge.eventDispatcher sendDeviceEventWithName:@"remoteNotificationReceived"
                                              body:[notification userInfo]];
}

- (void)handleRemoteNotificationsRegistered:(NSNotification *)notification
{
  [_bridge.eventDispatcher sendDeviceEventWithName:@"remoteNotificationsRegistered"
                                              body:[notification userInfo]];
}

/**
 * Update the application icon badge number on the home screen
 */
RCT_EXPORT_METHOD(setApplicationIconBadgeNumber:(NSInteger)number)
{
  [UIApplication sharedApplication].applicationIconBadgeNumber = number;
}

/**
 * Get the current application icon badge number on the home screen
 */
RCT_EXPORT_METHOD(getApplicationIconBadgeNumber:(RCTResponseSenderBlock)callback)
{
  callback(@[
    @([UIApplication sharedApplication].applicationIconBadgeNumber)
  ]);
}

RCT_EXPORT_METHOD(requestPermissions:(NSDictionary *)permissions)
{
  UIUserNotificationType types = UIRemoteNotificationTypeNone;
  if (permissions) {
    if ([permissions[@"alert"] boolValue]) {
      types |= UIUserNotificationTypeAlert;
    }
    if ([permissions[@"badge"] boolValue]) {
      types |= UIUserNotificationTypeBadge;
    }
    if ([permissions[@"sound"] boolValue]) {
      types |= UIUserNotificationTypeSound;
    }
  } else {
    types = UIUserNotificationTypeAlert | UIUserNotificationTypeBadge | UIUserNotificationTypeSound;
  }

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_8_0
  id notificationSettings = [UIUserNotificationSettings settingsForTypes:types categories:nil];
  [[UIApplication sharedApplication] registerUserNotificationSettings:notificationSettings];
  [[UIApplication sharedApplication] registerForRemoteNotifications];
#else
  [[UIApplication sharedApplication] registerForRemoteNotificationTypes:types];
#endif

}

RCT_EXPORT_METHOD(checkPermissions:(RCTResponseSenderBlock)callback)
{
  NSUInteger types = 0;
  if ([UIApplication instancesRespondToSelector:@selector(currentUserNotificationSettings)]) {
    types = [[[UIApplication sharedApplication] currentUserNotificationSettings] types];
  } else {

#if __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_8_0

    types = [[UIApplication sharedApplication] enabledRemoteNotificationTypes];

#endif

  }

  NSMutableDictionary *permissions = [[NSMutableDictionary alloc] init];
  permissions[@"alert"] = @((types & UIUserNotificationTypeAlert) > 0);
  permissions[@"badge"] = @((types & UIUserNotificationTypeBadge) > 0);
  permissions[@"sound"] = @((types & UIUserNotificationTypeSound) > 0);

  callback(@[permissions]);
}

- (NSDictionary *)constantsToExport
{
  return @{
    @"initialNotification": _initialNotification ?: [NSNull null]
  };
}

- (UILocalNotification *)createNotification:(NSDictionary*)details
{
  UILocalNotification *notification = [UILocalNotification new];

  notification.fireDate = details[@"fireDate"] ? [RCTConvert NSDate:details[@"fireDate"]] : [NSDate new];
  notification.alertBody = details[@"alertBody"] ? [RCTConvert NSString:details[@"alertBody"]] : nil;
  notification.userInfo = details[@"userInfo"] ? [RCTConvert NSDictionary:details[@"userInfo"]] : nil;

  return notification;
}

RCT_EXPORT_METHOD(presentLocalNotification:(NSDictionary *)details)
{
  [[UIApplication sharedApplication] presentLocalNotificationNow:[self createNotification:details]];
}


RCT_EXPORT_METHOD(scheduleLocalNotification:(NSDictionary *)details)
{
  [[UIApplication sharedApplication] scheduleLocalNotification:[self createNotification:details]];
}

RCT_EXPORT_METHOD(cancelLocalNotifications:(NSDictionary *)properties)
{
  NSArray *scheduledNotifications = [[UIApplication sharedApplication] scheduledLocalNotifications];
  NSArray *propertyKeys = properties ? [properties allKeys] : [NSArray new];
  for (UILocalNotification *notification in scheduledNotifications) {
    bool matchesAll = true;
    NSDictionary *notificationInfo = notification.userInfo;
    for (NSString *key in propertyKeys) {
      if (![properties[key] isEqual:notificationInfo[key]]) {
        matchesAll = false;
        break;
      }
    }
    if (matchesAll) {
      [[UIApplication sharedApplication] cancelLocalNotification:notification];
    }
  }
}

@end
