//
//  rc.m
//  lara
//
//  Created by ruter on 21.04.26.
//

#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <pthread.h>
#import <stdint.h>
#include <errno.h>
#include <string.h>
#include <unistd.h>
#import <sys/mman.h>
#import <objc/runtime.h>

#import "pac.h"
#import "rc.h"
#import "RemoteCall.h"
#import "PrivateAPI.h"

int ptrace(int _request, pid_t _pid, caddr_t _addr, int _data);
#define PT_DETACH       11
#define PT_ATTACHEXC    14

static bool rc_runtime_is_ios16(void) {
    NSString *version = [[UIDevice currentDevice] systemVersion];
    return [version compare:@"16.0" options:NSNumericSearch] != NSOrderedAscending &&
           [version compare:@"17.0" options:NSNumericSearch] == NSOrderedAscending;
}

static bool rc_ios16_require(const char *context, const char *name, uint64_t value) {
    if (value) {
        return true;
    }
    printf("(rc) iOS16: %s missing %s\n", context, name);
    fflush(stdout);
    return false;
}

void status_bar_time_format(RemoteCall *proc, const char *dateFormat) {
    if (!proc) {
        printf("(rc) RemoteCall not initialized\n");
        return;
    }

    uint64_t fmtNSStr = remote_NSString(proc, dateFormat);

    uint64_t selSharedApp   = remote_sel(proc, "sharedApplication");
    uint64_t selAggregator  = remote_sel(proc, "statusBarStateAggregator");
    uint64_t selValueForKey = remote_sel(proc, "valueForKey:");
    uint64_t selSetDateFmt  = remote_sel(proc, "setDateFormat:");
    uint64_t selUpdateTime  = remote_sel(proc, "_updateTimeItems");

    uint64_t uiAppCls = remote_getClass(proc, "UIApplication");
    uint64_t app = remote_msg(proc, uiAppCls, selSharedApp, 0, 0, 0, 0);
    printf("(rc) app = 0x%llx\n", app);

    uint64_t agg = remote_msg(proc, app, selAggregator, 0, 0, 0, 0);
    printf("(rc) aggregator = 0x%llx\n", agg);

    if (agg) {
        uint64_t keyStr = remote_NSString(proc, "_timeItemDateFormatter");
        uint64_t fmtr = remote_msg(proc, agg, selValueForKey, keyStr, 0, 0, 0);
        RemoteArbCall(proc, CFRelease, keyStr);
        printf("(rc) _timeItemDateFormatter = 0x%llx\n", fmtr);

        if (fmtr) {
            remote_msg(proc, fmtr, selSetDateFmt, fmtNSStr, 0, 0, 0);
            printf("(rc) Set format: HH:mm\n");
        }

        uint64_t key2Str = remote_NSString(proc, "_shortTimeItemDateFormatter");
        uint64_t fmtr2 = remote_msg(proc, agg, selValueForKey, key2Str, 0, 0, 0);
        RemoteArbCall(proc, CFRelease, key2Str);
        if (fmtr2) {
            remote_msg(proc, fmtr2, selSetDateFmt, fmtNSStr, 0, 0, 0);
            printf("(rc) Also patched _shortTimeItemDateFormatter\n");
        }

        uint64_t selPerform = remote_sel(proc, "performSelectorOnMainThread:withObject:waitUntilDone:");
        remote_msg(proc, agg, selPerform, selUpdateTime, 0 /*nil*/, 0 /*NO*/, 0);
    }

    printf("(rc) done\n");
}

// only works on processes with get_task_allow
int enable_jit(RemoteCall *proc, const char *bid) {
    if (!bid || bid[0] == '\0') {
        return EINVAL;
    }

    uint64_t predcls = remote_getClass(proc, "RBSProcessPredicate");
    uint64_t handlecls = remote_getClass(proc, "RBSProcessHandle");
    if (!predcls || !handlecls) {
        printf("(rc) RunningBoardServices classes not found\n");
        return ENOENT;
    }

    uint64_t bundlestr = remote_NSString(proc, bid);
    if (!bundlestr) {
        return ENOMEM;
    }

    uint64_t selpredmatch = remote_sel(proc, "predicateMatchingBundleIdentifier:");
    uint64_t selhandlefor = remote_sel(proc, "handleForPredicate:error:");
    uint64_t selpid = remote_sel(proc, "rbs_pid");

    uint64_t predicate = remote_msg(proc, predcls, selpredmatch, bundlestr, 0, 0, 0);
    uint64_t process = remote_msg(proc, handlecls, selhandlefor, predicate, 0 /*NSError ** == nil*/, 0, 0);
    uint64_t pid = remote_msg(proc, process, selpid, 0, 0, 0, 0) & 0xffffffffULL;

    RemoteArbCall(proc, CFRelease, bundlestr);

    if (!pid) {
        return ESRCH;
    }

    uint64_t ret = RemoteArbCall(proc, ptrace, PT_ATTACHEXC, pid, 0, 0, 0);
    if (ret == (uint64_t)-1) {
        int err = remote_errno(proc);
        return err > 0 ? err : EPERM;
    }

    usleep(100000);

    ret = RemoteArbCall(proc, ptrace, PT_DETACH, pid, 0, 0, 0);
    if (ret == (uint64_t)-1) {
        int err = remote_errno(proc);
        return err > 0 ? err : EPERM;
    }

    return 0;
}

static int hide_labels_in_view(RemoteCall *proc, uint64_t parentView) {
    if (!parentView) return 0;

    uint64_t selSubviews   = remote_sel(proc, "subviews");
    uint64_t selCount      = remote_sel(proc, "count");
    uint64_t selObjAtIdx   = remote_sel(proc, "objectAtIndex:");
    uint64_t selSetAllows  = remote_sel(proc, "setAllowsLabelArea:");
    uint64_t selResponds   = remote_sel(proc, "respondsToSelector:");

    uint64_t subviews = remote_msg(proc, parentView, selSubviews, 0,0,0,0);
    if (!subviews) return 0;
    uint64_t count = remote_msg(proc, subviews, selCount, 0,0,0,0);
    int hidden = 0;

    for (uint64_t i = 0; i < count && i < 200; i++) {
        uint64_t view = remote_msg(proc, subviews, selObjAtIdx, i, 0,0,0);
        if (!view) continue;
        uint64_t selPerform = remote_sel(proc, "performSelectorOnMainThread:withObject:waitUntilDone:");
        if (remote_msg(proc, view, selResponds, selSetAllows, 0,0,0)) {
            remote_msg(proc, view, selPerform, selSetAllows, 0 /*nil=NO*/, 1 /*YES wait*/, 0);
            hidden++;
        }
        uint64_t inner = remote_msg(proc, view, selSubviews, 0,0,0,0);
        uint64_t innerCount = remote_msg(proc, inner, selCount, 0,0,0,0);
        for (uint64_t j = 0; j < innerCount && j < 50; j++) {
            uint64_t v2 = remote_msg(proc, inner, selObjAtIdx, j, 0,0,0);
            if (v2 && remote_msg(proc, v2, selResponds, selSetAllows, 0,0,0)) {
                remote_msg(proc, v2, selPerform, selSetAllows, 0, 1, 0);
                hidden++;
            }
        }
    }
    return hidden;
}

