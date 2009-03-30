//
//  ATVLogger.h
//  AwkwardTV
//
//  Created by Alan Quatermain on 30/04/07.
//  Copyright 2007 AwkwardTV. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <stdarg.h>
#import <syslog.h>

@interface ATVLogger : NSObject
{
    int         _level;     // as in syslog.h
    NSString *  _path;
}

+ (ATVLogger *) log;

- (id) initWithAppName: (NSString *) name;
- (void) dealloc;

- (void) setLogLevel: (int) level;
- (int) logLevel;

- (void) appendLogEntry: (NSString *) format level: (int) level, ...;
- (void) appendLogEntry: (NSString *) format level: (int) level arguments: (va_list) args;

- (void) emptyLog;

- (NSString *) logPath;

@end

#define ATVDebugLog(msg, args...) [[ATVLogger log] appendLogEntry: msg level: LOG_DEBUG, ##args]
#define ATVErrorLog(msg, args...) [[ATVLogger log] appendLogEntry: msg level: LOG_ERR, ##args]
#define ATVLog(msg, args...) [[ATVLogger log] appendLogEntry: msg level: LOG_INFO, ##args]
#define ATVSystemLog(level, msg, args...) [[ATVLogger log] appendLogEntry: msg level: level, ##args]
