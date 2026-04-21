#import "lara-Bridging-Header.h"

#include <sys/stat.h>
#include <unistd.h>

@implementation VarCleanBridge

+ (NSDictionary *)loadRulesNamed:(NSString *)resourceName
                        inBundle:(NSBundle *)bundle
                           error:(NSError * _Nullable * _Nullable)error {
    NSString *jsonPath = [bundle pathForResource:resourceName ofType:@"json"];
    if (jsonPath.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"VarCleanBridge"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing VarClean rules resource"}];
        }
        return @{};
    }

    NSData *jsonData = [NSData dataWithContentsOfFile:jsonPath options:0 error:error];
    if (!jsonData) {
        return @{};
    }

    id rules = [NSJSONSerialization JSONObjectWithData:jsonData
                                               options:NSJSONReadingMutableContainers
                                                 error:error];
    if (![rules isKindOfClass:NSDictionary.class]) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"VarCleanBridge"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid VarClean rules format"}];
        }
        return @{};
    }

    return rules;
}

+ (BOOL)probePathExists:(NSString *)path
            isDirectory:(BOOL *)isDirectory
              isSymlink:(BOOL *)isSymlink {
    if (isDirectory) *isDirectory = NO;
    if (isSymlink) *isSymlink = NO;
    if (path.length == 0) {
        return NO;
    }

    struct stat st = {0};
    if (lstat(path.fileSystemRepresentation, &st) == 0) {
        if (isSymlink) *isSymlink = S_ISLNK(st.st_mode);
        if (isDirectory) *isDirectory = S_ISDIR(st.st_mode);
        return YES;
    }

    BOOL directory = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory]) {
        if (isDirectory) *isDirectory = directory;
        return YES;
    }

    return access(path.fileSystemRepresentation, F_OK) == 0;
}

@end
