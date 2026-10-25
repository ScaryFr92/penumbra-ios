//
//  StreamFrameViewController.m
//  Moonlight
//
//  Created by Diego Waxemberg on 1/18/14.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "StreamFrameViewController.h"
#import "MainFrameViewController.h"
#import "VideoDecoderRenderer.h"
#import "StreamManager.h"
#import "HttpManager.h"
#import "ControllerSupport.h"
#import "DataManager.h"
#import "../PenumbraSettings.h"

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <Limelight.h>

#if TARGET_OS_TV
#import <AVFoundation/AVDisplayCriteria.h>
#import <AVKit/AVDisplayManager.h>
#import <AVKit/UIWindow.h>
#endif

@interface AVDisplayCriteria()
@property(readonly) int videoDynamicRange;
@property(readonly, nonatomic) float refreshRate;
- (id)initWithRefreshRate:(float)arg1 videoDynamicRange:(int)arg2;
@end

static BOOL streamActive;

#if !TARGET_OS_TV
// Presses the keys in order and releases them in reverse, like a person typing a shortcut
static void sendKeyCombo(NSArray<NSNumber*>* keys) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        char modifiers = 0;
        for (NSNumber* key in keys) {
            switch (key.shortValue) {
                case 0xA0: modifiers |= MODIFIER_SHIFT; break;
                case 0xA2: modifiers |= MODIFIER_CTRL; break;
                case 0xA4: modifiers |= MODIFIER_ALT; break;
                case 0x5B: modifiers |= MODIFIER_META; break;
            }
            LiSendKeyboardEvent(key.shortValue, KEY_ACTION_DOWN, modifiers);
        }
        usleep(50 * 1000);
        for (NSNumber* key in [keys reverseObjectEnumerator]) {
            LiSendKeyboardEvent(key.shortValue, KEY_ACTION_UP, modifiers);
        }
    });
}

// Parses a shortcut typed by the user like "ctrl+shift+esc" or "win+d" into Windows key codes.
// Returns nil if any part is unknown.
static NSArray<NSNumber*>* parseKeyCombo(NSString* text) {
    static NSDictionary<NSString*, NSNumber*>* namedKeys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        namedKeys = @{
            @"ctrl": @0xA2, @"control": @0xA2, @"alt": @0xA4, @"shift": @0xA0,
            @"win": @0x5B, @"cmd": @0x5B, @"meta": @0x5B,
            @"esc": @0x1B, @"escape": @0x1B, @"tab": @0x09, @"enter": @0x0D, @"space": @0x20,
            @"del": @0x2E, @"delete": @0x2E, @"backspace": @0x08, @"insert": @0x2D,
            @"up": @0x26, @"down": @0x28, @"left": @0x25, @"right": @0x27,
            @"home": @0x24, @"end": @0x23, @"pgup": @0x21, @"pgdn": @0x22, @"printscreen": @0x2C,
        };
    });

    NSMutableArray<NSNumber*>* keys = [NSMutableArray array];
    for (NSString* part in [[text lowercaseString] componentsSeparatedByString:@"+"]) {
        NSString* name = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        unichar c = name.length == 1 ? [name characterAtIndex:0] : 0;
        if (namedKeys[name] != nil) {
            [keys addObject:namedKeys[name]];
        }
        else if (c >= 'a' && c <= 'z') {
            [keys addObject:@(c - 'a' + 0x41)];
        }
        else if (c >= '0' && c <= '9') {
            [keys addObject:@(c)];
        }
        else if (name.length >= 2 && [name characterAtIndex:0] == 'f' && [name substringFromIndex:1].intValue >= 1 && [name substringFromIndex:1].intValue <= 24) {
            [keys addObject:@(0x70 + [name substringFromIndex:1].intValue - 1)];
        }
        else {
            return nil;
        }
    }
    return keys;
}
#endif

@implementation StreamFrameViewController {
    ControllerSupport *_controllerSupport;
    StreamManager *_streamMan;
    TemporarySettings *_settings;
    NSTimer *_inactivityTimer;
    NSTimer *_statsUpdateTimer;
    UITapGestureRecognizer *_menuTapGestureRecognizer;
    UITapGestureRecognizer *_menuDoubleTapGestureRecognizer;
    UITapGestureRecognizer *_playPauseTapGestureRecognizer;
    UITextView *_overlayView;
    UILabel *_stageLabel;
    UILabel *_tipLabel;
    UIActivityIndicatorView *_spinner;
    StreamView *_streamView;
    UIScrollView *_scrollView;
    BOOL _userIsInteracting;
    CGSize _keyboardSize;

    NSString *_hostMetricsText;
    BOOL _hostMetricsInFlight;
    BOOL _hostMetricsStopped;
    int _hostMetricsFailures;
    CFTimeInterval _hostMetricsNextPoll;
    
#if !TARGET_OS_TV
    UIScreenEdgePanGestureRecognizer *_exitSwipeRecognizer;
#endif
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

#if !TARGET_OS_TV
    [[self revealViewController] setPrimaryViewController:self];

    // Let the stream follow the device into portrait
    streamActive = YES;
    [self refreshSupportedOrientations];
#endif
}

