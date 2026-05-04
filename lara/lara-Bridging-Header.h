//
//  lara-Bridging-Header.h
//  lara
//

@import UIKit;
#import <Foundation/Foundation.h>

#import "darksword.h"
#import "offsets.h"
#import "utils.h"
#import "apfs.h"
#import "vfs.h"
#import "sbx.h"
#import "rc.h"
#import "RemoteCall.h"
#import "kexploit/pe/amfi.h"
#import "kexploit/pe/installd_patch.h"
#import "kexploit/pe/trust_cache_inject.h"

long FindCacheDataOffset(const char *mgKey);

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