static int hide_icon_labels_swizzle(RemoteCall *proc, bool swizzleSetter) {
    uint64_t clsNSObject = remote_getClass(proc, "NSObject");
    uint64_t clsSBIconView = remote_getClass(proc, "SBIconView");
    int swizzled = 0;

    if (clsNSObject && clsSBIconView) {
        uint64_t selIsProxy = remote_sel(proc, "isProxy");
        uint64_t methodReturn0 = RemoteArbCall(proc, class_getInstanceMethod, clsNSObject, selIsProxy);
        uint64_t impReturn0 = RemoteArbCall(proc, method_getImplementation, methodReturn0);

        uint64_t selAllowsGet = remote_sel(proc, "allowsLabelArea");
        uint64_t methodAllowsGet = RemoteArbCall(proc, class_getInstanceMethod, clsSBIconView, selAllowsGet);
        if (methodAllowsGet && impReturn0) {
            RemoteArbCall(proc, method_setImplementation, methodAllowsGet, impReturn0);
            swizzled++;
            printf("(rc) Swizzled allowsLabelArea to return NO\n");
        }

        if (swizzleSetter) {
            uint64_t selSelf = remote_sel(proc, "self");
            uint64_t methodNoOp = RemoteArbCall(proc, class_getInstanceMethod, clsNSObject, selSelf);
            uint64_t impNoOp = RemoteArbCall(proc, method_getImplementation, methodNoOp);

            uint64_t selSetAllows = remote_sel(proc, "setAllowsLabelArea:");
            uint64_t methodSetAllows = RemoteArbCall(proc, class_getInstanceMethod, clsSBIconView, selSetAllows);
            if (methodSetAllows && impNoOp) {
                RemoteArbCall(proc, method_setImplementation, methodSetAllows, impNoOp);
                swizzled++;
                printf("(rc) Swizzled setAllowsLabelArea: to no-op\n");
            }
        } else {
            printf("(rc) Skipped setAllowsLabelArea: swizzle\n");
        }
    } else {
        printf("(rc) Failed to find SBIconView or NSObject for swizzling\n");
    }

    return swizzled;
}

int hide_icon_labels(RemoteCall *proc) {
    if (!proc) {
        printf("(rc) RemoteCall not initialized\n");
        return -1;
    }
    printf("(rc) Hiding icon labels natively...\n");

    if (rc_runtime_is_ios16()) {
        printf("(rc) iOS16: skip icon view walk; using SBIconView getter swizzle only\n");
        int swizzled = hide_icon_labels_swizzle(proc, false);
        return swizzled ? swizzled : -1;
    }

    uint64_t selShared   = remote_sel(proc, "sharedInstance");
    uint64_t selIconMgr  = remote_sel(proc, "iconManager");
    uint64_t selCount    = remote_sel(proc, "count");
    uint64_t selObjAtIdx = remote_sel(proc, "objectAtIndex:");

    uint64_t ctrlCls = remote_getClass(proc, "SBIconController");
    uint64_t ctrl = remote_msg(proc, ctrlCls, selShared, 0,0,0,0);
    if (!ctrl) { printf("(rc) SBIconController not found\n"); return -1; }
    
    uint64_t mgr = remote_msg(proc, ctrl, selIconMgr, 0,0,0,0);
    int totalHidden = 0;

    uint64_t selRootFC    = remote_sel(proc, "rootFolderController");
    uint64_t selListViews = remote_sel(proc, "iconListViews");
    uint64_t rootFC = 0;
    if (mgr) rootFC = remote_msg(proc, mgr, selRootFC, 0,0,0,0);

    if (rootFC) {
        uint64_t listViews = remote_msg(proc, rootFC, selListViews, 0,0,0,0);
        uint64_t listCount = remote_msg(proc, listViews, selCount, 0,0,0,0);
        for (uint64_t i = 0; i < listCount && i < 20; i++) {
            uint64_t listView = remote_msg(proc, listViews, selObjAtIdx, i, 0,0,0);
            totalHidden += hide_labels_in_view(proc, listView);
        }
    }
    
    printf("(rc) Initial hidden labels: %d\n", totalHidden);

    int swizzled = hide_icon_labels_swizzle(proc, true);

    return totalHidden ? totalHidden : swizzled;
}

int set_dock_icon_count(RemoteCall *proc, int count) {
    if (!proc) {
        printf("(rc) RemoteCall not initialized\n");
        return -1;
    }

    if (count < 1) count = 1;
    if (count > 50) count = 50;

    printf("(rc) Starting dock tweak (columns=%d)...\n", count);

    uint64_t selShared    = remote_sel(proc, "sharedInstance");
    uint64_t selIconMgr   = remote_sel(proc, "iconManager");
    uint64_t selDockView  = remote_sel(proc, "dockListView");
    uint64_t selModel     = remote_sel(proc, "model");
    uint64_t selModel2    = remote_sel(proc, "iconListModel");
    uint64_t selGridGet   = remote_sel(proc, "gridSize");
    uint64_t selGridSet   = remote_sel(proc, "setGridSize:");
    uint64_t selLayout    = remote_sel(proc, "layout");
    uint64_t selLayoutCfg = remote_sel(proc, "layoutConfiguration");
    uint64_t selSetCols   = remote_sel(proc, "setNumberOfPortraitColumns:");
    uint64_t selPerform   = remote_sel(proc, "performSelectorOnMainThread:withObject:waitUntilDone:");
    uint64_t selSetNeedsLayout = remote_sel(proc, "setNeedsLayout");

    printf("(rc) Selectors registered\n");
    usleep(100000);

    uint64_t cls = remote_getClass(proc, "SBIconController");
    if (!cls) { printf("(rc) SBIconController not found\n"); return -1; }
    usleep(50000);

    uint64_t ctrl = remote_msg(proc, cls, selShared, 0,0,0,0);
    if (!ctrl) { printf("(rc) sharedInstance failed\n"); return -1; }
    printf("(rc) ctrl = 0x%llx\n", ctrl);
    usleep(50000);

    uint64_t mgr = remote_msg(proc, ctrl, selIconMgr, 0,0,0,0);
    usleep(50000);

    uint64_t dock = 0;
    if (mgr) dock = remote_msg(proc, mgr, selDockView, 0,0,0,0);
    if (!dock) dock = remote_msg(proc, ctrl, selDockView, 0,0,0,0);
    if (!dock) { printf("(rc) dockListView not found\n"); return -1; }
    printf("(rc) dock = 0x%llx\n", dock);
    usleep(50000);

    uint64_t model = remote_msg(proc, dock, selModel, 0,0,0,0);
    if (!model) model = remote_msg(proc, dock, selModel2, 0,0,0,0);
    if (model) {
        uint64_t oldGrid = remote_msg(proc, model, selGridGet, 0,0,0,0) & 0xFFFFFFFF;
        uint64_t newGrid = (oldGrid & 0xFFFF0000) | ((uint64_t)count & 0xFFFFULL);
        usleep(50000);
        remote_msg(proc, model, selGridSet, newGrid, 0,0,0);
        printf("(rc) gridSize 0x%llx -> 0x%llx\n", oldGrid, newGrid);
    }
    usleep(50000);

    uint64_t layout = remote_msg(proc, dock, selLayout, 0,0,0,0);
    if (layout) {
        usleep(50000);
        uint64_t cfg = remote_msg(proc, layout, selLayoutCfg, 0,0,0,0);
        if (cfg) {
            usleep(50000);
            remote_msg(proc, cfg, selSetCols, (uint64_t)count, 0,0,0);
            printf("(rc) portraitColumns -> %d\n", count);
        }
    }
    usleep(50000);

    remote_msg(proc, dock, selPerform, selSetNeedsLayout, 0 /*nil*/, 0 /*NO*/, 0);

    printf("(rc) done\n");
    return 0;
}

