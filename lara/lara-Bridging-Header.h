//
//  lara-Bridging-Header.h
//  lara
//

#import <Foundation/Foundation.h>
#import "darksword.h"
#import "utils.h"
#import "vfs.h"

void test(NSString *path);

bool setkernproc(NSString *path);
bool dlkerncache(void);
uint64_t getkernproc(void);
uint64_t getrootvnode(void);
bool haskernproc(void);
NSString *getkerncache(void);
void clearkerncachedata(void);
NSData* vfs_read(NSString* path);
bool vfs_write(NSString* path, NSData* data);
int get_pid_for_name(NSString* name);