+ (BOOL)isStreamActive {
    return streamActive;
}

#if !TARGET_OS_TV
- (void)refreshSupportedOrientations {
    if (@available(iOS 16.0, *)) {
        [self.view.window.rootViewController setNeedsUpdateOfSupportedInterfaceOrientations];
        if (!streamActive) {
            UIWindowSceneGeometryPreferencesIOS* preferences = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscape];
            [self.view.window.windowScene requestGeometryUpdateWithPreferences:preferences errorHandler:nil];
        }
    }
    else {
        [UIViewController attemptRotationToDeviceOrientation];
    }
}
#endif

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    // Follow rotations between landscape and portrait
    if (_scrollView != nil) {
        _scrollView.frame = self.view.bounds;
        if (_scrollView.zoomScale == 1.0f) {
            _streamView.frame = _scrollView.bounds;
        }
    }
    else {
        _streamView.frame = self.view.bounds;
    }
}

#if TARGET_OS_TV
- (void)controllerPauseButtonPressed:(id)sender { }
- (void)controllerPauseButtonDoublePressed:(id)sender {
    Log(LOG_I, @"Menu double-pressed -- backing out of stream");
    [self returnToMainFrame];
}
- (void)controllerPlayPauseButtonPressed:(id)sender {
    Log(LOG_I, @"Play/Pause button pressed -- backing out of stream");
    [self returnToMainFrame];
}
#endif


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self.navigationController setNavigationBarHidden:YES animated:YES];
    
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    _settings = [[[DataManager alloc] init] getSettings];
    
    _stageLabel = [[UILabel alloc] init];
    [_stageLabel setUserInteractionEnabled:NO];
    [_stageLabel setText:[NSString stringWithFormat:@"Starting %@...", self.streamConfig.appName]];
    [_stageLabel sizeToFit];
    _stageLabel.textAlignment = NSTextAlignmentCenter;
    _stageLabel.textColor = [UIColor whiteColor];
    _stageLabel.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height / 2);
    
    _spinner = [[UIActivityIndicatorView alloc] init];
    [_spinner setUserInteractionEnabled:NO];
#if TARGET_OS_TV
    [_spinner setActivityIndicatorViewStyle:UIActivityIndicatorViewStyleWhiteLarge];
#else
    [_spinner setActivityIndicatorViewStyle:UIActivityIndicatorViewStyleWhite];
#endif
    [_spinner sizeToFit];
    [_spinner startAnimating];
    _spinner.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height / 2 - _stageLabel.frame.size.height - _spinner.frame.size.height);
    
    _controllerSupport = [[ControllerSupport alloc] initWithConfig:self.streamConfig delegate:self];
    _inactivityTimer = nil;
    
    _streamView = [[StreamView alloc] initWithFrame:self.view.frame];
    [_streamView setupStreamView:_controllerSupport interactionDelegate:self config:self.streamConfig];
    
#if TARGET_OS_TV
    if (!_menuTapGestureRecognizer || !_menuDoubleTapGestureRecognizer || !_playPauseTapGestureRecognizer) {
        _menuTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPauseButtonPressed:)];
        _menuTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypeMenu)];

        _playPauseTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPlayPauseButtonPressed:)];
        _playPauseTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypePlayPause)];
        
        _menuDoubleTapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(controllerPauseButtonDoublePressed:)];
        _menuDoubleTapGestureRecognizer.numberOfTapsRequired = 2;
        [_menuTapGestureRecognizer requireGestureRecognizerToFail:_menuDoubleTapGestureRecognizer];
        _menuDoubleTapGestureRecognizer.allowedPressTypes = @[@(UIPressTypeMenu)];
    }
    
    [self.view addGestureRecognizer:_menuTapGestureRecognizer];
    [self.view addGestureRecognizer:_menuDoubleTapGestureRecognizer];
    [self.view addGestureRecognizer:_playPauseTapGestureRecognizer];

#else
    _exitSwipeRecognizer = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(edgeSwiped:)];
    _exitSwipeRecognizer.edges = UIRectEdgeLeft;
    _exitSwipeRecognizer.delaysTouchesBegan = NO;
    _exitSwipeRecognizer.delaysTouchesEnded = NO;
    
    [self.view addGestureRecognizer:_exitSwipeRecognizer];
#endif
    
    _tipLabel = [[UILabel alloc] init];
    [_tipLabel setUserInteractionEnabled:NO];
    
#if TARGET_OS_TV
    [_tipLabel setText:@"Tip: Tap the Play/Pause button on the Apple TV Remote to disconnect from your PC"];