int five_icon_dock(RemoteCall *proc) {
    return set_dock_icon_count(proc, 5);
}

int enable_upside_down(RemoteCall *proc) {
    bool isIOS16 = rc_runtime_is_ios16();

    uint64_t clsSBAlertItemRootViewController = remote_getClass(proc, "SBAlertItemRootViewController");
    uint64_t clsSBHomeScreenViewController = remote_getClass(proc, "SBHomeScreenViewController");
    uint64_t clsSBCoverSheetPrimarySlidingViewController = remote_getClass(proc, "SBCoverSheetPrimarySlidingViewController");
    uint64_t clsSBShelfExpansionSwitcherModifier = remote_getClass(proc, "SBShelfExpansionSwitcherModifier");
    uint64_t clsSBTraitsSceneParticipantDelegate = remote_getClass(proc, "SBTraitsSceneParticipantDelegate");
    
    uint64_t selAllowed = remote_sel(proc, "_isAllowedToHavePortraitUpsideDown");
    uint64_t selOrientations = remote_sel(proc, "supportedInterfaceOrientations");
    uint64_t selOrientationMode = remote_sel(proc, "_orientationMode");
    uint64_t selSupportedOrientations = remote_sel(proc, "_supportedOrientations");
    uint64_t selReturn1 = remote_sel(proc, "_canShowWhileLocked");
    uint64_t selReturn6 = remote_sel(proc, "transactionCompletionOptions");
    
    uint64_t methodAllowed = RemoteArbCall(proc, class_getInstanceMethod, clsSBTraitsSceneParticipantDelegate, selAllowed);
    uint64_t methodHomeScreen = RemoteArbCall(proc, class_getInstanceMethod, clsSBHomeScreenViewController, selOrientations);
    uint64_t methodLockScreen = RemoteArbCall(proc, class_getInstanceMethod, clsSBCoverSheetPrimarySlidingViewController, selOrientations);
    uint64_t methodOrientationMode = RemoteArbCall(proc, class_getInstanceMethod, clsSBTraitsSceneParticipantDelegate, selOrientationMode);
    uint64_t methodSupportedOrientations = RemoteArbCall(proc, class_getInstanceMethod, clsSBTraitsSceneParticipantDelegate, selSupportedOrientations);
    uint64_t methodReturn1 = RemoteArbCall(proc, class_getInstanceMethod, clsSBCoverSheetPrimarySlidingViewController, selReturn1);
    uint64_t methodReturn6 = RemoteArbCall(proc, class_getInstanceMethod, clsSBShelfExpansionSwitcherModifier, selReturn6);
    uint64_t methodReturn0x1E = RemoteArbCall(proc, class_getInstanceMethod, clsSBAlertItemRootViewController, selOrientations);

    if (isIOS16) {
        if (!methodAllowed || !methodHomeScreen || !methodLockScreen ||
            !methodOrientationMode || !methodSupportedOrientations ||
            !methodReturn1 || !methodReturn6 || !methodReturn0x1E) {
            printf("(rc) iOS16: enable_upside_down missing method; aborting before method_setImplementation\n");
            fflush(stdout);
            return -1;
        }
    }
    
    // swizzle these to a return 6 gadget aka UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskPortraitUpsideDown
    // -[SBShelfExpansionSwitcherModifier transactionCompletionOptions]:
    //    mov    w0, #0x6
    //    ret
    uint64_t return6Imp = RemoteArbCall(proc, method_getImplementation, methodReturn6);
    if (isIOS16 && !return6Imp) {
        printf("(rc) iOS16: enable_upside_down missing return6 IMP\n");
        fflush(stdout);
        return -1;
    }
    RemoteArbCall(proc, method_setImplementation, methodHomeScreen, (uint64_t)return6Imp);
    RemoteArbCall(proc, method_setImplementation, methodLockScreen, (uint64_t)return6Imp);
    
    // swizzle these to a return 1 gadget
    uint64_t return1Imp = RemoteArbCall(proc, method_getImplementation, methodReturn1);
    if (isIOS16 && !return1Imp) {
        printf("(rc) iOS16: enable_upside_down missing return1 IMP\n");
        fflush(stdout);
        return -1;
    }
    RemoteArbCall(proc, method_setImplementation, methodAllowed, (uint64_t)return1Imp);
    
    // forward _orientationMode to 0x1e //_supportedOrientations
    //uint64_t supportedImp = RemoteArbCall(proc, method_getImplementation, methodSupportedOrientations);
    uint64_t return0x1EImp = RemoteArbCall(proc, method_getImplementation, methodReturn0x1E);
    if (isIOS16 && !return0x1EImp) {
        printf("(rc) iOS16: enable_upside_down missing return0x1E IMP\n");
        fflush(stdout);
        return -1;
    }
    RemoteArbCall(proc, method_setImplementation, methodOrientationMode, (uint64_t)return0x1EImp);
    RemoteArbCall(proc, method_setImplementation, methodSupportedOrientations, (uint64_t)return0x1EImp);
    
    
    /*
     UIInterfaceOrientationMaskPortraitUpsideDown =  1<<2
     find return 6 gadget
     
     SpringBoard`-[SBAlertItemRootViewController supportedInterfaceOrientations]:
         0x21f3392a8    mov    w0, #0x1e
         0x21f3392ac    ret

     
     SpringBoard`-[SBSystemApertureCurtainViewController supportedInterfaceOrientations]:
     ->  0x22e534d78 <+0>: mov    w0, #0x2 ; =2
         0x22e534d7c <+4>: ret
     
     SpringBoard`-[SBSystemApertureViewController supportedInterfaceOrientations]:
     ->  0x22e762134 <+0>: mov    w0, #0x2 ; =2
         0x22e762138 <+4>: ret
     */
    return 0;
}

