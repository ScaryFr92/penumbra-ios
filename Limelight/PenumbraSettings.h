//
//  PenumbraSettings.h
//  Penumbra
//
//  Settings added by Penumbra. They live in NSUserDefaults instead of the
//  Core Data store so no data model migration is needed.
//

#import <Foundation/Foundation.h>

static NSString* const PenumbraMouseSensitivityKey = @"penumbra.mouseSensitivity";
static NSString* const PenumbraOscOpacityKey = @"penumbra.oscOpacity";
static NSString* const PenumbraDeviceMotionKey = @"penumbra.deviceMotion";
static NSString* const PenumbraNativeTouchKey = @"penumbra.nativeTouch";
static NSString* const PenumbraInertialScrollKey = @"penumbra.inertialScroll";
static NSString* const PenumbraCustomShortcutsKey = @"penumbra.customShortcuts";
static NSString* const PenumbraPortraitStreamKey = @"penumbra.portraitStream";

static inline void PenumbraRegisterDefaults(void) {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        PenumbraMouseSensitivityKey: @1.0f,
        PenumbraOscOpacityKey: @1.0f,
        PenumbraDeviceMotionKey: @NO,
        PenumbraNativeTouchKey: @NO,
        PenumbraInertialScrollKey: @YES,
        PenumbraCustomShortcutsKey: @[],
        PenumbraPortraitStreamKey: @NO,
    }];
}

static inline float PenumbraMouseSensitivity(void) {
    PenumbraRegisterDefaults();
    return [[NSUserDefaults standardUserDefaults] floatForKey:PenumbraMouseSensitivityKey];
}

static inline float PenumbraOscOpacity(void) {
    PenumbraRegisterDefaults();
    return [[NSUserDefaults standardUserDefaults] floatForKey:PenumbraOscOpacityKey];
}

static inline BOOL PenumbraDeviceMotionEnabled(void) {
    PenumbraRegisterDefaults();
    return [[NSUserDefaults standardUserDefaults] boolForKey:PenumbraDeviceMotionKey];
}

static inline BOOL PenumbraNativeTouchEnabled(void) {
    PenumbraRegisterDefaults();
    return [[NSUserDefaults standardUserDefaults] boolForKey:PenumbraNativeTouchKey];
}

static inline BOOL PenumbraInertialScrollEnabled(void) {
    PenumbraRegisterDefaults();
    return [[NSUserDefaults standardUserDefaults] boolForKey:PenumbraInertialScrollKey];
}

// Off by default: streams stay landscape like before, even with the rotation lock on
static inline BOOL PenumbraPortraitStreamEnabled(void) {
    PenumbraRegisterDefaults();
    return [[NSUserDefaults standardUserDefaults] boolForKey:PenumbraPortraitStreamKey];
}

static inline NSArray<NSString*>* PenumbraCustomShortcuts(void) {
    PenumbraRegisterDefaults();
    return [[NSUserDefaults standardUserDefaults] stringArrayForKey:PenumbraCustomShortcutsKey] ?: @[];
}

static inline void PenumbraSetCustomShortcuts(NSArray<NSString*>* shortcuts) {
    [[NSUserDefaults standardUserDefaults] setObject:shortcuts forKey:PenumbraCustomShortcutsKey];
}