#else
    [_tipLabel setText:@"Astuce : glisse depuis le bord gauche pour ouvrir le menu"];
#endif
    
    [_tipLabel sizeToFit];
    _tipLabel.textColor = [UIColor whiteColor];
    _tipLabel.textAlignment = NSTextAlignmentCenter;
    _tipLabel.center = CGPointMake(self.view.frame.size.width / 2, self.view.frame.size.height * 0.9);
    
    _streamMan = [[StreamManager alloc] initWithConfig:self.streamConfig
                                            renderView:_streamView
                                   connectionCallbacks:self];
    NSOperationQueue* opQueue = [[NSOperationQueue alloc] init];
    [opQueue addOperation:_streamMan];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(applicationDidBecomeActive:)
                                                 name: UIApplicationDidBecomeActiveNotification
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(applicationDidEnterBackground:)
                                                 name: UIApplicationDidEnterBackgroundNotification
                                               object: nil];

#if 0
    // FIXME: This doesn't work reliably on iPad for some reason. Showing and hiding the keyboard
    // several times in a row will not correctly restore the state of the UIScrollView.
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(keyboardWillShow:)
                                                 name: UIKeyboardWillShowNotification
                                               object: nil];
    
    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(keyboardWillHide:)
                                                 name: UIKeyboardWillHideNotification
                                               object: nil];
#endif
    
    // Only enable scroll and zoom in absolute touch mode
    if (_settings.absoluteTouchMode) {
        _scrollView = [[UIScrollView alloc] initWithFrame:self.view.frame];
#if !TARGET_OS_TV
        [_scrollView.panGestureRecognizer setMinimumNumberOfTouches:2];
#endif
        [_scrollView setShowsHorizontalScrollIndicator:NO];
        [_scrollView setShowsVerticalScrollIndicator:NO];
        [_scrollView setDelegate:self];
        [_scrollView setMaximumZoomScale:10.0f];
        
        // Add StreamView inside a UIScrollView for absolute mode
        [_scrollView addSubview:_streamView];
        [self.view addSubview:_scrollView];
    }
    else {
        // Add StreamView directly in relative mode
        [self.view addSubview:_streamView];
    }
    
    [self.view addSubview:_stageLabel];
    [self.view addSubview:_spinner];
    [self.view addSubview:_tipLabel];
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return _streamView;
}

- (void)willMoveToParentViewController:(UIViewController *)parent {
    // Only cleanup when we're being destroyed
    if (parent == nil) {
        streamActive = NO;
        [_controllerSupport cleanup];
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        [_streamMan stopStream];
        if (_inactivityTimer != nil) {
            [_inactivityTimer invalidate];
            _inactivityTimer = nil;
        }
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    }
}

#if 0
- (void)keyboardWillShow:(NSNotification *)notification {
    _keyboardSize = [[[notification userInfo] objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;

    [UIView animateWithDuration:0.3 animations:^{
        CGRect frame = self->_scrollView.frame;
        frame.size.height -= self->_keyboardSize.height;
        self->_scrollView.frame = frame;
    }];
}

-(void)keyboardWillHide:(NSNotification *)notification {
    // NOTE: UIKeyboardFrameEndUserInfoKey returns a different keyboard size
    // than UIKeyboardFrameBeginUserInfoKey, so it's unsuitable for use here
    // to undo the changes made by keyboardWillShow.
    
    [UIView animateWithDuration:0.3 animations:^{
        CGRect frame = self->_scrollView.frame;
        frame.size.height += self->_keyboardSize.height;
        self->_scrollView.frame = frame;
    }];
}
#endif

- (void)updateStatsOverlay {
    NSString* overlayText = [self->_streamMan getStatsOverlayText];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self pollHostMetrics];
        if (overlayText != nil && self->_hostMetricsText != nil) {
            [self updateOverlayText:[NSString stringWithFormat:@"%@\n%@", overlayText, self->_hostMetricsText]];
        }
        else {
            [self updateOverlayText:overlayText];
        }
    });
}

static NSNumber* metricNumber(id object, NSString* key) {
    id value = [object isKindOfClass:[NSDictionary class]] ? object[key] : nil;
    return [value isKindOfClass:[NSNumber class]] ? value : nil;
}