// FIXME: floating dock does not hide at all
int enable_floating_dock(RemoteCall *proc) {
    if (!proc) {
        printf("(rc) RemoteCall not initialized\n");
        return -1;
    }
    bool isIOS16 = rc_runtime_is_ios16();
    uint64_t clsReturn1 = remote_getClass(proc, "SBCoverSheetPrimarySlidingViewController");
    uint64_t clsSBFloatingDockController = remote_getClass(proc, "SBFloatingDockController");
    uint64_t clsSBIconController = remote_getClass(proc, "SBIconController");
    uint64_t clsSBMainWorkspace = remote_getClass(proc, "SBMainWorkspace");
    
    uint64_t createFloatingDock = remote_sel(proc, "createFloatingDockControllerForWindowScene:");
    uint64_t selDockListView = remote_sel(proc, "dockListView");
    uint64_t selIconMgr   = remote_sel(proc, "iconManager");
    uint64_t selMainWindowScene = remote_sel(proc, "mainWindowScene");
    uint64_t selSharedInstance = remote_sel(proc, "sharedInstance");
    uint64_t selRespondsTo = remote_sel(proc, "respondsToSelector:");
    uint64_t selSupported = remote_sel(proc, "isFloatingDockSupported");
    uint64_t selSupported2 = remote_sel(proc, "isFloatingDockUtilitiesSupported");
    uint64_t selReturn1 = remote_sel(proc, "_canShowWhileLocked");
    
    uint64_t methodSupported = RemoteArbCall(proc, class_getClassMethod, clsSBFloatingDockController, selSupported);
    uint64_t methodSupported2 = RemoteArbCall(proc, class_getClassMethod, clsSBFloatingDockController, selSupported2);
    uint64_t methodReturn1 = RemoteArbCall(proc, class_getInstanceMethod, clsReturn1, selReturn1);

    if (isIOS16 &&
        (!rc_ios16_require("floating dock", "SBFloatingDockController", clsSBFloatingDockController) ||
         !rc_ios16_require("floating dock", "SBIconController", clsSBIconController) ||
         !rc_ios16_require("floating dock", "SBMainWorkspace", clsSBMainWorkspace) ||
         !rc_ios16_require("floating dock", "isFloatingDockSupported method", methodSupported) ||
         !rc_ios16_require("floating dock", "isFloatingDockUtilitiesSupported method", methodSupported2) ||
         !rc_ios16_require("floating dock", "_canShowWhileLocked method", methodReturn1))) {
        return -1;
    }
    
    uint64_t return1Imp = RemoteArbCall(proc, method_getImplementation, methodReturn1);
    if (isIOS16 && !rc_ios16_require("floating dock", "return1 IMP", return1Imp)) {
        return -1;
    }
    RemoteArbCall(proc, method_setImplementation, methodSupported, (uint64_t)return1Imp);
    RemoteArbCall(proc, method_setImplementation, methodSupported2, (uint64_t)return1Imp);
    
    uint64_t workspace = remote_msg(proc, clsSBMainWorkspace, selSharedInstance, 0,0,0,0);
    uint64_t mainWindowScene = remote_msg(proc, workspace, selMainWindowScene, 0,0,0,0);
    uint64_t iconController = remote_msg(proc, clsSBIconController, selSharedInstance, 0,0,0,0);
    if (isIOS16 &&
        (!rc_ios16_require("floating dock", "SBMainWorkspace sharedInstance", workspace) ||
         !rc_ios16_require("floating dock", "mainWindowScene", mainWindowScene) ||
         !rc_ios16_require("floating dock", "SBIconController sharedInstance", iconController))) {
        return -1;
    }
    return ![proc doRemoteCallSyncOnMainThread:^{
        uint64_t dockController;
        if (remote_msg(proc, iconController, selRespondsTo, createFloatingDock, 0,0,0)) {
            // iOS < 26 has -[SBIconController createFloatingDockControllerForWindowScene:]
            dockController = remote_msg(proc, iconController, createFloatingDock, mainWindowScene, 0,0,0);
        } else {
            // iOS 26 has -[SBHomeScreenController createFloatingDockControllerForWindowScene:]
            uint64_t selHomeScreen = remote_sel(proc, "homeScreenController");
            uint64_t homeScreenController = remote_msg(proc, mainWindowScene, selHomeScreen, 0,0,0,0);
            dockController = remote_msg(proc, homeScreenController, createFloatingDock, mainWindowScene, 0,0,0);
        }
        
        uint64_t sceneDelegate = remote_msg(proc, mainWindowScene, remote_sel(proc, "delegate"), 0,0,0,0);
        uint64_t sceneContext = remote_msg(proc, sceneDelegate, remote_sel(proc, "_sbWindowSceneContext"), 0,0,0,0);
        remote_msg(proc, sceneContext, remote_sel(proc, "setFloatingDockController:"), dockController, 0,0,0);
        
        uint64_t iconManager = remote_msg(proc, iconController, selIconMgr, 0,0,0,0);
        uint64_t rfcVC = remote_msg(proc, iconManager, remote_sel(proc, "rootFolderController"), 0,0,0,0);
        if (remote_msg(proc, rfcVC, selRespondsTo, selDockListView, 0,0,0)) {
            uint64_t dlv = remote_msg(proc, rfcVC, selDockListView, 0,0,0,0);
            if (dlv) {
                // Also hide the stock dock background
                uint64_t dockBG = remote_msg(proc, dlv, remote_sel(proc, "superview"), 0,0,0,0);
                remote_msg(proc, dockBG, remote_sel(proc, "setHidden:"), 1, 0,0,0);
            }
        }
        return YES;
    }];
}

int enable_grid_app_switcher(RemoteCall *proc) {
    if (!proc) {
        printf("(rc) RemoteCall not initialized\n");
        return -1;
    }
    bool isIOS16 = rc_runtime_is_ios16();
    uint64_t clsReturn2 = remote_getClass(proc, "SBDeckSwitcherModifier");
    uint64_t clsSBAppSwitcherSettings = remote_getClass(proc, "SBAppSwitcherSettings");
    
    uint64_t selStyle = remote_sel(proc, "switcherStyle");
    uint64_t selReturn2 = remote_sel(proc, "dockUpdateMode");
    
    uint64_t methodSupported = RemoteArbCall(proc, class_getInstanceMethod, clsSBAppSwitcherSettings, selStyle);
    uint64_t methodReturn2 = RemoteArbCall(proc, class_getInstanceMethod, clsReturn2, selReturn2);

    if (isIOS16 &&
        (!rc_ios16_require("grid app switcher", "SBAppSwitcherSettings", clsSBAppSwitcherSettings) ||
         !rc_ios16_require("grid app switcher", "SBDeckSwitcherModifier", clsReturn2) ||
         !rc_ios16_require("grid app switcher", "switcherStyle method", methodSupported) ||
         !rc_ios16_require("grid app switcher", "dockUpdateMode method", methodReturn2))) {
        return -1;
    }
    
    uint64_t return2Imp = RemoteArbCall(proc, method_getImplementation, methodReturn2);
    if (isIOS16 && !rc_ios16_require("grid app switcher", "return2 IMP", return2Imp)) {
        return -1;
    }
    RemoteArbCall(proc, method_setImplementation, methodSupported, (uint64_t)return2Imp);
    
    // <SBSwitcherController: 0x670b5b300>
    // [[0x670b5b300 contentViewController] personality]
    // TODO: fix animation?
    return 0;
}

