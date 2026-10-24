//
//  UIAppView.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/22/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "UIAppView.h"
#import "AppAssetManager.h"
#import "PenumbraTheme.h"

static const float REFRESH_CYCLE = 1.0f;

#if TARGET_OS_TV
static const CGFloat COVER_WIDTH = 200;
static const CGFloat COVER_HEIGHT = 265;
static const CGFloat TITLE_HEIGHT = 50;
static const CGFloat TITLE_FONT_SIZE = 24;
#else
static const CGFloat COVER_WIDTH = 150;
static const CGFloat COVER_HEIGHT = 200;
static const CGFloat TITLE_HEIGHT = 34;
static const CGFloat TITLE_FONT_SIZE = 18;
#endif

// A box art cover with the game's name under it. Games without box art get a
// tinted tile with their name, and the running game gets a golden ring and badge.
@implementation UIAppView {
    TemporaryApp* _app;
    UILabel* _appLabel;
    UILabel* _runningBadge;
    UIImageView* _appImage;
    UILabel* _titleLabel;
    NSCache* _artCache;
    id<AppCallback> _callback;
}

+ (CGSize) preferredSize {
    return CGSizeMake(COVER_WIDTH, COVER_HEIGHT + TITLE_HEIGHT);
}

// The share of the view's height taken by the cover
+ (CGFloat) coverHeightRatio {
    return COVER_HEIGHT / (COVER_HEIGHT + TITLE_HEIGHT);
}

- (id) initWithApp:(TemporaryApp*)app cache:(NSCache*)cache andCallback:(id<AppCallback>)callback {
    self = [super init];
    _app = app;
    _callback = callback;
    _artCache = cache;

    self.frame = CGRectMake(0, 0, [UIAppView preferredSize].width, [UIAppView preferredSize].height);

    [self setAlpha:app.hidden ? 0.4 : 1.0];

    _appImage = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, COVER_WIDTH, COVER_HEIGHT)];
    _appImage.contentMode = UIViewContentModeScaleAspectFill;
    _appImage.backgroundColor = PenumbraTileColor(app.name);
#if !TARGET_OS_TV
    _appImage.layer.cornerRadius = 14 * COVER_WIDTH / 104;
    _appImage.clipsToBounds = YES;
#endif
    [self addSubview:_appImage];

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(2, COVER_HEIGHT + 8, COVER_WIDTH - 4, TITLE_HEIGHT - 8)];
    _titleLabel.text = app.name;
    _titleLabel.font = [UIFont systemFontOfSize:TITLE_FONT_SIZE weight:UIFontWeightSemibold];
    _titleLabel.textColor = PenumbraTextColor();
    _titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:_titleLabel];

    // Use UIContextMenuInteraction on iOS 13.0+ and a standard UILongPressGestureRecognizer
    // for tvOS devices and iOS prior to 13.0.
#if !TARGET_OS_TV
    if (@available(iOS 13.0, *)) {
        UIContextMenuInteraction* rightClickInteraction = [[UIContextMenuInteraction alloc] initWithDelegate:self];
        [self addInteraction:rightClickInteraction];
    }
    else
#endif
    {
        UILongPressGestureRecognizer* longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(appLongClicked:)];
        [self addGestureRecognizer:longPressRecognizer];
    }

    [self addTarget:self action:@selector(appClicked:) forControlEvents:UIControlEventPrimaryActionTriggered];

    [self addTarget:self action:@selector(buttonSelected:) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(buttonDeselected:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchCancel | UIControlEventTouchDragExit];

#if TARGET_OS_TV
    _appImage.adjustsImageWhenAncestorFocused = YES;
#else
    // Rasterizing the cell layer increases rendering performance by quite a bit
    // but we want it unrasterized for tvOS where it must be scaled.
    self.layer.shouldRasterize = YES;
    self.layer.rasterizationScale = [UIScreen mainScreen].scale;

    if (@available(iOS 13.4.1, *)) {
        // Allow the button style to change when moused over
        self.pointerInteractionEnabled = YES;
    }
#endif

    [self updateAppImage];

    return self;
}

- (void)didMoveToSuperview {
    // Start our update loop when we are added to our cell
    if (self.superview != nil) {
        [self updateLoop];
    }
}

- (void) appClicked:(UIView *)view {
    [_callback appClicked:_app view:view];
}

- (void) appLongClicked:(UILongPressGestureRecognizer*)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [_callback appLongClicked:_app view:self];
    }
}

#if !TARGET_OS_TV
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                        configurationForMenuAtLocation:(CGPoint)location {
    // We don't want to trigger the primary action at this point, so cancel
    // tracking touch on this view now. This will also have the (intended)
    // effect of removing the touch highlight on this view.
    [self cancelTrackingWithEvent:nil];
    [self buttonDeselected:self];

    [_callback appLongClicked:_app view:self];
    return nil;
}
#endif