// Hardware metrics v1: the host's CPU and GPU load, only when the host advertises it.
// One request at a time, no faster than the host's interval, backing off on errors.
- (void)pollHostMetrics {
    if (!self.streamConfig.hostMetricsSupported || _hostMetricsStopped || _hostMetricsInFlight || CACurrentMediaTime() < _hostMetricsNextPoll) {
        return;
    }

    _hostMetricsInFlight = YES;
    StreamConfiguration* config = self.streamConfig;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        HttpManager* hMan = [[HttpManager alloc] initWithAddress:config.host httpsPort:config.httpsPort serverCert:config.serverCert];
        HttpResponse* response = [[HttpResponse alloc] init];
        [hMan executeRequestSynchronously:[HttpRequest requestForResponse:response withUrlRequest:[hMan newHardwareMetricsRequest]]];
        id json = response.data != nil ? [NSJSONSerialization JSONObjectWithData:response.data options:0 error:nil] : nil;

        dispatch_async(dispatch_get_main_queue(), ^{
            self->_hostMetricsInFlight = NO;

            if (![json isKindOfClass:[NSDictionary class]] || json[@"error"] != nil) {
                // Back off, and give up if the host keeps refusing (metrics off, no video yet...)
                self->_hostMetricsText = nil;
                self->_hostMetricsNextPoll = CACurrentMediaTime() + 5;
                self->_hostMetricsStopped = ++self->_hostMetricsFailures >= 3;
                return;
            }

            self->_hostMetricsFailures = 0;
            self->_hostMetricsNextPoll = CACurrentMediaTime() + MAX([metricNumber(json, @"interval_ms") doubleValue], 1000) / 1000;

            NSMutableArray<NSString*>* parts = [NSMutableArray array];
            NSNumber* cpu = metricNumber(json[@"cpu"], @"cpu_usage_percent");
            if (cpu != nil) {
                [parts addObject:[NSString stringWithFormat:@"CPU %.0f%%", cpu.doubleValue]];
            }

            id gpus = json[@"gpus"];
            id gpu = [gpus isKindOfClass:[NSArray class]] ? [gpus firstObject] : nil;
            id gpuMetrics = [gpu isKindOfClass:[NSDictionary class]] ? gpu[@"metrics"] : nil;
            NSNumber* gpuUsage = metricNumber(gpuMetrics, @"gpu_usage_percent");
            NSNumber* encoderUsage = metricNumber(gpuMetrics, @"gpu_encoder_percent");
            NSNumber* temperature = metricNumber(gpuMetrics, @"gpu_temperature_c");
            NSNumber* vramUsed = metricNumber(gpuMetrics, @"gpu_vram_used_mb");
            if (gpuUsage != nil) {
                [parts addObject:[NSString stringWithFormat:@"GPU %.0f%%", gpuUsage.doubleValue]];
            }
            if (encoderUsage != nil) {
                [parts addObject:[NSString stringWithFormat:@"Encodeur %.0f%%", encoderUsage.doubleValue]];
            }
            if (temperature != nil) {
                [parts addObject:[NSString stringWithFormat:@"%.0f °C", temperature.doubleValue]];
            }
            if (vramUsed != nil) {
                [parts addObject:[NSString stringWithFormat:@"VRAM %.1f Go", vramUsed.doubleValue / 1024]];
            }

            self->_hostMetricsText = parts.count > 0 ? [@"PC : " stringByAppendingString:[parts componentsJoinedByString:@" · "]] : nil;
        });
    });
}

- (void)updateOverlayText:(NSString*)text {
    if (_overlayView == nil) {
        _overlayView = [[UITextView alloc] init];
#if !TARGET_OS_TV
        [_overlayView setEditable:NO];
#endif
        [_overlayView setUserInteractionEnabled:NO];
        [_overlayView setSelectable:NO];
        [_overlayView setScrollEnabled:NO];
        
        // HACK: If not using stats overlay, center the text
        if (_statsUpdateTimer == nil) {
            [_overlayView setTextAlignment:NSTextAlignmentCenter];
        }
        
        // A translucent dark plate keeps the text fully opaque and readable over the video.
        // Digits have a fixed width so changing numbers don't make the text jitter.
        [_overlayView setTextColor:[UIColor colorWithWhite:1 alpha:0.9]];
        [_overlayView setBackgroundColor:[UIColor colorWithWhite:0 alpha:0.55]];
        _overlayView.layer.cornerRadius = 10;
        _overlayView.textContainerInset = UIEdgeInsetsMake(6, 10, 6, 10);
#if TARGET_OS_TV
        [_overlayView setFont:[UIFont monospacedDigitSystemFontOfSize:24 weight:UIFontWeightMedium]];
#else
        [_overlayView setFont:[UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium]];
#endif
        [self.view addSubview:_overlayView];
    }
    
    if (text != nil) {
        // We set our bounds to the maximum width in order to work around a bug where
        // sizeToFit interacts badly with the UITextView's line breaks, causing the
        // width to get smaller and smaller each time as more line breaks are inserted.
        [_overlayView setBounds:CGRectMake(self.view.frame.origin.x,
                                           _overlayView.frame.origin.y,
                                           self.view.frame.size.width,
                                           _overlayView.frame.size.height)];
        [_overlayView setText:text];
        [_overlayView sizeToFit];
        // Keep clear of the notch and status area
        [_overlayView setCenter:CGPointMake(self.view.frame.size.width / 2, self.view.safeAreaInsets.top + 8 + _overlayView.frame.size.height / 2)];
        [_overlayView setHidden:NO];
    }
    else {
        [_overlayView setHidden:YES];
    }
}