int enable_debug_overlay(RemoteCall *proc) {
    if (!proc) {
        printf("(rc) RemoteCall not initialized\n");
        return -1;
    }
    bool isIOS16 = rc_runtime_is_ios16();
    uint64_t clsSBMainWorkspace = remote_getClass(proc, "SBMainWorkspace");
    uint64_t clsDebugOverlayWindow = remote_getClass(proc, "UIDebuggingInformationOverlay");
    uint64_t clsDebugOverlayHandler = remote_getClass(proc, "UIDebuggingInformationOverlayInvokeGestureHandler");
    uint64_t clsUIApplication = remote_getClass(proc, "UIApplication");
    uint64_t clsUITapGestureRecognizer = remote_getClass(proc, "UITapGestureRecognizer");
    uint64_t clsUIWindow = remote_getClass(proc, "UIWindow");
    
    uint64_t selAddGestureRecognizer = remote_sel(proc, "addGestureRecognizer:");
    uint64_t selHandleActivation = remote_sel(proc, "_handleActivationGesture:");
    uint64_t selInit = remote_sel(proc, "init");
    uint64_t selInitWithTargetAction = remote_sel(proc, "initWithTarget:action:");
    uint64_t selMainHandler = remote_sel(proc, "mainHandler");
    uint64_t selMainWindowScene = remote_sel(proc, "mainWindowScene");
    uint64_t selOverlay = remote_sel(proc, "overlay");
    uint64_t selPerform = remote_sel(proc, "performSelectorOnMainThread:withObject:waitUntilDone:");
    uint64_t selSetNumberOfTapsRequired = remote_sel(proc, "setNumberOfTapsRequired:");
    uint64_t selSetWindowScene = remote_sel(proc, "setWindowScene:");
    uint64_t selSharedApplication = remote_sel(proc, "sharedApplication");
    uint64_t selSharedInstance = remote_sel(proc, "sharedInstance");
    uint64_t selStatusBar = remote_sel(proc, "statusBarForEmbeddedDisplay");
    
    // Swizzle -[UIDebuggingInformationOverlay init] to -[UIWindow init] to bypass internal check
    uint64_t methodWindowInit = RemoteArbCall(proc, class_getInstanceMethod, clsUIWindow, selInit);
    uint64_t methodOverlayInit = RemoteArbCall(proc, class_getInstanceMethod, clsDebugOverlayWindow, selInit);
    if (isIOS16 &&
        (!rc_ios16_require("debug overlay", "SBMainWorkspace", clsSBMainWorkspace) ||
         !rc_ios16_require("debug overlay", "UIDebuggingInformationOverlay", clsDebugOverlayWindow) ||
         !rc_ios16_require("debug overlay", "UIDebuggingInformationOverlayInvokeGestureHandler", clsDebugOverlayHandler) ||
         !rc_ios16_require("debug overlay", "UIApplication", clsUIApplication) ||
         !rc_ios16_require("debug overlay", "UITapGestureRecognizer", clsUITapGestureRecognizer) ||
         !rc_ios16_require("debug overlay", "UIWindow", clsUIWindow) ||
         !rc_ios16_require("debug overlay", "UIWindow init method", methodWindowInit) ||
         !rc_ios16_require("debug overlay", "overlay init method", methodOverlayInit))) {
        return -1;
    }
    uint64_t impWindowInit = RemoteArbCall(proc, method_getImplementation, methodWindowInit);
    if (isIOS16 && !rc_ios16_require("debug overlay", "UIWindow init IMP", impWindowInit)) {
        return -1;
    }
    RemoteArbCall(proc, method_setImplementation, methodOverlayInit, impWindowInit);
    
    // Set windowScene
    uint64_t workspace = remote_msg(proc, clsSBMainWorkspace, selSharedInstance, 0,0,0,0);
    uint64_t mainWindowScene = remote_msg(proc, workspace, selMainWindowScene, 0,0,0,0);
    remote_msg(proc, clsDebugOverlayWindow, selPerform, selOverlay, 0, 1,0); // init window
    uint64_t debugOverlay = remote_msg(proc, clsDebugOverlayWindow, selOverlay, 0,0,0,0);
    if (isIOS16 &&
        (!rc_ios16_require("debug overlay", "SBMainWorkspace sharedInstance", workspace) ||
         !rc_ios16_require("debug overlay", "mainWindowScene", mainWindowScene) ||
         !rc_ios16_require("debug overlay", "overlay", debugOverlay))) {
        return -1;
    }
    remote_msg(proc, debugOverlay, selPerform, selSetWindowScene, mainWindowScene, 1,0);
    
    // register gesture recognizer to the status bar
    uint64_t target = remote_msg(proc, clsDebugOverlayHandler, selMainHandler, 0,0,0,0);
    uint64_t doubleTapGesture = RemoteArbCall(proc, objc_alloc, clsUITapGestureRecognizer);
    doubleTapGesture = remote_msg(proc, doubleTapGesture, selInitWithTargetAction, target, selHandleActivation, 0,0);
    remote_msg(proc, doubleTapGesture, selSetNumberOfTapsRequired, 2, 0,0,0);
    uint64_t app = remote_msg(proc, clsUIApplication, selSharedApplication, 0,0,0,0);
    uint64_t statusBar = remote_msg(proc, app, selStatusBar, 0,0,0,0);
    if (isIOS16 &&
        (!rc_ios16_require("debug overlay", "main handler", target) ||
         !rc_ios16_require("debug overlay", "tap gesture", doubleTapGesture) ||
         !rc_ios16_require("debug overlay", "sharedApplication", app) ||
         !rc_ios16_require("debug overlay", "statusBarForEmbeddedDisplay", statusBar))) {
        return -1;
    }
    remote_msg(proc, statusBar, selPerform, selAddGestureRecognizer, doubleTapGesture, 1,0);
    RemoteArbCall(proc, objc_release, doubleTapGesture);
    
    return 0;
}

static const NSInteger kFreakyDogTag = 0xD06;

static uint64_t freakywindow(RemoteCall *proc) {
    uint64_t clsUIApplication = remote_getClass(proc, "UIApplication");
    if (!clsUIApplication) {
        return 0;
    }

    uint64_t selSharedApplication = remote_sel(proc, "sharedApplication");
    uint64_t selKeyWindow = remote_sel(proc, "keyWindow");
    uint64_t selWindows = remote_sel(proc, "windows");
    uint64_t selFirstObject = remote_sel(proc, "firstObject");
    uint64_t selDelegate = remote_sel(proc, "delegate");
    uint64_t selWindow = remote_sel(proc, "window");

    uint64_t app = remote_msg(proc, clsUIApplication, selSharedApplication, 0, 0, 0, 0);
    if (!app) {
        printf("(rc) freakywindow: UIApplication unavailable\n");
        return 0;
    }

    uint64_t window = remote_msg(proc, app, selKeyWindow, 0, 0, 0, 0);
    if (window) {
        return window;
    }

    uint64_t windows = remote_msg(proc, app, selWindows, 0, 0, 0, 0);
    if (windows) {
        window = remote_msg(proc, windows, selFirstObject, 0, 0, 0, 0);
        if (window) {
            return window;
        }
    }

    uint64_t delegate = remote_msg(proc, app, selDelegate, 0, 0, 0, 0);
    if (delegate) {
        window = remote_msg(proc, delegate, selWindow, 0, 0, 0, 0);
        if (window) {
            return window;
        }
    }

    printf("(rc) freakywindow: no SpringBoard window found\n");
    return 0;
}

static void freakyperform(RemoteCall *proc, uint64_t target, uint64_t sel, uint64_t arg) {
    if (!proc || !target || !sel) {
        return;
    }

    uint64_t selPerform = remote_sel(proc, "performSelectorOnMainThread:withObject:waitUntilDone:");
    remote_msg(proc, target, selPerform, sel, arg, 0, 0);
}

