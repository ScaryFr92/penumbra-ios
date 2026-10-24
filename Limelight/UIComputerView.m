//
//  UIComputerView.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/22/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "UIComputerView.h"
#import "PenumbraTheme.h"

// A rounded card with an icon, the PC name and a status line
@implementation UIComputerView {
    TemporaryHost* _host;
    id<HostCallback> _callback;
    UIView* _iconBackground;
    UIImageView* _icon;
    UIActivityIndicatorView* _spinner;
    UILabel* _nameLabel;
    UIView* _statusDot;
    UILabel* _statusLabel;
    UILabel* _actionLabel;
    CGFloat _scale;
}
static const float REFRESH_CYCLE = 2.0f;

- (id) init {
    self = [super init];

    // Everything is laid out for an iPhone and scaled up for bigger screens
#if TARGET_OS_TV
    _scale = 1.9;
#else
    _scale = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ? 1.2 : 1.0;
#endif
    CGFloat s = _scale;
    CGFloat padding = 18 * s;

    self.frame = CGRectMake(0, 0, 176 * s, 168 * s);
    CGSize size = self.bounds.size;

    self.backgroundColor = PenumbraSurfaceColor();
    self.layer.cornerRadius = 22 * s;
    self.layer.borderWidth = 1;
    self.layer.borderColor = PenumbraHairlineColor().CGColor;
    self.layer.shadowColor = [UIColor blackColor].CGColor;
    self.layer.shadowOffset = CGSizeMake(0, 10 * s);
    self.layer.shadowRadius = 15 * s;

    _iconBackground = [[UIView alloc] initWithFrame:CGRectMake(padding, padding, 48 * s, 48 * s)];
    _iconBackground.layer.cornerRadius = 14 * s;
    _iconBackground.userInteractionEnabled = NO;
    _icon = [[UIImageView alloc] initWithFrame:CGRectInset(_iconBackground.bounds, 11 * s, 11 * s)];
    _icon.contentMode = UIViewContentModeScaleAspectFit;
    [_iconBackground addSubview:_icon];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.color = PenumbraSecondaryTextColor();
    _spinner.center = _iconBackground.center;
    _spinner.hidesWhenStopped = YES;
    _spinner.userInteractionEnabled = NO;

    _nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(padding, size.height - 62 * s, size.width - 2 * padding, 22 * s)];
    _nameLabel.font = [UIFont systemFontOfSize:16 * s weight:UIFontWeightBold];
    _nameLabel.textColor = PenumbraTextColor();

    _statusDot = [[UIView alloc] initWithFrame:CGRectMake(padding, size.height - 29 * s, 7 * s, 7 * s)];
    _statusDot.layer.cornerRadius = 3.5 * s;
    _statusDot.userInteractionEnabled = NO;

    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(padding + 13 * s, size.height - 35 * s, size.width - 2 * padding - 13 * s, 18 * s)];
    _statusLabel.font = [UIFont systemFontOfSize:12 * s weight:UIFontWeightMedium];

    _actionLabel = [[UILabel alloc] initWithFrame:_statusLabel.frame];
    _actionLabel.font = [UIFont systemFontOfSize:12 * s weight:UIFontWeightSemibold];
    _actionLabel.textColor = PenumbraAccentColor();
    _actionLabel.textAlignment = NSTextAlignmentRight;
    _actionLabel.hidden = YES;

    [self addSubview:_iconBackground];
    [self addSubview:_spinner];
    [self addSubview:_nameLabel];
    [self addSubview:_statusDot];
    [self addSubview:_statusLabel];
    [self addSubview:_actionLabel];

#if !TARGET_OS_TV
    [self addTarget:self action:@selector(cardPressed) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [self addTarget:self action:@selector(cardReleased) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];

    if (@available(iOS 13.4.1, *)) {
        // Allow the button style to change when moused over
        self.pointerInteractionEnabled = YES;
    }
#endif

    return self;
}