- (void) returnToMainFrame {
    // Reset display mode back to default
    [self updatePreferredDisplayMode:NO];
    
    [_statsUpdateTimer invalidate];
    _statsUpdateTimer = nil;

    // Rotate back to landscape while our view is still in the window
#if !TARGET_OS_TV
    streamActive = NO;
    [self refreshSupportedOrientations];
#endif

    [self.navigationController popToRootViewControllerAnimated:YES];
}

// This will fire if the user opens control center or gets a low battery message
- (void)applicationWillResignActive:(NSNotification *)notification {
    if (_inactivityTimer != nil) {
        [_inactivityTimer invalidate];
    }
    
#if !TARGET_OS_TV
    // Terminate the stream if the app is inactive for 60 seconds
    Log(LOG_I, @"Starting inactivity termination timer");
    _inactivityTimer = [NSTimer scheduledTimerWithTimeInterval:60
                                                      target:self
                                                    selector:@selector(inactiveTimerExpired:)
                                                    userInfo:nil
                                                     repeats:NO];
#endif
}

- (void)inactiveTimerExpired:(NSTimer*)timer {
    Log(LOG_I, @"Terminating stream after inactivity");

    [self returnToMainFrame];
    
    _inactivityTimer = nil;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    // Stop the background timer, since we're foregrounded again
    if (_inactivityTimer != nil) {
        Log(LOG_I, @"Stopping inactivity timer after becoming active again");
        [_inactivityTimer invalidate];
        _inactivityTimer = nil;
    }
}

// This fires when the home button is pressed
- (void)applicationDidEnterBackground:(UIApplication *)application {
    Log(LOG_I, @"Terminating stream immediately for backgrounding");

    if (_inactivityTimer != nil) {
        [_inactivityTimer invalidate];
        _inactivityTimer = nil;
    }
    
    [self returnToMainFrame];
}

#if !TARGET_OS_TV
- (void)edgeSwiped:(UIScreenEdgePanGestureRecognizer *)gesture {
    // The recognizer keeps firing while the finger moves, only react once
    if (gesture.state != UIGestureRecognizerStateBegan || self.presentedViewController != nil) {
        return;
    }

    Log(LOG_I, @"User swiped to open the stream menu");
    [self showStreamMenu];
}

- (void)presentMenu:(UIAlertController *)menu {
    // Action sheets need an anchor on iPad
    menu.popoverPresentationController.sourceView = self.view;
    menu.popoverPresentationController.sourceRect = CGRectMake(0, self.view.bounds.size.height / 2, 1, 1);
    [self presentViewController:menu animated:YES completion:nil];
}

