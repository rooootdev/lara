#import <UIKit/UIKit.h>
#import <os/log.h>
#import <substrate.h>

#define CLLog(format, ...) os_log(OS_LOG_DEFAULT, "Cylinder: %@", [NSString stringWithFormat: format, ## __VA_ARGS__])
#define Log CLLog

#define SCREEN_SIZE UIScreen.mainScreen.bounds.size

#define PrefsEffectKey        @"effect"
#define PrefsEffectDirKey  @"effectSelector"
#define PrefsFormulaKey @"formula"
#define PrefsSelectedFormulaKey @"selectedFormula"
#define PrefsCarrierTextKey  @"carrierText"
#define PrefsUseTextKey      @"useText"
#define PrefsEnabledKey      @"enabled"
#define PrefsRandomizedKey      @"randomized"
#define PrefsOldMethodKey    @"useOldMethod"

#define PrefsPackKey         @"pack"
#define PrefsBrokenKey       @"brokenEffects"

#define DEFAULT_EFFECT @"Cube (inside)"
#define DEFAULT_SELECTOR @"cubeInside"

#ifndef MAIN_BUNDLE
#define MAIN_BUNDLE ([NSBundle bundleForClass:NSClassFromString(@"CylinderSettingsListController")])
#endif
#define LOCALIZE(KEY, DEFAULT) [MAIN_BUNDLE localizedStringForKey:KEY value:DEFAULT table:@"CylinderSettings"]
#define SYSTEM_LOCALIZE(KEY) [[NSBundle bundleWithIdentifier:@"com.apple.UIKit"] localizedStringForKey:KEY value:@"" table:nil]

#define IN_SPRINGBOARD()     ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"])
#define PREFS_PATH           @"/var/mobile/Library/Preferences/com.ryannair05.cylinderremade.plist"
#define RETINIZE(r)          [r stringByAppendingString:@"@2x"]

#define kCylinderSettingsChanged         @"com.ryannair05.cylinderremade/settingsChanged"
#define kCylinderSettingsRefreshSettings @"com.ryannair05.cylinderremade/refreshSettings"

#define BUNDLE_PATH @"/Library/PreferenceBundles/CylinderSettings.bundle/"

#define DEFAULT_EFFECTS      [NSArray arrayWithObjects:[NSDictionary dictionaryWithObjectsAndKeys:DEFAULT_EFFECT, PrefsEffectKey, DEFAULT_SELECTOR, PrefsEffectDirKey, nil], nil]
#define DEFAULT_FORMULAS    [NSDictionary dictionary]
#define DefaultPrefs         [NSMutableDictionary dictionaryWithObjectsAndKeys: DEFAULT_EFFECTS, PrefsEffectKey, DEFAULT_FORMULAS, PrefsFormulaKey, [NSNumber numberWithBool:YES], PrefsEnabledKey, [NSNumber numberWithBool:false], PrefsRandomizedKey, nil]