- (void) cardPressed {
    [UIView animateWithDuration:0.12 animations:^{
        self.transform = CGAffineTransformMakeScale(0.96, 0.96);
    }];
}

- (void) cardReleased {
    [UIView animateWithDuration:0.2 animations:^{
        self.transform = CGAffineTransformIdentity;
    }];
}

#if TARGET_OS_TV
// The focused card grows and lights up with the accent, like the rest of tvOS
- (void)didUpdateFocusInContext:(UIFocusUpdateContext *)context withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator {
    [super didUpdateFocusInContext:context withAnimationCoordinator:coordinator];

    BOOL focused = context.nextFocusedView == self;
    [coordinator addCoordinatedAnimations:^{
        self.transform = focused ? CGAffineTransformMakeScale(1.08, 1.08) : CGAffineTransformIdentity;
        self.backgroundColor = focused ? PenumbraColor(0x22252E, 1) : (self->_host != nil ? PenumbraSurfaceColor() : [UIColor clearColor]);
        self.layer.shadowOpacity = focused ? 0.6 : 0;
    } completion:nil];
}
#endif

- (id) initForAddWithCallback:(id<HostCallback>)callback {
    self = [self init];
    _callback = callback;

    [self addTarget:self action:@selector(addClicked) forControlEvents:UIControlEventPrimaryActionTriggered];

    CGFloat s = _scale;
    CGSize size = self.bounds.size;
    self.backgroundColor = [UIColor clearColor];
    self.layer.borderWidth = 0;

    CAShapeLayer* dashedBorder = [CAShapeLayer layer];
    dashedBorder.path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(self.bounds, 0.75, 0.75) cornerRadius:22 * s].CGPath;
    dashedBorder.fillColor = nil;
    dashedBorder.strokeColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
    dashedBorder.lineWidth = 1.5 * s;
    dashedBorder.lineDashPattern = @[@(6 * s), @(5 * s)];
    [self.layer addSublayer:dashedBorder];

    _iconBackground.frame = CGRectMake((size.width - 44 * s) / 2, size.height / 2 - 34 * s, 44 * s, 44 * s);
    _iconBackground.layer.cornerRadius = 22 * s;
    _iconBackground.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
    _icon.frame = CGRectInset(_iconBackground.bounds, 12 * s, 12 * s);
    _icon.image = [UIImage systemImageNamed:@"plus"];
    _icon.tintColor = PenumbraMutedTextColor();

    _nameLabel.frame = CGRectMake(18 * s, CGRectGetMaxY(_iconBackground.frame) + 10 * s, size.width - 36 * s, 20 * s);
    _nameLabel.textAlignment = NSTextAlignmentCenter;
    _nameLabel.font = [UIFont systemFontOfSize:14 * s weight:UIFontWeightSemibold];
    _nameLabel.textColor = PenumbraMutedTextColor();
    _nameLabel.text = @"Ajouter un PC";

    _statusDot.hidden = YES;
    _statusLabel.hidden = YES;

    return self;
}

- (id) initWithComputer:(TemporaryHost*)host andCallback:(id<HostCallback>)callback {
    self = [self init];
    _host = host;
    _callback = callback;

    // Use UIContextMenuInteraction on iOS and a standard UILongPressGestureRecognizer on tvOS
#if !TARGET_OS_TV
    UIContextMenuInteraction* rightClickInteraction = [[UIContextMenuInteraction alloc] initWithDelegate:self];
    [self addInteraction:rightClickInteraction];
#else
    UILongPressGestureRecognizer* longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(hostLongClicked:)];
    [self addGestureRecognizer:longPressRecognizer];
#endif

    [self addTarget:self action:@selector(hostClicked) forControlEvents:UIControlEventPrimaryActionTriggered];

    [self updateContentsForHost:host];

    return self;
}

- (void)didMoveToSuperview {
    // Start our update loop when we are added to our cell
    if (self.superview != nil && _host != nil) {
        [self updateLoop];
    }
}