- (void)showStreamMenu {
    // Title the menu with the game being streamed, so it is clear what Disconnect leaves
    UIAlertController* menu = [UIAlertController alertControllerWithTitle:self.streamConfig.appName message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    [menu addAction:[UIAlertAction actionWithTitle:@"Clavier" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
        [self->_streamView toggleKeyboard];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Coller le presse-papiers" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
        NSString* text = [UIPasteboard generalPasteboard].string;
        if (text.length > 0) {
            const char* utf8String = [text UTF8String];
            LiSendUtf8TextEvent(utf8String, (unsigned int)strlen(utf8String));
        }
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Raccourcis clavier…" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
        [self showShortcutsMenu];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Changer d'écran…" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
        [self showDisplayMenu];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Se déconnecter" style:UIAlertActionStyleDestructive handler:^(UIAlertAction* action) {
        [self returnToMainFrame];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"Annuler" style:UIAlertActionStyleCancel handler:nil]];

    [self presentMenu:menu];
}

- (void)showDisplayMenu {
    // Sunshine switches the streamed monitor on Ctrl+Alt+Shift+F1..F12
    UIAlertController* menu = [UIAlertController alertControllerWithTitle:@"Changer d'écran" message:@"Nécessite un hôte Sunshine" preferredStyle:UIAlertControllerStyleActionSheet];
    for (int i = 0; i < 4; i++) {
        [menu addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Écran %d", i + 1] style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
            sendKeyCombo(@[@0xA2, @0xA4, @0xA0, @(0x70 + i)]);
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"Annuler" style:UIAlertActionStyleCancel handler:nil]];

    [self presentMenu:menu];
}

- (void)showShortcutsMenu {
    UIAlertController* menu = [UIAlertController alertControllerWithTitle:@"Raccourcis clavier" message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray<NSArray*>* builtInShortcuts = @[
        @[@"Alt+Tab", @[@0xA4, @0x09]],
        @[@"Alt+F4", @[@0xA4, @0x73]],
        @[@"Menu Démarrer (Win)", @[@0x5B]],
        @[@"Afficher le bureau (Win+D)", @[@0x5B, @0x44]],
        @[@"Gestionnaire des tâches (Ctrl+Shift+Esc)", @[@0xA2, @0xA0, @0x1B]],
        @[@"Capture d'écran (Win+Shift+S)", @[@0x5B, @0xA0, @0x53]],
    ];
    for (NSArray* shortcut in builtInShortcuts) {
        [menu addAction:[UIAlertAction actionWithTitle:shortcut[0] style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
            sendKeyCombo(shortcut[1]);
        }]];
    }

    for (NSString* shortcut in PenumbraCustomShortcuts()) {
        [menu addAction:[UIAlertAction actionWithTitle:shortcut style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
            NSArray<NSNumber*>* keys = parseKeyCombo(shortcut);
            if (keys != nil) {
                sendKeyCombo(keys);
            }
        }]];
    }

    [menu addAction:[UIAlertAction actionWithTitle:@"Ajouter un raccourci…" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
        [self promptAddShortcut];
    }]];
    if (PenumbraCustomShortcuts().count > 0) {
        [menu addAction:[UIAlertAction actionWithTitle:@"Supprimer un raccourci…" style:UIAlertActionStyleDestructive handler:^(UIAlertAction* action) {
            [self showRemoveShortcutMenu];
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"Annuler" style:UIAlertActionStyleCancel handler:nil]];

    [self presentMenu:menu];
}

- (void)promptAddShortcut {
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Ajouter un raccourci"
                                                                   message:@"Touches séparées par +, par exemple ctrl+shift+esc, win+e ou alt+f4"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField* textField) {
        textField.placeholder = @"ctrl+alt+t";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    __weak UIAlertController* weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Ajouter" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action) {
        NSString* shortcut = [weakAlert.textFields[0].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (parseKeyCombo(shortcut) == nil) {
            UIAlertController* error = [UIAlertController alertControllerWithTitle:@"Touche inconnue"
                                                                           message:@"Utilise des lettres, des chiffres, f1 à f24 et les noms de touches ctrl, alt, shift, win, esc, tab, enter, space, del, up, down, left, right, home, end."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [error addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:error animated:YES completion:nil];
            return;
        }
        PenumbraSetCustomShortcuts([PenumbraCustomShortcuts() arrayByAddingObject:shortcut]);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Annuler" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showRemoveShortcutMenu {
    UIAlertController* menu = [UIAlertController alertControllerWithTitle:@"Supprimer un raccourci" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSString* shortcut in PenumbraCustomShortcuts()) {
        [menu addAction:[UIAlertAction actionWithTitle:shortcut style:UIAlertActionStyleDestructive handler:^(UIAlertAction* action) {
            NSMutableArray* shortcuts = [PenumbraCustomShortcuts() mutableCopy];
            [shortcuts removeObject:shortcut];
            PenumbraSetCustomShortcuts(shortcuts);
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"Annuler" style:UIAlertActionStyleCancel handler:nil]];

    [self presentMenu:menu];
}
#endif

- (void) connectionStarted {
    Log(LOG_I, @"Connection started");
    dispatch_async(dispatch_get_main_queue(), ^{
        // Leave the spinner spinning until it's obscured by
        // the first frame of video.
        self->_stageLabel.hidden = YES;
        self->_tipLabel.hidden = YES;
        
        [self->_streamView showOnScreenControls];
        
        [self->_controllerSupport connectionEstablished];
        
        if (self->_settings.statsOverlay) {
            self->_statsUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0f
                                                                       target:self
                                                                     selector:@selector(updateStatsOverlay)
                                                                     userInfo:nil
                                                                      repeats:YES];
        }
    });
}

- (void)connectionTerminated:(int)errorCode {
    Log(LOG_I, @"Connection terminated: %d", errorCode);
    
    unsigned int portFlags = LiGetPortFlagsFromTerminationErrorCode(errorCode);
    unsigned int portTestResults = LiTestClientConnectivity(CONN_TEST_SERVER, 443, portFlags);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        NSString* title;
        NSString* message;
        
        if (portTestResults != ML_TEST_RESULT_INCONCLUSIVE && portTestResults != 0) {
            title = @"Connection Error";
            message = @"Your device's network connection is blocking Penumbra. Streaming may not work while connected to this network.";
        }
        else {
            switch (errorCode) {
                case ML_ERROR_GRACEFUL_TERMINATION:
                    [self returnToMainFrame];
                    return;
                    
                case ML_ERROR_NO_VIDEO_TRAFFIC:
                    title = @"Connection Error";
                    message = @"No video received from host.";
                    if (portFlags != 0) {
                        char failingPorts[256];
                        LiStringifyPortFlags(portFlags, "\n", failingPorts, sizeof(failingPorts));
                        message = [message stringByAppendingString:[NSString stringWithFormat:@"\n\nCheck your firewall and port forwarding rules for port(s):\n%s", failingPorts]];
                    }
                    break;
                    
                case ML_ERROR_NO_VIDEO_FRAME:
                    title = @"Connection Error";
                    message = @"Your network connection isn't performing well. Reduce your video bitrate setting or try a faster connection.";
                    break;
                    
                case ML_ERROR_UNEXPECTED_EARLY_TERMINATION:
                case ML_ERROR_PROTECTED_CONTENT:
                    title = @"Connection Error";
                    message = @"Something went wrong on your host PC when starting the stream.\n\nMake sure you don't have any DRM-protected content open on your host PC. You can also try restarting your host PC.\n\nIf the issue persists, try reinstalling your GPU drivers and GeForce Experience.";
                    break;
                    
                case ML_ERROR_FRAME_CONVERSION:
                    title = @"Connection Error";
                    message = @"The host PC reported a fatal video encoding error.\n\nTry disabling HDR mode, changing the streaming resolution, or changing your host PC's display resolution.";
                    break;
                    
                default:
                {
                    NSString* errorString;
                    if (abs(errorCode) > 1000) {
                        // We'll assume large errors are hex values
                        errorString = [NSString stringWithFormat:@"%08X", (uint32_t)errorCode];
                    }
                    else {
                        // Smaller values will just be printed as decimal (probably errno.h values)
                        errorString = [NSString stringWithFormat:@"%d", errorCode];
                    }
                    
                    title = @"Connection Terminated";
                    message = [NSString stringWithFormat: @"The connection was terminated\n\nError code: %@", errorString];
                    break;
                }
            }
        }
        
        UIAlertController* conTermAlert = [UIAlertController alertControllerWithTitle:title
                                                                              message:message
                                                                       preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:conTermAlert];
        [conTermAlert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentViewController:conTermAlert animated:YES completion:nil];
    });

    [_streamMan stopStream];
}

- (void) stageStarting:(const char*)stageName {
    Log(LOG_I, @"Starting %s", stageName);
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString* lowerCase = [NSString stringWithFormat:@"%s in progress...", stageName];
        NSString* titleCase = [[[lowerCase substringToIndex:1] uppercaseString] stringByAppendingString:[lowerCase substringFromIndex:1]];
        [self->_stageLabel setText:titleCase];
        [self->_stageLabel sizeToFit];
        self->_stageLabel.center = CGPointMake(self.view.frame.size.width / 2, self->_stageLabel.center.y);
    });
}