uint64_t enable_freaky_dog_overlay(RemoteCall *proc) {
    if (!proc) {
        printf("(rc) RemoteCall not initialized\n");
        return 0;
    }

    uint64_t clsUIApplication = remote_getClass(proc, "UIApplication");
    uint64_t clsNSURL = remote_getClass(proc, "NSURL");
    uint64_t clsNSData = remote_getClass(proc, "NSData");
    uint64_t clsUIImage = remote_getClass(proc, "UIImage");
    uint64_t clsUIImageView = remote_getClass(proc, "UIImageView");
    if (!clsUIApplication || !clsNSURL || !clsNSData || !clsUIImage || !clsUIImageView) {
        return 0;
    }

    uint64_t selViewWithTag = remote_sel(proc, "viewWithTag:");
    uint64_t selRemoveFromSuperview = remote_sel(proc, "removeFromSuperview");
    uint64_t selURLWithString = remote_sel(proc, "URLWithString:");
    uint64_t selDataWithContentsOfURL = remote_sel(proc, "dataWithContentsOfURL:");
    uint64_t selImageWithData = remote_sel(proc, "imageWithData:");
    uint64_t selInitWithImage = remote_sel(proc, "initWithImage:");
    uint64_t selAddSubview = remote_sel(proc, "addSubview:");
    uint64_t selSetTag = remote_sel(proc, "setTag:");
    uint64_t selSetContentMode = remote_sel(proc, "setContentMode:");
    uint64_t selSetClipsToBounds = remote_sel(proc, "setClipsToBounds:");
    uint64_t selBringSubviewToFront = remote_sel(proc, "bringSubviewToFront:");
    uint64_t selSetUserInteractionEnabled = remote_sel(proc, "setUserInteractionEnabled:");
    uint64_t selSetHidden = remote_sel(proc, "setHidden:");

    uint64_t window = freakywindow(proc);
    if (!window) {
        return 0;
    }

    uint64_t urlString = remote_NSString(proc, "https://roooot.dev/lara/assets/freakyahhdog.png");
    uint64_t url = remote_msg(proc, clsNSURL, selURLWithString, urlString, 0, 0, 0);
    if (!url) {
        printf("(rc) freaky: URL creation failed\n");
        return 0;
    }

    uint64_t data = remote_msg(proc, clsNSData, selDataWithContentsOfURL, url, 0, 0, 0);
    if (!data) {
        printf("(rc) freaky: image download failed\n");
        return 0;
    }

    uint64_t image = remote_msg(proc, clsUIImage, selImageWithData, data, 0, 0, 0);
    if (!image) {
        printf("(rc) freaky: UIImage creation failed\n");
        return 0;
    }

    uint64_t existing = remote_msg(proc, window, selViewWithTag, (uint64_t)kFreakyDogTag, 0, 0, 0);
    if (existing) {
        freakyperform(proc, existing, selRemoveFromSuperview, 0);
    }

    uint64_t imageView = RemoteArbCall(proc, objc_alloc, clsUIImageView);
    if (!imageView) {
        printf("(rc) freaky: UIImageView alloc failed\n");
        return 0;
    }

    imageView = remote_msg(proc, imageView, selInitWithImage, image, 0, 0, 0);
    if (!imageView) {
        printf("(rc) freaky: UIImageView init failed\n");
        return 0;
    }

    remote_setCGRect(proc, imageView, remote_sel(proc, "setFrame:"), CGRectMake(24, 140, 180, 180));
    remote_msg(proc, imageView, selSetTag, (uint64_t)kFreakyDogTag, 0, 0, 0);
    remote_msg(proc, imageView, selSetContentMode, 1, 0, 0, 0);
    remote_msg(proc, imageView, selSetClipsToBounds, 1, 0, 0, 0);
    remote_msg(proc, imageView, selSetUserInteractionEnabled, 0, 0, 0, 0);
    remote_msg(proc, imageView, selSetHidden, 0, 0, 0, 0);
    freakyperform(proc, window, selAddSubview, imageView);
    freakyperform(proc, window, selBringSubviewToFront, imageView);
    return imageView;
}

int move_freaky_dog_overlay(RemoteCall *proc, uint64_t imageView, int x, int y, int width, int height) {
    if (!proc || !imageView) {
        return -1;
    }

    remote_setCGRect(proc, imageView, remote_sel(proc, "setFrame:"), CGRectMake(x, y, width, height));
    return 0;
}

int disable_freaky_dog_overlay(RemoteCall *proc) {
    if (!proc) {
        return -1;
    }

    uint64_t selViewWithTag = remote_sel(proc, "viewWithTag:");
    uint64_t selRemoveFromSuperview = remote_sel(proc, "removeFromSuperview");

    uint64_t window = freakywindow(proc);
    if (!window) {
        return -1;
    }

    uint64_t existing = remote_msg(proc, window, selViewWithTag, (uint64_t)kFreakyDogTag, 0, 0, 0);
    if (!existing) {
        return 0;
    }

    freakyperform(proc, existing, selRemoveFromSuperview, 0);
    return 0;
}

int get_performance_hud(RemoteCall *proc) {
    uint64_t flags = RemoteArbCall(proc, CARenderServerGetDebugFlags, 0);
    if (flags & CA_DEBUG_FLAG_PERFORMANCE_HUD) {
        return (int)RemoteArbCall(proc, CARenderServerGetDebugValue, 0, 1);
    }
    return -1;
}

int set_performance_hud(RemoteCall *proc, int selection) {
    BOOL enabled = selection >= 0;
    uint64_t flags = RemoteArbCall(proc, CARenderServerGetDebugFlags, 0);
    if (enabled) {
        flags |= CA_DEBUG_FLAG_PERFORMANCE_HUD;
        RemoteArbCall(proc, CARenderServerSetDebugValue, 0, 1, selection);
    } else {
        flags &= ~CA_DEBUG_FLAG_PERFORMANCE_HUD;
    }
    RemoteArbCall(proc, CARenderServerSetDebugFlags, 0, CA_DEBUG_FLAG_PERFORMANCE_HUD, flags);
    return 0;
}

void wake_up_daemon(RemoteCall *sb, NSString *daemon, NSString *frameworkContainingXPCSerice) {
    uint64_t memRemote = sb.trojanMem;
    
    // special case for certain daemons
    if ([daemon isEqualToString:@"appstorecomponentsd"]) {
        // [[ASCServicesConnection sharedConnection] testConnection]
        uint64_t cls = remote_getClass(sb, "ASCServicesConnection");
        uint64_t selShared = remote_sel(sb, "sharedConnection");
        uint64_t selTest = remote_sel(sb, "testConnection");
        uint64_t connection = remote_msg(sb, cls, selShared, 0,0,0,0);
        if (connection) {
            remote_msg(sb, connection, selTest, 0,0,0,0);
        }
        return;
    }
    
    if (frameworkContainingXPCSerice) {
        sb[memRemote].string = frameworkContainingXPCSerice;
        //@"/System/Library/PrivateFrameworks/DVTInstrumentsFoundation.framework/DVTInstrumentsFoundation";
        RemoteArbCall(sb, dlopen, memRemote, 0);
    }
    
    sb[memRemote].string = daemon;
    uint64_t conn;
    if (frameworkContainingXPCSerice) {
        // for XPC services embedded in a certain framework, eg. com.apple.dt.instruments.dtsecurity.xpc
        conn = RemoteArbCall(sb, xpc_connection_create, memRemote, 0);
    } else {
        // for Mach/XPC services registered in launchd.plist
        void *xpc_connection_create_mach_service = dlsym(RTLD_DEFAULT, "xpc_connection_create_mach_service");
        conn = RemoteArbCall(sb, xpc_connection_create_mach_service, memRemote, 0);
    }
    // ^(xpc_object_t event) {}
    // Construct a block
    RemoteArbCall(sb, bzero, memRemote, PAGE_SIZE);
    uint64_t block = memRemote;
    uint64_t descriptor = block + 0x20; // right next to block
    sb[block].value64 = remote_getClass(sb, "__NSGlobalBlock__"); // isa
    sb[block+0x8].value32 = (1<<30) | (1<<28); //flags: BLOCK_HAS_SIGNATURE | BLOCK_IS_GLOBAL;
    sb[block+0x10].value64 = remotepac(sb.callThreadAddr, (uint64_t)getpid, ptrauth_blend_discriminator((void *)(block+0x10), 0));
    sb[block+0x18].value64 = descriptor;
    sb[descriptor].value64 = 0; // reserved
    sb[descriptor+0x8].value64 = 0x20; // size
    RemoteArbCall(sb, xpc_connection_set_event_handler, conn, block);
    
    RemoteArbCall(sb, xpc_connection_resume, conn, 0);
    uint64_t msg = RemoteArbCall(sb, xpc_dictionary_create, 0, 0, 0);
    RemoteArbCall(sb, xpc_connection_send_message, conn, msg, 0);
    RemoteArbCall(sb, xpc_release, msg, 0);
    RemoteArbCall(sb, xpc_release, conn, 0);
//    xpc_connection_t conn = xpc_connection_create("com.apple.dt.instruments.dtsecurity.xpc", 0);
//    xpc_connection_set_event_handler(conn, ^(id event) {});
//    xpc_connection_resume(conn);
//    xpc_connection_send_message(conn, xpc_dictionary_create(NULL, NULL, 0));
}