- (void) setIconNamed:(NSString*)name highlighted:(BOOL)highlighted {
    _icon.image = name != nil ? [UIImage systemImageNamed:name] : nil;
    _icon.tintColor = highlighted ? PenumbraAccentColor() : PenumbraMutedTextColor();
    _iconBackground.backgroundColor = highlighted ? [PenumbraAccentColor() colorWithAlphaComponent:0.14] : [UIColor colorWithWhite:1 alpha:0.06];
}

- (void) setStatus:(NSString*)status color:(UIColor*)color dotColor:(UIColor*)dotColor {
    _statusLabel.text = status;
    _statusLabel.textColor = color;
    _statusDot.hidden = dotColor == nil;
    _statusDot.backgroundColor = dotColor;

    // Without a dot, the status text starts where the dot would be
    CGRect frame = _statusLabel.frame;
    frame.origin.x = (dotColor != nil ? 31 : 18) * _scale;
    _statusLabel.frame = frame;
}

- (void) updateContentsForHost:(TemporaryHost*)host {
    _nameLabel.text = host.name;
    _nameLabel.textColor = PenumbraTextColor();
    _actionLabel.hidden = YES;
    self.layer.borderColor = PenumbraHairlineColor().CGColor;
#if !TARGET_OS_TV
    // On tvOS the shadow follows focus instead
    self.layer.shadowOpacity = 0;
#endif

    if (host.state == StateOnline) {
        [_spinner stopAnimating];

        if (host.pairState == PairStateUnpaired) {
            [self setIconNamed:@"lock" highlighted:NO];
            [self setStatus:@"Sélectionner pour appairer" color:PenumbraSecondaryTextColor() dotColor:nil];
        }
        else {
            [self setIconNamed:@"desktopcomputer" highlighted:YES];
            NSString* status = host.appList.count > 0 ? [NSString stringWithFormat:@"En ligne · %lu jeux", (unsigned long)host.appList.count] : @"En ligne";
            [self setStatus:status color:PenumbraOnlineTextColor() dotColor:PenumbraOnlineColor()];
            self.layer.borderColor = [PenumbraAccentColor() colorWithAlphaComponent:0.45].CGColor;
#if !TARGET_OS_TV
            self.layer.shadowOpacity = 0.45;
#endif
        }
    }
    else if (host.state == StateOffline) {
        [_spinner stopAnimating];
        [self setIconNamed:@"desktopcomputer" highlighted:NO];
        _nameLabel.textColor = PenumbraMutedTextColor();
        [self setStatus:@"Hors ligne" color:PenumbraSecondaryTextColor() dotColor:PenumbraOfflineColor()];

        // Selecting an offline PC opens its menu, which offers Wake-on-LAN
        _actionLabel.text = @"Réveiller";
        _actionLabel.hidden = NO;
    }
    else {
        [self setIconNamed:nil highlighted:NO];
        [_spinner startAnimating];
        [self setStatus:@"Connexion…" color:PenumbraSecondaryTextColor() dotColor:nil];
    }
}

- (void) updateLoop {
    // Stop immediately if the view has been detached
    if (self.superview == nil) {
        return;
    }

    [self updateContentsForHost:_host];

    // Queue the next refresh cycle
    [self performSelector:@selector(updateLoop) withObject:self afterDelay:REFRESH_CYCLE];
}

- (void) hostLongClicked:(UILongPressGestureRecognizer*)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [_callback hostLongClicked:_host view:self];
    }
}

#if !TARGET_OS_TV
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                        configurationForMenuAtLocation:(CGPoint)location {
    // We don't want to trigger the primary action at this point, so cancel
    // tracking touch on this view now. This will also have the (intended)
    // effect of removing the touch highlight on this view.
    [self cancelTrackingWithEvent:nil];
    [self cardReleased];

    [_callback hostLongClicked:_host view:self];
    return nil;
}
#endif

- (void) hostClicked {
    [_callback hostClicked:_host view:self];
}

- (void) addClicked {
    [_callback addHostClicked];
}

@end