- (void) stageComplete:(const char*)stageName {
}

- (void) stageFailed:(const char*)stageName withError:(int)errorCode portTestFlags:(int)portTestFlags {
    Log(LOG_I, @"Stage %s failed: %d", stageName, errorCode);
    
    unsigned int portTestResults = LiTestClientConnectivity(CONN_TEST_SERVER, 443, portTestFlags);

    dispatch_async(dispatch_get_main_queue(), ^{
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        NSString* message = [NSString stringWithFormat:@"%s failed with error %d", stageName, errorCode];
        if (portTestFlags != 0) {
            char failingPorts[256];
            LiStringifyPortFlags(portTestFlags, "\n", failingPorts, sizeof(failingPorts));
            message = [message stringByAppendingString:[NSString stringWithFormat:@"\n\nCheck your firewall and port forwarding rules for port(s):\n%s", failingPorts]];
        }
        if (portTestResults != ML_TEST_RESULT_INCONCLUSIVE && portTestResults != 0) {
            message = [message stringByAppendingString:@"\n\nYour device's network connection is blocking Penumbra. Streaming may not work while connected to this network."];
        }
        
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Connection Failed"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:alert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    });
    
    [_streamMan stopStream];
}

- (void) launchFailed:(NSString*)message {
    Log(LOG_I, @"Launch failed: %@", message);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // Allow the display to go to sleep now
        [UIApplication sharedApplication].idleTimerDisabled = NO;
        
        UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Connection Error"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [Utils addHelpOptionToDialog:alert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* action){
            [self returnToMainFrame];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)rumble:(unsigned short)controllerNumber lowFreqMotor:(unsigned short)lowFreqMotor highFreqMotor:(unsigned short)highFreqMotor {
    Log(LOG_I, @"Rumble on gamepad %d: %04x %04x", controllerNumber, lowFreqMotor, highFreqMotor);
    
    [_controllerSupport rumble:controllerNumber lowFreqMotor:lowFreqMotor highFreqMotor:highFreqMotor];
}

- (void) rumbleTriggers:(uint16_t)controllerNumber leftTrigger:(uint16_t)leftTrigger rightTrigger:(uint16_t)rightTrigger {
    Log(LOG_I, @"Trigger rumble on gamepad %d: %04x %04x", controllerNumber, leftTrigger, rightTrigger);
    
    [_controllerSupport rumbleTriggers:controllerNumber leftTrigger:leftTrigger rightTrigger:rightTrigger];
}

- (void) setMotionEventState:(uint16_t)controllerNumber motionType:(uint8_t)motionType reportRateHz:(uint16_t)reportRateHz {
    Log(LOG_I, @"Set motion state on gamepad %d: %02x %u Hz", controllerNumber, motionType, reportRateHz);
    
    [_controllerSupport setMotionEventState:controllerNumber motionType:motionType reportRateHz:reportRateHz];
}

- (void) setControllerLed:(uint16_t)controllerNumber r:(uint8_t)r g:(uint8_t)g b:(uint8_t)b {
    Log(LOG_I, @"Set controller LED on gamepad %d: l%02x%02x%02x", controllerNumber, r, g, b);
    
    [_controllerSupport setControllerLed:controllerNumber r:r g:g b:b];
}

- (void)connectionStatusUpdate:(int)status {
    Log(LOG_W, @"Connection status update: %d", status);

    // The stats overlay takes precedence over these warnings
    if (_statsUpdateTimer != nil) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (status) {
            case CONN_STATUS_OKAY:
                [self updateOverlayText:nil];
                break;
                
            case CONN_STATUS_POOR:
                if (self->_streamConfig.bitRate > 5000) {
                    [self updateOverlayText:@"Slow connection to PC\nReduce your bitrate"];
                }
                else {
                    [self updateOverlayText:@"Poor connection to PC"];
                }
                break;
        }
    });
}