int euenabler_overwrite_eligibility(RemoteCall *proc) {
    void *os_eligibility_force_domain_answer = dlsym(RTLD_DEFAULT, "os_eligibility_force_domain_answer");
    // probably old iOS, skip this
    if (!os_eligibility_force_domain_answer) return -1;
    int result = (int)RemoteArbCall(proc, os_eligibility_force_domain_answer, EligibilityDomainTypeHydrogen, EligibilityAnswerEligible, 0);
    RemoteArbCall(proc, os_eligibility_force_domain_answer, EligibilityDomainTypeHelium, EligibilityAnswerEligible, 0);
    RemoteArbCall(proc, os_eligibility_force_domain_answer, EligibilityDomainTypeLithium, EligibilityAnswerEligible, 0);
    RemoteArbCall(proc, os_eligibility_force_domain_answer, EligibilityDomainTypeBoron, EligibilityAnswerEligible, 0);
    RemoteArbCall(proc, os_eligibility_force_domain_answer, EligibilityDomainTypeCarbon, EligibilityAnswerEligible, 0);
    RemoteArbCall(proc, os_eligibility_force_domain_answer, EligibilityDomainTypeArgon, EligibilityAnswerEligible, 0);
    RemoteArbCall(proc, os_eligibility_force_domain_answer, EligibilityDomainTypePotassium, EligibilityAnswerEligible, 0);
    RemoteArbCall(proc, os_eligibility_force_domain_answer, EligibilityDomainTypeTitanium, EligibilityAnswerEligible, 0);
    RemoteArbCall(proc, os_eligibility_force_domain_answer, EligibilityDomainTypeIron, EligibilityAnswerEligible, 0);
    // return first one
    return result;
}

// Extremely hack here: this need to swizzle countryCodeOverride methods to return one of EU countries, since we can't just hook or inject code
// It does this by finding a certain `return @"<country code>";` gadget, and swizzling in both managedappdistributiond and appstorecomponentsd
// We find that /System/Library/PrivateFrameworks/MediaAnalysis.framework/MediaAnalysis has -[PHPhotoLibrary vcp_description] which could return PL aka Poland country code.
// However, said method calls 2 other methods, so we add these fake methods to make them return 0, its implementation is as follows:
#if 0
@implementation PHPhotoLibrary(MediaAnalysis)
- (NSString *)vcp_description {
    if ([self isSystemPhotoLibrary]) {
        return @"SPL";
    }
    if ([self wellKnownPhotoLibraryIdentifier] == 3) {
        return @"SyndPL";
    }
    return @"PL";
}
@end
#endif

void euenabler_override_country_code(RemoteCall *proc, rc_euenabler_callback_t callback) {
    callback(0.2);
    uint64_t mem = proc.trojanMem;
    proc[mem].string = @"/System/Library/PrivateFrameworks/MediaAnalysis.framework/MediaAnalysis";
    RemoteArbCall(proc, dlopen, mem, RTLD_GLOBAL);
    
    uint64_t cls1 = remote_getClass(proc, "ASCLockupBatchRequest");
    uint64_t cls2 = remote_getClass(proc, "ASCLockupRequest");
    uint64_t clsReturnPL = remote_getClass(proc, "PHPhotoLibrary");
    
    uint64_t selCountryCodeOverride = remote_sel(proc, "countryCodeOverride");
    uint64_t selFakeMethod1 = remote_sel(proc, "isSystemPhotoLibrary");
    uint64_t selFakeMethod2 = remote_sel(proc, "wellKnownPhotoLibraryIdentifier");
    uint64_t selReturnNil = remote_sel(proc, "platformOverride");
    uint64_t selReturnPL = remote_sel(proc, "vcp_description");
    callback(0.4);
    
    // Add fake isSystemPhotoLibrary and wellKnownPhotoLibraryIdentifier methods that return 0, so that vcp_description will return "PL"
    uint64_t methodReturnNil = RemoteArbCall(proc, class_getInstanceMethod, cls1, selReturnNil);
    uint64_t returnNilImp = RemoteArbCall(proc, method_getImplementation, methodReturnNil);
    uint64_t fakeMethodEncoding = RemoteArbCall(proc, method_getTypeEncoding, methodReturnNil);
    RemoteArbCall(proc, class_addMethod, cls1, selFakeMethod1, (uint64_t)returnNilImp, fakeMethodEncoding);
    RemoteArbCall(proc, class_addMethod, cls1, selFakeMethod2, (uint64_t)returnNilImp, fakeMethodEncoding);
    RemoteArbCall(proc, class_addMethod, cls2, selFakeMethod1, (uint64_t)returnNilImp, fakeMethodEncoding);
    RemoteArbCall(proc, class_addMethod, cls2, selFakeMethod2, (uint64_t)returnNilImp, fakeMethodEncoding);
    callback(0.6);
    
    // Swizzle countryCodeOverride -> vcp_description
    uint64_t methodReturnPL = RemoteArbCall(proc, class_getInstanceMethod, clsReturnPL, selReturnPL);
    uint64_t method1 = RemoteArbCall(proc, class_getInstanceMethod, cls1, selCountryCodeOverride);
    uint64_t method2 = RemoteArbCall(proc, class_getInstanceMethod, cls2, selCountryCodeOverride);
    uint64_t returnPLImp = RemoteArbCall(proc, method_getImplementation, methodReturnPL);
    RemoteArbCall(proc, method_setImplementation, method1, (uint64_t)returnPLImp);
    RemoteArbCall(proc, method_setImplementation, method2, (uint64_t)returnPLImp);
    callback(0.8);
    
    // Swizzle some methods in LSBundleRecord to bypass "Not bypassing eligibility for com.apple.mobilesafari:personal (isProfileValidated: false isUPPValidated:false isBeta:false"
    uint64_t clsLSBundleRecord = remote_getClass(proc, "LSBundleRecord");
    if (clsLSBundleRecord) {
        uint64_t selIsProfileValidated = remote_sel(proc, "isProfileValidated");
        uint64_t selReturn1 = remote_sel(proc, "supportsSecureCoding");
        // uint64_t selIsUPPValidated = remote_sel(proc, "isUPPValidated");
        // uint64_t selIsBeta = remote_sel(proc, "isBeta");
        uint64_t methodProfile = RemoteArbCall(proc, class_getInstanceMethod, clsLSBundleRecord, selIsProfileValidated);
        uint64_t methodReturn1 = RemoteArbCall(proc, class_getClassMethod, clsLSBundleRecord, selReturn1);
        //uint64_t return0Imp = (uint64_t)RemoteArbCall(proc, method_getImplementation, methodProfile);
        uint64_t return1Imp = (uint64_t)RemoteArbCall(proc, method_getImplementation, methodReturn1);
        RemoteArbCall(proc, method_setImplementation, methodProfile, return1Imp);
    }
    callback(1.0);
}

