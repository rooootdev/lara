#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <objc/runtime.h>

@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
- (id)allInstalledApplications;
@end

@interface LSApplicationProxy : NSObject
- (NSString *)applicationIdentifier;
- (NSString *)localizedName;
- (NSURL *)containerURL; 
@end

NSString* get_container_uuid_for_app(NSString *targetName) {
    if (!targetName || [targetName length] == 0) {
        return nil;
    }
    
    void *handle = dlopen("/System/Library/PrivateFrameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_NOW);
    if (!handle) {
        handle = dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_NOW);
    }
    
    if (!handle) {
        return nil;
    }
    
    Class workspaceClass = objc_getClass("LSApplicationWorkspace");
    if (!workspaceClass) {
        dlclose(handle);
        return nil;
    }
    
    id workspace = [workspaceClass defaultWorkspace];
    NSArray *apps = [workspace allInstalledApplications];
    NSString *foundUUID = nil;
    
    NSString *searchQuery = [targetName lowercaseString];
    
    for (LSApplicationProxy *app in apps) {
        NSString *appName = [[app localizedName] lowercaseString];
        NSString *bundleId = [[app applicationIdentifier] lowercaseString];
        
        if ((appName && [appName rangeOfString:searchQuery].location != NSNotFound) || 
            (bundleId && [bundleId rangeOfString:searchQuery].location != NSNotFound)) {
            
            NSURL *containerURL = [app containerURL];
            if (containerURL) {
                foundUUID = [containerURL lastPathComponent];
                break;
            }
        }
    }
    
    dlclose(handle);
    return foundUUID;
}