- (BOOL) isRunning {
    return [_app.id isEqualToString:_app.host.currentGame];
}

- (void) updateAppImage {
    if (_runningBadge != nil) {
        [_runningBadge removeFromSuperview];
        _runningBadge = nil;
    }
    if (_appLabel != nil) {
        [_appLabel removeFromSuperview];
        _appLabel = nil;
    }

    BOOL noAppImage = false;

    // First check the memory cache
    UIImage* appImage = [_artCache objectForKey:_app];
    if (appImage == nil) {
        // Next try to load from the on disk cache
        appImage = [UIImage imageWithContentsOfFile:[AppAssetManager boxArtPathForApp:_app]];
        if (appImage != nil) {
            [_artCache setObject:appImage forKey:_app];
        }
    }

    if (appImage != nil) {
        // This size of image might be blank image received from GameStream.
        // TODO: Improve no-app image detection
        if (!(appImage.size.width == 130.f && appImage.size.height == 180.f) && // GFE 2.0
            !(appImage.size.width == 628.f && appImage.size.height == 888.f)) { // GFE 3.0
            [_appImage setImage:appImage];
        } else {
            noAppImage = true;
        }
    } else {
        noAppImage = true;
    }

    CGFloat padding = COVER_WIDTH * 0.08;

    if (noAppImage) {
        // The game's name sits at the bottom of its tile
        _appLabel = [[UILabel alloc] initWithFrame:CGRectMake(padding, padding, COVER_WIDTH - 2 * padding, COVER_HEIGHT - 2 * padding)];
        _appLabel.text = _app.name;
        _appLabel.textColor = [UIColor colorWithWhite:1 alpha:0.9];
        _appLabel.font = [UIFont systemFontOfSize:TITLE_FONT_SIZE + 2 weight:UIFontWeightHeavy];
        _appLabel.numberOfLines = 0;
        _appLabel.lineBreakMode = NSLineBreakByWordWrapping;
        CGSize textSize = [_appLabel sizeThatFits:CGSizeMake(_appLabel.frame.size.width, CGFLOAT_MAX)];
        CGFloat textHeight = MIN(textSize.height, _appLabel.frame.size.height);
        _appLabel.frame = CGRectMake(padding, COVER_HEIGHT - padding - textHeight, COVER_WIDTH - 2 * padding, textHeight);
    }

    if ([self isRunning]) {
        _runningBadge = [[UILabel alloc] init];
        _runningBadge.text = @"En cours";
        _runningBadge.font = [UIFont systemFontOfSize:TITLE_FONT_SIZE - 4 weight:UIFontWeightBold];
        _runningBadge.textColor = PenumbraOnAccentColor();
        _runningBadge.backgroundColor = PenumbraAccentColor();
        _runningBadge.textAlignment = NSTextAlignmentCenter;
        [_runningBadge sizeToFit];
        CGFloat badgeHeight = _runningBadge.frame.size.height + 8;
        _runningBadge.frame = CGRectMake(padding, padding, _runningBadge.frame.size.width + 18, badgeHeight);
        _runningBadge.layer.cornerRadius = badgeHeight / 2;
        _runningBadge.clipsToBounds = YES;

        _appImage.layer.borderWidth = 3;
        _appImage.layer.borderColor = PenumbraAccentColor().CGColor;
    }
    else {
        _appImage.layer.borderWidth = 0;
    }

#if TARGET_OS_TV
    [_appImage.overlayContentView addSubview:_appLabel];
    [_appImage.overlayContentView addSubview:_runningBadge];
#else
    [self addSubview:_appLabel];
    [self addSubview:_runningBadge];
#endif
}

- (void) buttonSelected:(id)sender {
    [UIView animateWithDuration:0.12 animations:^{
        self->_appImage.transform = CGAffineTransformMakeScale(0.95, 0.95);
    }];
}
- (void) buttonDeselected:(id)sender {
    [UIView animateWithDuration:0.2 animations:^{
        self->_appImage.transform = CGAffineTransformIdentity;
    }];
}

- (void) updateLoop {
    // Stop immediately if the view has been detached
    if (self.superview == nil) {
        return;
    }

    // Update the app image if neccessary
    if ((_runningBadge != nil) != [self isRunning]) {
        [self updateAppImage];
    }

    // Show no shadow for hidden apps. Because we adjust the opacity of the
    // cells for hidden apps, it makes them look bad when the shadow draws
    // through the app tile.
    self.superview.layer.shadowOpacity = _app.hidden ? 0.0f : 0.45f;

    // Update opacity if neccessary
    [self setAlpha:_app.hidden ? 0.4 : 1.0];

    // Queue the next refresh cycle
    [self performSelector:@selector(updateLoop) withObject:self afterDelay:REFRESH_CYCLE];
}

@end