bool patch_homescreen_grid(RemoteCall *proc, int cols, int rows) {
    if (!proc) return false;
    
    uint64_t selShared      = remote_sel(proc, "sharedInstance");
    uint64_t selIconMgr     = remote_sel(proc, "iconManager");
    uint64_t selProvider    = remote_sel(proc, "listLayoutProvider");
    uint64_t selLayout      = remote_sel(proc, "layoutForIconLocation:");
    uint64_t selLayoutCfg   = remote_sel(proc, "layoutConfiguration");
    uint64_t selSetCols     = remote_sel(proc, "setNumberOfPortraitColumns:");
    uint64_t selSetRows     = remote_sel(proc, "setNumberOfPortraitRows:");
    uint64_t selSetLandCols = remote_sel(proc, "setNumberOfLandscapeColumns:");
    uint64_t selSetLandRows = remote_sel(proc, "setNumberOfLandscapeRows:");
    uint64_t selRootFolder  = remote_sel(proc, "rootFolderController");
    uint64_t selViewCount   = remote_sel(proc, "iconListViewCount");
    uint64_t selViewAtIndex = remote_sel(proc, "iconListViewAtIndex:");
    uint64_t selDockLV      = remote_sel(proc, "dockListView");
    uint64_t selSetAutoFit  = remote_sel(proc, "setAutomaticallyAdjustsLayoutMetricsToFit:");
    uint64_t selGridGet     = remote_sel(proc, "gridSize");
    uint64_t selGridSet     = remote_sel(proc, "setGridSize:");
    uint64_t selModel       = remote_sel(proc, "model");
    uint64_t selModel2      = remote_sel(proc, "iconListModel");
    
    uint64_t cls = remote_getClass(proc, "SBIconController");
    if (!cls) return false;
    uint64_t ctrl = remote_msg(proc, cls, selShared, 0, 0, 0, 0);
    if (!ctrl) return false;
    uint64_t mgr = remote_msg(proc, ctrl, selIconMgr, 0, 0, 0, 0);
    if (!mgr) return false;
    
    uint64_t provider = remote_msg(proc, mgr, selProvider, 0, 0, 0, 0);
    if (provider) {
        uint64_t locStr = remote_NSString(proc, "SBIconLocationRoot");
        if (locStr) {
            uint64_t layout = remote_msg(proc, provider, selLayout, locStr, 0, 0, 0);
            if (layout) {
                uint64_t cfg = remote_msg(proc, layout, selLayoutCfg, 0, 0, 0, 0);
                if (cfg) {
                    remote_msg(proc, cfg, selSetCols,     (uint64_t)cols, 0, 0, 0);
                    remote_msg(proc, cfg, selSetRows,     (uint64_t)rows, 0, 0, 0);
                    remote_msg(proc, cfg, selSetLandCols, (uint64_t)rows, 0, 0, 0);
                    remote_msg(proc, cfg, selSetLandRows, (uint64_t)cols, 0, 0, 0);
                    printf("(rc) layout config patched\n");
                }
            }
        }
    }
    
    uint64_t rootFolder = remote_msg(proc, mgr, selRootFolder, 0, 0, 0, 0);
    if (!rootFolder) return false;
    
    uint64_t newGrid = (((uint64_t)rows & 0xFFFF) << 16) | ((uint64_t)cols & 0xFFFF);
    
    uint64_t viewCount = remote_msg(proc, rootFolder, selViewCount, 0, 0, 0, 0);
    if (viewCount > 64) viewCount = 64;
    
    for (uint64_t i = 0; i < viewCount; i++) {
        uint64_t lv = remote_msg(proc, rootFolder, selViewAtIndex, i, 0, 0, 0);
        if (!lv) continue;
        
        remote_msg(proc, lv, selSetAutoFit, 0, 0, 0, 0);
        
        uint64_t pageModel = remote_msg(proc, lv, selModel, 0, 0, 0, 0);
        if (!pageModel) pageModel = remote_msg(proc, lv, selModel2, 0, 0, 0, 0);
        if (pageModel) {
            uint64_t oldGrid = remote_msg(proc, pageModel, selGridGet, 0, 0, 0, 0) & 0xFFFFFFFF;
            remote_msg(proc, pageModel, selGridSet, newGrid, 0, 0, 0);
            printf("(rc) page %llu model gridSize 0x%llx -> 0x%llx\n", i, oldGrid, newGrid);
        }
    }
    
    uint64_t dockLV = remote_msg(proc, mgr, selDockLV, 0, 0, 0, 0);
    if (dockLV) {
        remote_msg(proc, dockLV, selSetAutoFit, 0, 0, 0, 0);
        uint64_t dockModel = remote_msg(proc, dockLV, selModel, 0, 0, 0, 0);
        if (!dockModel) dockModel = remote_msg(proc, dockLV, selModel2, 0, 0, 0, 0);
        if (dockModel) {
            uint64_t oldGrid = remote_msg(proc, dockModel, selGridGet, 0, 0, 0, 0) & 0xFFFFFFFF;
            remote_msg(proc, dockModel, selGridSet, newGrid, 0, 0, 0);
            printf("(rc) dock model gridSize 0x%llx -> 0x%llx\n", oldGrid, newGrid);
        }
    }
    
    printf("(rc) patch_homescreen_grid done\n");
    return true;
}

void youtube_tweak(RemoteCall *proc) {
    printf("starting YouTube tweaks...\n");
    
    uint64_t nsCls = remote_getClass(proc, "NSObject");
    uint64_t selAllows = remote_sel(proc, "allowsWeakReference");
    uint64_t nsMethod = RemoteArbCall(proc, class_getInstanceMethod, nsCls, selAllows, 0, 0, 0, 0);
    uint64_t retYesImp = RemoteArbCall(proc, method_getImplementation, nsMethod, 0, 0, 0, 0);
    printf("return-YES IMP = 0x%llx\n", retYesImp);
    
    if (!retYesImp) {
        printf("failed to obtain return-YES IMP\n");
        return;
    }
    
    uint64_t adCls = remote_getClass(proc, "YTAdsInnerTubeContextDecorator");
    if (adCls) {
        uint64_t selDecorate = remote_sel(proc, "decorateContext:");
        uint64_t adMethod = RemoteArbCall(proc, class_getInstanceMethod, adCls, selDecorate, 0, 0, 0, 0);
        if (adMethod) {
            RemoteArbCall(proc, method_setImplementation, adMethod, retYesImp, 0, 0, 0, 0);
            printf("hooked YTAdsInnerTubeContextDecorator.decorateContext: -> no-op\n");
        } else {
            printf("decorateContext: method not found\n");
        }
    } else {
        printf("YTAdsInnerTubeContextDecorator class not found\n");
    }
    
    uint64_t selBG = remote_sel(proc, "isPlayableInBackground");
    const char *bgClasses[] = {
        "YTIPlayerResponse",
        "YTSingleVideo",
        "YTPlaybackData",
        "YTIPlayabilityStatus",
    };
    
    for (int i = 0; i < 4; i++) {
        uint64_t cls = remote_getClass(proc, bgClasses[i]);
        if (!cls) {
            printf("%s class not found\n", bgClasses[i]);
            continue;
        }
        uint64_t method = RemoteArbCall(proc, class_getInstanceMethod, cls, selBG, 0, 0, 0, 0);
        if (method) {
            RemoteArbCall(proc, method_setImplementation, method, retYesImp, 0, 0, 0, 0);
            printf("hooked %s.isPlayableInBackground -> YES\n", bgClasses[i]);
        } else {
            printf("%s: isPlayableInBackground not found\n", bgClasses[i]);
        }
    }
    
    printf("Done\n");
}
