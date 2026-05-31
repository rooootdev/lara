//
//  lara-Bridging-Header.h
//  lara
//

@import UIKit;
#import <Foundation/Foundation.h>

#import "darksword.h"
#import "offsets.h"
#import "utils.h"
#import "vnode.h"
#import "apfs.h"
#import "vfs.h"
#import "sbx.h"
#import "IconServices.h"
#import "rc.h"
#import "RemoteCall.h"
#import "decrypt.h"
#import "persistence.h"

#import <zlib.h>

long findcachedataoff(const char *mgkey);
void LaraClearIconCache(void);

@interface UIDevice(Private)
+ (BOOL)_hasHomeButton;
@end

void test(NSString *path);

NS_ASSUME_NONNULL_BEGIN

@interface VarCleanBridge : NSObject

+ (NSDictionary *)loadRulesNamed:(NSString *)resourceName
                        inBundle:(NSBundle *)bundle
                           error:(NSError * _Nullable * _Nullable)error;

+ (BOOL)probePathExists:(NSString *)path
            isDirectory:(BOOL *)isDirectory
              isSymlink:(BOOL *)isSymlink;

@end

NS_ASSUME_NONNULL_END
