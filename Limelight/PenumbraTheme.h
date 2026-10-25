//
//  PenumbraTheme.h
//  Penumbra
//
//  The "eclipse" look: near-black ground, charcoal cards and one golden accent.
//

#import <UIKit/UIKit.h>

static inline UIColor* PenumbraColor(uint32_t rgb, CGFloat alpha) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:alpha];
}

static inline UIColor* PenumbraGroundColor(void) { return PenumbraColor(0x0B0C10, 1); }
static inline UIColor* PenumbraSurfaceColor(void) { return PenumbraColor(0x16181F, 1); }
// Card borders get much stronger when the user turned on Increase Contrast
static inline UIColor* PenumbraHairlineColor(void) {
    return [UIColor colorWithWhite:1 alpha:UIAccessibilityDarkerSystemColorsEnabled() ? 0.35 : 0.08];
}
static inline UIColor* PenumbraAccentColor(void) { return PenumbraColor(0xF5B544, 1); }
static inline UIColor* PenumbraOnAccentColor(void) { return PenumbraColor(0x1A1408, 1); }
static inline UIColor* PenumbraTextColor(void) { return PenumbraColor(0xF2F3F5, 1); }
static inline UIColor* PenumbraMutedTextColor(void) { return PenumbraColor(0xC9CDD4, 1); }
static inline UIColor* PenumbraSecondaryTextColor(void) { return PenumbraColor(0x9AA0AB, 1); }
static inline UIColor* PenumbraOnlineColor(void) { return PenumbraColor(0x4ADE80, 1); }
static inline UIColor* PenumbraOnlineTextColor(void) { return PenumbraColor(0x7EE2A0, 1); }
static inline UIColor* PenumbraOfflineColor(void) { return PenumbraColor(0x5B616C, 1); }

// Press feedback for cards and covers: shrinks on touch down, springs back on
// release. Critically damped and started from the on-screen state, so a press
// can be interrupted and reversed at any time. Skipped with Reduce Motion.
static inline void PenumbraAnimatePress(UIView* view, BOOL pressed) {
    CGAffineTransform transform = pressed ? CGAffineTransformMakeScale(0.96, 0.96) : CGAffineTransformIdentity;
    if (UIAccessibilityIsReduceMotionEnabled()) {
        view.alpha = pressed ? 0.7 : 1.0;
        return;
    }
    [UIView animateWithDuration:pressed ? 0.2 : 0.35
                          delay:0
         usingSpringWithDamping:1.0
          initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        view.transform = transform;
    } completion:nil];
}

// A muted tile color picked from the name, for games without box art
static inline UIColor* PenumbraTileColor(NSString* name) {
    static const uint32_t tiles[] = { 0x1E2633, 0x3A2E1E, 0x2E1F2B, 0x1D2A24, 0x2B1D1D, 0x24203A };
    return PenumbraColor(tiles[name.hash % (sizeof(tiles) / sizeof(tiles[0]))], 1);
}