- (void) updatePreferredDisplayMode:(BOOL)streamActive {
#if TARGET_OS_TV
    if (@available(tvOS 11.2, *)) {
        UIWindow* window = [[[UIApplication sharedApplication] delegate] window];
        AVDisplayManager* displayManager = [window avDisplayManager];
        
        // This logic comes from Kodi and MrMC
        if (streamActive) {
            int dynamicRange;
            
            if (LiGetCurrentHostDisplayHdrMode()) {
                dynamicRange = 2; // HDR10
            }
            else {
                dynamicRange = 0; // SDR
            }
            
            AVDisplayCriteria* displayCriteria = [[AVDisplayCriteria alloc] initWithRefreshRate:[_settings.framerate floatValue]
                                                                              videoDynamicRange:dynamicRange];
            displayManager.preferredDisplayCriteria = displayCriteria;
        }
        else {
            // Switch back to the default display mode
            displayManager.preferredDisplayCriteria = nil;
        }
    }
#endif
}

- (void) setHdrMode:(bool)enabled {
    Log(LOG_I, @"HDR is now: %s", enabled ? "active" : "inactive");
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updatePreferredDisplayMode:YES];
    });
}

- (void) videoContentShown {
    [_spinner stopAnimating];
    [self.view setBackgroundColor:[UIColor blackColor]];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)gamepadPresenceChanged {
#if !TARGET_OS_TV
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

- (void)mousePresenceChanged {
#if !TARGET_OS_TV
    if (@available(iOS 14.0, *)) {
        [self setNeedsUpdateOfPrefersPointerLocked];
    }
#endif
}

- (void) streamExitRequested {
    Log(LOG_I, @"Gamepad combo requested stream exit");
    
    [self returnToMainFrame];
}

- (void)userInteractionBegan {
    // Disable hiding home bar when user is interacting.
    // iOS will force it to be shown anyway, but it will
    // also discard our edges deferring system gestures unless
    // we willingly give up home bar hiding preference.
    _userIsInteracting = YES;
#if !TARGET_OS_TV
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

- (void)userInteractionEnded {
    // Enable home bar hiding again if conditions allow
    _userIsInteracting = NO;
#if !TARGET_OS_TV
    if (@available(iOS 11.0, *)) {
        [self setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
#endif
}

#if !TARGET_OS_TV
// Require a confirmation when streaming to activate a system gesture
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures {
    return UIRectEdgeAll;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    if ([_controllerSupport getConnectedGamepadCount] > 0 &&
        [_streamView getCurrentOscState] == OnScreenControlsLevelOff &&
        _userIsInteracting == NO) {
        // Autohide the home bar when a gamepad is connected
        // and the on-screen controls are disabled. We can't
        // do this all the time because any touch on the display
        // will cause the home indicator to reappear, and our
        // preferredScreenEdgesDeferringSystemGestures will also
        // be suppressed (leading to possible errant exits of the
        // stream).
        return YES;
    }
    
    return NO;
}

- (BOOL)shouldAutorotate {
    return YES;
}

- (BOOL)prefersPointerLocked {
    // Pointer lock breaks the UIKit mouse APIs, which is a problem because
    // GCMouse is horribly broken on iOS 14.0 for certain mice. Only lock
    // the cursor if there is a GCMouse present.
    return [GCMouse mice].count > 0;
}
#endif

@end
