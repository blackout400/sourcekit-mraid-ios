//
//  SKMRAIDView.m
//  MRAID
//
//  Created by Jay Tucker on 9/13/13.
//  Copyright (c) 2013 Nexage, Inc. All rights reserved.
//

#import <WebKit/WebKit.h>

#import "SKMRAIDView.h"
#import "SKMRAIDOrientationProperties.h"
#import "SKMRAIDResizeProperties.h"
#import "SKMRAIDParser.h"
#import "SKMRAIDModalViewController.h"
#import "SKMRAIDServiceDelegate.h"
#import "SKMRAIDUtil.h"
#import "MRAIDSettings.h"

#import "mraidjs.h"
#import "CloseButton.h"

#define kCloseEventRegionSize 50
#define SYSTEM_VERSION_LESS_THAN(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)

typedef enum {
    MRAIDStateLoading,
    MRAIDStateDefault,
    MRAIDStateExpanded,
    MRAIDStateResized,
    MRAIDStateHidden
} MRAIDState;

@interface SKMRAIDView () <UIWebViewDelegate, SKMRAIDModalViewControllerDelegate, UIGestureRecognizerDelegate>

@property (nonatomic, assign) MRAIDState state;
    // This corresponds to the MRAID placement type.
@property (nonatomic, assign) BOOL isInterstitial;
    
    // The only property of the MRAID expandProperties we need to keep track of
    // on the native side is the useCustomClose property.
    // The width, height, and isModal properties are not used in MRAID v2.0.
@property (nonatomic, assign) BOOL useCustomClose;
    
@property (nonatomic, strong) SKMRAIDOrientationProperties *orientationProperties;
@property (nonatomic, strong) SKMRAIDResizeProperties *resizeProperties;
    
@property (nonatomic, strong) SKMRAIDParser *mraidParser;
@property (nonatomic, strong) SKMRAIDModalViewController *modalVC;
    
@property (nonatomic, strong) NSString *mraidjs;
    
@property (nonatomic, strong) NSURL *baseURL;
    
@property (nonatomic, strong) NSArray *mraidFeatures;
@property (nonatomic, strong) NSArray *supportedFeatures;
    
@property (nonatomic, strong) UIWebView *webView;
@property (nonatomic, strong) UIWebView *webViewPart2;
@property (nonatomic, strong) UIWebView *currentWebView;
    
@property (nonatomic, strong) UIButton *closeEventRegion;
    
@property (nonatomic, strong) UIView *resizeView;
@property (nonatomic, strong) UIButton *resizeCloseRegion;
@property (nonatomic, assign) CGSize previousMaxSize;
@property (nonatomic, assign) CGSize previousScreenSize;
    
@property (nonatomic, strong) UITapGestureRecognizer *tapGestureRecognizer;
@property (nonatomic, assign) BOOL bonafideTapObserved;

// "hidden" method for interstitial support
- (void)showAsInterstitial;

- (void)deviceOrientationDidChange:(NSNotification *)notification;

- (void)addCloseEventRegion;
- (void)showResizeCloseRegion;
- (void)removeResizeCloseRegion;
- (void)setResizeViewPosition;

// These methods provide the means for native code to talk to JavaScript code.
- (void)injectJavaScript:(NSString *)js;
// convenience methods to fire MRAID events
- (void)fireErrorEventWithAction:(NSString *)action message:(NSString *)message;
- (void)fireReadyEvent;
- (void)fireSizeChangeEvent;
- (void)fireStateChangeEvent;
- (void)fireViewableChangeEvent;
// setters
- (void)setDefaultPosition;
-(void)setMaxSize;
-(void)setScreenSize;

// internal helper methods
- (void)initWebView:(UIWebView *)wv;
- (void)parseCommandUrl:(NSString *)commandUrlString;

@end

@implementation SKMRAIDView

@synthesize isViewable = _isViewable;

- (id)init {
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:@"-init is not a valid initializer for the class MRAIDView"
                                 userInfo:nil];
    return nil;
}

- (id)initWithFrame:(CGRect)frame
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:@"-initWithFrame is not a valid initializer for the class MRAIDView"
                                 userInfo:nil];
    return nil;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:@"-initWithCoder is not a valid initializer for the class MRAIDView"
                                 userInfo:nil];
    return nil;
}

- (id)initWithFrame:(CGRect)frame
       withHtmlData:(NSString*)htmlData
        withBaseURL:(NSURL*)bsURL
  supportedFeatures:(NSArray *)features
           delegate:(id<SKMRAIDViewDelegate>)delegate
   serviceDelegate:(id<SKMRAIDServiceDelegate>)serviceDelegate
 rootViewController:(UIViewController *)rootViewController
{
    return [self initWithFrame:frame
                  withHtmlData:htmlData
                   withBaseURL:bsURL
                asInterstitial:NO
             supportedFeatures:features
                      delegate:delegate
              serviceDelegate:serviceDelegate
            rootViewController:rootViewController];
}

// designated initializer
- (id)initWithFrame:(CGRect)frame
       withHtmlData:(NSString*)htmlData
        withBaseURL:(NSURL*)bsURL
     asInterstitial:(BOOL)isInter
  supportedFeatures:(NSArray *)currentFeatures
           delegate:(id<SKMRAIDViewDelegate>)delegate
   serviceDelegate:(id<SKMRAIDServiceDelegate>)serviceDelegate
 rootViewController:(UIViewController *)rootViewController
{
    self = [super initWithFrame:frame];
    if (self) {
        [self setUpTapGestureRecognizer];
        self.isInterstitial = isInter;
        _delegate = delegate;
        _serviceDelegate = serviceDelegate;
        _rootViewController = rootViewController;
        
        self.state = MRAIDStateLoading;
        self.isViewable = NO;
        self.useCustomClose = NO;
        
        self.orientationProperties = [[SKMRAIDOrientationProperties alloc] init];
        self.resizeProperties = [[SKMRAIDResizeProperties alloc] init];
        
        self.mraidParser = [[SKMRAIDParser alloc] init];
        
        self.mraidFeatures = @[
                          MRAIDSupportsSMS,
                          MRAIDSupportsTel,
                          MRAIDSupportsCalendar,
                          MRAIDSupportsStorePicture,
                          MRAIDSupportsInlineVideo,
                          ];
        
        if([self isValidFeatureSet:currentFeatures] && serviceDelegate){
            self.supportedFeatures=currentFeatures;
        }
        
        self.webView = [[UIWebView alloc] initWithFrame:CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height)];
        [self initWebView:self.webView];
        self.currentWebView = self.webView;
        [self addSubview:self.webView];
        
        self.previousMaxSize = CGSizeZero;
        self.previousScreenSize = CGSizeZero;
        
        [self addObserver:self forKeyPath:@"self.frame" options:NSKeyValueObservingOptionOld context:NULL];
 
        // Get mraid.js as binary data
        NSData* mraidJSData = [NSData dataWithBytesNoCopy:__MRAID_mraid_js
                                                   length:__MRAID_mraid_js_len
                                             freeWhenDone:NO];
        self.mraidjs = [[NSString alloc] initWithData:mraidJSData encoding:NSUTF8StringEncoding];
        mraidJSData = nil;
        
        self.baseURL = bsURL;
        self.state = MRAIDStateLoading;
        
        if (self.mraidjs) {
            [self injectJavaScript:self.mraidjs];
        }
        
        htmlData = [SKMRAIDUtil processRawHtml:htmlData];
        if (htmlData) {
            [self.currentWebView loadHTMLString:htmlData baseURL:self.baseURL];
        } else {
            if ([self.delegate respondsToSelector:@selector(mraidViewAdFailed:)]) {
                [self.delegate mraidViewAdFailed:self];
            }
        }
        if (isInter) {
            self.bonafideTapObserved = YES;  // no autoRedirect suppression for Interstitials
        }
    }
    return self;
}

- (void)cancel
{
    [self.currentWebView stopLoading];
    self.currentWebView = nil;
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
}

- (void)dealloc
{
    
    [self removeObserver:self forKeyPath:@"self.frame"];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
    
    
    self.webView = nil;
    self.webViewPart2 = nil;
    self.currentWebView = nil;
    
    self.mraidParser = nil;
    self.modalVC = nil;
    
    self.orientationProperties = nil;
    self.resizeProperties = nil;
    
    self.mraidFeatures = nil;
    self.supportedFeatures = nil;
    
    self.closeEventRegion = nil;
    self.resizeView = nil;
    self.resizeCloseRegion = nil;
}

- (BOOL)isValidFeatureSet:(NSArray *)features
{
    NSArray *kFeatures = @[
                           MRAIDSupportsSMS,
                           MRAIDSupportsTel,
                           MRAIDSupportsCalendar,
                           MRAIDSupportsStorePicture,
                           MRAIDSupportsInlineVideo,
                           ];
    
    // Validate the features set by the user
    for (id feature in features) {
        if (![kFeatures containsObject:feature]) {
            return NO;
        }
    }
    return YES;
}

- (void)setIsViewable:(BOOL)newIsViewable
{
    if(newIsViewable!= self.isViewable){
        self.isViewable=newIsViewable;
        [self fireViewableChangeEvent];
    }
}

- (BOOL)isViewable
{
    return _isViewable;
}

- (void)setRootViewController:(UIViewController *)newRootViewController
{
    if(newRootViewController!=_rootViewController) {
        _rootViewController=newRootViewController;
    }
}

- (void)deviceOrientationDidChange:(NSNotification *)notification
{
    @synchronized (self) {
        [self setScreenSize];
        [self setMaxSize];
        [self setDefaultPosition];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (!([keyPath isEqualToString:@"self.frame"])) {
        return;
    }
    
    CGRect oldFrame = CGRectNull;
    CGRect newFrame = CGRectNull;
    if (change[@"old"] != [NSNull null]) {
        oldFrame = [change[@"old"] CGRectValue];
    }
    if ([object valueForKeyPath:keyPath] != [NSNull null]) {
        newFrame = [[object valueForKeyPath:keyPath] CGRectValue];
    }
    
    if (self.state == MRAIDStateResized) {
        [self setResizeViewPosition];
    }
    [self setDefaultPosition];
    [self setMaxSize];
    [self fireSizeChangeEvent];
}

-(void)setBackgroundColor:(UIColor *)backgroundColor
{
    [super setBackgroundColor:backgroundColor];
    self.currentWebView.backgroundColor = backgroundColor;
}

#pragma mark - interstitial support

- (void)showAsInterstitial
{
    [self expand:nil];
}

#pragma mark - JavaScript --> native support

// These methods are (indirectly) called by JavaScript code.
// They provide the means for JavaScript code to talk to native code

- (void)close
{
    if (self.state == MRAIDStateLoading ||
        (self.state == MRAIDStateDefault && !self.isInterstitial) ||
        self.state == MRAIDStateHidden) {
        // do nothing
        return;
    }
    
    if (self.state == MRAIDStateResized) {
        [self closeFromResize];
        return;
    }
    
    if (self.modalVC) {
        [self.closeEventRegion removeFromSuperview];
        self.closeEventRegion = nil;
        [self.currentWebView removeFromSuperview];
        [self.modalVC dismissViewControllerAnimated:NO completion:nil];
    }
    
    self.modalVC = nil;
    
    if (self.webViewPart2) {
        // Clean up webViewPart2 if returning from 2-part expansion.
        self.webViewPart2.delegate = nil;
        self.currentWebView =self. webView;
        self.webViewPart2 = nil;
    } else {
        // Reset frame of webView if returning from 1-part expansion.
        self.webView.frame = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);
    }
    
    [self addSubview:self.webView];
    
    if (!self.isInterstitial) {
        [self fireSizeChangeEvent];
    } else {
        self.isViewable = NO;
        [self fireViewableChangeEvent];
    }
    
    if (self.state == MRAIDStateDefault && self.isInterstitial) {
        self.state = MRAIDStateHidden;
    } else if (self.state == MRAIDStateExpanded || self.state == MRAIDStateResized) {
        self.state = MRAIDStateDefault;
    }
    [self fireStateChangeEvent];
    
    if ([self.delegate respondsToSelector:@selector(mraidViewDidClose:)]) {
        [self.delegate mraidViewDidClose:self];
    }
}

// This is a helper method which is not part of the official MRAID API.
- (void)closeFromResize
{
    [self removeResizeCloseRegion];
    self.state = MRAIDStateDefault;
    [self fireStateChangeEvent];
    [self.webView removeFromSuperview];
    self.webView.frame = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);
    [self addSubview:self.webView];
    [self.resizeView removeFromSuperview];
    self.resizeView = nil;
    [self fireSizeChangeEvent];
    if ([self.delegate respondsToSelector:@selector(mraidViewDidClose:)]) {
        [self.delegate mraidViewDidClose:self];
    }
}

- (void)createCalendarEvent:(NSString *)eventJSON
{
    if(!self.bonafideTapObserved && SK_SUPPRESS_BANNER_AUTO_REDIRECT){
        return;  // ignore programmatic touches (taps)
    }

    eventJSON=[eventJSON stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    
    if ([self.supportedFeatures containsObject:MRAIDSupportsCalendar]) {
        if ([self.serviceDelegate respondsToSelector:@selector(mraidServiceCreateCalendarEventWithEventJSON:)]) {
            [self.serviceDelegate mraidServiceCreateCalendarEventWithEventJSON:eventJSON];
        }
    }
}

// Note: This method is also used to present an interstitial ad.
- (void)expand:(NSString *)urlString
{
    if(!self.bonafideTapObserved && SK_SUPPRESS_BANNER_AUTO_REDIRECT){
        return;  // ignore programmatic touches (taps)
    }
    
    // The only time it is valid to call expand is when the ad is currently in either default or resized state.
    if (self.state != MRAIDStateDefault && self.state != MRAIDStateResized) {
        // do nothing
        return;
    }
    
    self.modalVC = [[SKMRAIDModalViewController alloc] initWithOrientationProperties:self.orientationProperties];
    CGRect frame = [[UIScreen mainScreen] bounds];
    self.modalVC.view.frame = frame;
    self.modalVC.delegate = self;
    
    if (!urlString) {
        // 1-part expansion
        self.webView.frame = frame;
        [self.webView removeFromSuperview];
    } else {
        // 2-part expansion
        self.webViewPart2 = [[UIWebView alloc] initWithFrame:frame];
        [self initWebView:self.webViewPart2];
        self.currentWebView = self.webViewPart2;
        self.bonafideTapObserved = YES; // by definition for 2 part expand a valid tap has occurred
        
        if (self.mraidjs) {
            [self injectJavaScript:self.mraidjs];
        }
        
        // Check to see whether we've been given an absolute or relative URL.
        // If it's relative, prepend the base URL.
        urlString = [urlString stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        if (![[NSURL URLWithString:urlString] scheme]) {
            // relative URL
            urlString = [[[self.baseURL absoluteString] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding] stringByAppendingString:urlString];
        }
        
        // Need to escape characters which are URL specific
        urlString = [urlString stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        
        NSError *error;
        NSString *content = [NSString stringWithContentsOfURL:[NSURL URLWithString:urlString] encoding:NSUTF8StringEncoding error:&error];
        if (!error) {
            [self.webViewPart2 loadHTMLString:content baseURL:self.baseURL];
        } else {
            // Error! Clean up and return.
            self.currentWebView = self.webView;
            self.webViewPart2.delegate = nil;
            self.webViewPart2 = nil;
            self.modalVC = nil;
            return;
        }
    }
    
    if ([self.delegate respondsToSelector:@selector(mraidViewWillExpand:)]) {
        [self.delegate mraidViewWillExpand:self];
    }
    
    [self.modalVC.view addSubview:self.currentWebView];
    
    // always include the close event region
    [self addCloseEventRegion];
    
    if ([self.rootViewController respondsToSelector:@selector(presentViewController:animated:completion:)]) {
        // used if running >= iOS 6
        if (SYSTEM_VERSION_LESS_THAN(@"8.0")) {  // respect clear backgroundColor
            self.rootViewController.navigationController.modalPresentationStyle = UIModalPresentationCurrentContext;
        } else {
            self.modalVC.modalPresentationStyle = UIModalPresentationFullScreen;
        }
        [self.rootViewController presentViewController:self.modalVC animated:NO completion:nil];
    } else {
        // Turn off the warning about using a deprecated method.

        [self.rootViewController presentViewController:self.modalVC animated:NO completion:^{
        }];
    }
    
    if (!self.isInterstitial) {
        self.state = MRAIDStateExpanded;
        [self fireStateChangeEvent];
    }
    [self fireSizeChangeEvent];
    self.isViewable = YES;
}

- (void)open:(NSString *)urlString
{
    if(!self.bonafideTapObserved && SK_SUPPRESS_BANNER_AUTO_REDIRECT){
       return;  // ignore programmatic touches (taps)
    }
    
    urlString = [urlString stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    
    // Notify the callers
    if ([self.serviceDelegate respondsToSelector:@selector(mraidServiceOpenBrowserWithUrlString:)]) {
        [self.serviceDelegate mraidServiceOpenBrowserWithUrlString:urlString];
    }
}

- (void)playVideo:(NSString *)urlString
{
    if(!self.bonafideTapObserved && SK_SUPPRESS_BANNER_AUTO_REDIRECT){
        return;  // ignore programmatic touches (taps)
    }
    
    urlString = [urlString stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    if ([self.serviceDelegate respondsToSelector:@selector(mraidServicePlayVideoWithUrlString:)]) {
        [self.serviceDelegate mraidServicePlayVideoWithUrlString:urlString];
    }
}

- (void)resize
{
    if(!self.bonafideTapObserved && SK_SUPPRESS_BANNER_AUTO_REDIRECT){
        return;  // ignore programmatic touches (taps)
    }
    
    // If our delegate doesn't respond to the mraidViewShouldResizeToPosition:allowOffscreen: message,
    // then we can't do anything. We need help from the app here.
    if (![self.delegate respondsToSelector:@selector(mraidViewShouldResize:toPosition:allowOffscreen:)]) {
        return;
    }
    
    CGRect resizeFrame = CGRectMake(self.resizeProperties.offsetX, self.resizeProperties.offsetY, self.resizeProperties.width, self.resizeProperties.height);
    // The offset of the resize frame is relative to the origin of the default banner.
    CGPoint bannerOriginInRootView = [self.rootViewController.view convertPoint:CGPointZero fromView:self];
    resizeFrame.origin.x += bannerOriginInRootView.x;
    resizeFrame.origin.y += bannerOriginInRootView.y;
    
    if (![self.delegate mraidViewShouldResize:self toPosition:resizeFrame allowOffscreen:self.resizeProperties.allowOffscreen]) {
        return;
    }
    
    // resize here
    self.state = MRAIDStateResized;
    [self fireStateChangeEvent];
    
    if (!self.resizeView) {
        self.resizeView = [[UIView alloc] initWithFrame:resizeFrame];
        [self.webView removeFromSuperview];
        [self.resizeView addSubview:self.webView];
        [self.rootViewController.view addSubview:self.resizeView];
    }
    
    self.resizeView.frame = resizeFrame;
    self.webView.frame = self.resizeView.bounds;
    [self showResizeCloseRegion];
    [self fireSizeChangeEvent];
}

- (void)setOrientationProperties:(NSDictionary *)properties;
{
    BOOL allowOrientationChange = [[properties valueForKey:@"allowOrientationChange"] boolValue];
    NSString *forceOrientation = [properties valueForKey:@"forceOrientation"];
    self.orientationProperties.allowOrientationChange = allowOrientationChange;
    self.orientationProperties.forceOrientation = [SKMRAIDOrientationProperties MRAIDForceOrientationFromString:forceOrientation];
    [self.modalVC forceToOrientation:self.orientationProperties];
}

- (void)setResizeProperties:(NSDictionary *)properties;
{
    int width = [[properties valueForKey:@"width"] intValue];
    int height = [[properties valueForKey:@"height"] intValue];
    int offsetX = [[properties valueForKey:@"offsetX"] intValue];
    int offsetY = [[properties valueForKey:@"offsetY"] intValue];
    NSString *customClosePosition = [properties valueForKey:@"customClosePosition"];
    BOOL allowOffscreen = [[properties valueForKey:@"allowOffscreen"] boolValue];
    self.resizeProperties.width = width;
    self.resizeProperties.height = height;
    self.resizeProperties.offsetX = offsetX;
    self.resizeProperties.offsetY = offsetY;
    self.resizeProperties.customClosePosition = [SKMRAIDResizeProperties MRAIDCustomClosePositionFromString:customClosePosition];
    self.resizeProperties.allowOffscreen = allowOffscreen;
}

-(void)storePicture:(NSString *)urlString
{
    if(!self.bonafideTapObserved && SK_SUPPRESS_BANNER_AUTO_REDIRECT){
        return;  // ignore programmatic touches (taps)
    }
    
    urlString=[urlString stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    
    if ([self.supportedFeatures containsObject:MRAIDSupportsStorePicture]) {
        if ([self.serviceDelegate respondsToSelector:@selector(mraidServiceStorePictureWithUrlString:)]) {
            [self.serviceDelegate mraidServiceStorePictureWithUrlString:urlString];
        }
    }
}

- (void)useCustomClose:(NSString *)isCustomCloseString
{
    BOOL isCustomClose = [isCustomCloseString boolValue];
    self.useCustomClose = isCustomClose;
}

#pragma mark - JavaScript --> native support helpers

// These methods are helper methods for the ones above.

- (void)addCloseEventRegion
{
    self.closeEventRegion = [UIButton buttonWithType:UIButtonTypeCustom];
    self.closeEventRegion.backgroundColor = [UIColor clearColor];
    [self.closeEventRegion addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    
    if (!self.useCustomClose) {
        // get button image from header file
        NSData* buttonData = [NSData dataWithBytesNoCopy:__MRAID_CloseButton_png
                                                  length:__MRAID_CloseButton_png_len
                                            freeWhenDone:NO];
        UIImage *closeButtonImage = [UIImage imageWithData:buttonData];
        [self.closeEventRegion setBackgroundImage:closeButtonImage forState:UIControlStateNormal];
    }
    
    self.closeEventRegion.frame = CGRectMake(0, 0, kCloseEventRegionSize, kCloseEventRegionSize);
    CGRect frame = self.closeEventRegion.frame;
    
    // align on top right
    int x = CGRectGetWidth(self.modalVC.view.frame) - CGRectGetWidth(frame);
    frame.origin = CGPointMake(x, 0);
    self.closeEventRegion.frame = frame;
    // autoresizing so it stays at top right (flexible left and flexible bottom margin)
    self.closeEventRegion.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    
    [self.modalVC.view addSubview:self.closeEventRegion];
}

- (void)showResizeCloseRegion
{
    if (!self.resizeCloseRegion) {
        self.resizeCloseRegion = [UIButton buttonWithType:UIButtonTypeCustom];
        self.resizeCloseRegion.frame = CGRectMake(0, 0, kCloseEventRegionSize, kCloseEventRegionSize);
        self.resizeCloseRegion.backgroundColor = [UIColor clearColor];
        [self.resizeCloseRegion addTarget:self action:@selector(closeFromResize) forControlEvents:UIControlEventTouchUpInside];
        [self.resizeView addSubview:self.resizeCloseRegion];
    }
    
    // align appropriately
    int x;
    int y;
    UIViewAutoresizing autoresizingMask = UIViewAutoresizingNone;
    
    switch (self.resizeProperties.customClosePosition) {
        case MRAIDCustomClosePositionTopLeft:
        case MRAIDCustomClosePositionBottomLeft:
            x = 0;
            break;
        case MRAIDCustomClosePositionTopCenter:
        case MRAIDCustomClosePositionCenter:
        case MRAIDCustomClosePositionBottomCenter:
            x = (CGRectGetWidth(self.resizeView.frame) - CGRectGetWidth(self.resizeCloseRegion.frame)) / 2;
            autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
            break;
        case MRAIDCustomClosePositionTopRight:
        case MRAIDCustomClosePositionBottomRight:
            x = CGRectGetWidth(self.resizeView.frame) - CGRectGetWidth(self.resizeCloseRegion.frame);
            autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
            break;
    }
    
    switch (self.resizeProperties.customClosePosition) {
        case MRAIDCustomClosePositionTopLeft:
        case MRAIDCustomClosePositionTopCenter:
        case MRAIDCustomClosePositionTopRight:
            y = 0;
            break;
        case MRAIDCustomClosePositionCenter:
            y = (CGRectGetHeight(self.resizeView.frame) - CGRectGetHeight(self.resizeCloseRegion.frame)) / 2;
            autoresizingMask |= UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
            break;
        case MRAIDCustomClosePositionBottomLeft:
        case MRAIDCustomClosePositionBottomCenter:
        case MRAIDCustomClosePositionBottomRight:
            y = CGRectGetHeight(self.resizeView.frame) - CGRectGetHeight(self.resizeCloseRegion.frame);
            autoresizingMask |= UIViewAutoresizingFlexibleTopMargin;
            break;
    }
    
    CGRect resizeCloseRegionFrame = self.resizeCloseRegion.frame;
    resizeCloseRegionFrame.origin = CGPointMake(x, y);
    self.resizeCloseRegion.frame = resizeCloseRegionFrame;
    self.resizeCloseRegion.autoresizingMask = autoresizingMask;
}

- (void)removeResizeCloseRegion
{
    if (self.resizeCloseRegion) {
        [self.resizeCloseRegion removeFromSuperview];
        self.resizeCloseRegion = nil;
    }
}

- (void)setResizeViewPosition
{
    CGRect oldResizeFrame = self.resizeView.frame;
    CGRect newResizeFrame = CGRectMake(self.resizeProperties.offsetX, self.resizeProperties.offsetY, self.resizeProperties.width, self.resizeProperties.height);
    // The offset of the resize frame is relative to the origin of the default banner.
    CGPoint bannerOriginInRootView = [self.rootViewController.view convertPoint:CGPointZero fromView:self];
    newResizeFrame.origin.x += bannerOriginInRootView.x;
    newResizeFrame.origin.y += bannerOriginInRootView.y;
    if (!CGRectEqualToRect(oldResizeFrame, newResizeFrame)) {
        self.resizeView.frame = newResizeFrame;
    }
}

#pragma mark - native -->  JavaScript support

- (void)injectJavaScript:(NSString *)js
{
    [self.currentWebView stringByEvaluatingJavaScriptFromString:js];
}

// convenience methods
- (void)fireErrorEventWithAction:(NSString *)action message:(NSString *)message
{
    [self injectJavaScript:[NSString stringWithFormat:@"mraid.fireErrorEvent('%@','%@');", message, action]];
}

- (void)fireReadyEvent
{
    [self injectJavaScript:@"mraid.fireReadyEvent()"];
}

- (void)fireSizeChangeEvent
{
    @synchronized(self){
        int x;
        int y;
        int width;
        int height;
        if (self.state == MRAIDStateExpanded || self.isInterstitial) {
            x = (int)self.currentWebView.frame.origin.x;
            y = (int)self.currentWebView.frame.origin.y;
            width = (int)self.currentWebView.frame.size.width;
            height = (int)self.currentWebView.frame.size.height;
        } else if (self.state == MRAIDStateResized) {
            x = (int)self.resizeView.frame.origin.x;
            y = (int)self.resizeView.frame.origin.y;
            width = (int)self.resizeView.frame.size.width;
            height = (int)self.resizeView.frame.size.height;
        } else {
            // Per the MRAID spec, the current or default position is relative to the rectangle defined by the getMaxSize method,
            // that is, the largest size that the ad can resize to.
            CGPoint originInRootView = [self.rootViewController.view convertPoint:CGPointZero fromView:self];
            x = originInRootView.x;
            y = originInRootView.y;
            width = (int)self.frame.size.width;
            height = (int)self.frame.size.height;
        }
        
        UIInterfaceOrientation interfaceOrientation = [UIApplication sharedApplication].statusBarOrientation;
        BOOL isLandscape = UIInterfaceOrientationIsLandscape(interfaceOrientation);

        BOOL adjustOrientationForIOS8 = self.isInterstitial &&  isLandscape && !SYSTEM_VERSION_LESS_THAN(@"8.0");
        [self injectJavaScript:[NSString stringWithFormat:@"mraid.setCurrentPosition(%d,%d,%d,%d);", x, y, adjustOrientationForIOS8?height:width, adjustOrientationForIOS8?width:height]];
    }
}

- (void)fireStateChangeEvent
{
    @synchronized(self) {
        NSArray *stateNames = @[
                                @"loading",
                                @"default",
                                @"expanded",
                                @"resized",
                                @"hidden",
                                ];
        
        NSString *stateName = stateNames[self.state];
        [self injectJavaScript:[NSString stringWithFormat:@"mraid.fireStateChangeEvent('%@');", stateName]];
    }
}

- (void)fireViewableChangeEvent
{
    [self injectJavaScript:[NSString stringWithFormat:@"mraid.fireViewableChangeEvent(%@);", (self.isViewable ? @"true" : @"false")]];
}

- (void)setDefaultPosition
{
    if (self.isInterstitial) {
        // For interstitials, we define defaultPosition to be the same as screen size, so set the value there.
        return;
    }
    
    // getDefault position from the parent frame if we are not directly added to the rootview
    if(self.superview != self.rootViewController.view) {
        [self injectJavaScript:[NSString stringWithFormat:@"mraid.setDefaultPosition(%f,%f,%f,%f);", self.superview.frame.origin.x, self.superview.frame.origin.y, self.superview.frame.size.width, self.superview.frame.size.height]];
    } else {
        [self injectJavaScript:[NSString stringWithFormat:@"mraid.setDefaultPosition(%f,%f,%f,%f);", self.frame.origin.x, self.frame.origin.y, self.frame.size.width, self.frame.size.height]];
    }
}

-(void)setMaxSize
{
    if (self.isInterstitial) {
        // For interstitials, we define maxSize to be the same as screen size, so set the value there.
        return;
    }
    CGSize maxSize = self.rootViewController.view.bounds.size;
    if (!CGSizeEqualToSize(maxSize, self.previousMaxSize)) {
        [self injectJavaScript:[NSString stringWithFormat:@"mraid.setMaxSize(%d,%d);",
                                (int)maxSize.width,
                                (int)maxSize.height]];
        self.previousMaxSize = CGSizeMake(maxSize.width, maxSize.height);
    }
}

-(void)setScreenSize
{
    CGSize screenSize = [[UIScreen mainScreen] bounds].size;
    // screenSize is ALWAYS for portrait orientation, so we need to figure out the
    // actual interface orientation to get the correct current screenRect.
    UIInterfaceOrientation interfaceOrientation = [UIApplication sharedApplication].statusBarOrientation;
    BOOL isLandscape = UIInterfaceOrientationIsLandscape(interfaceOrientation);
    // [SKLogger debug:[NSString stringWithFormat:@"orientation is %@", (isLandscape ?  @"landscape" : @"portrait")]];
   
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"8.0")) {
        screenSize = CGSizeMake(screenSize.width, screenSize.height);
    } else {
        if (isLandscape) {
            screenSize = CGSizeMake(screenSize.height, screenSize.width);
        }
    }
    if (!CGSizeEqualToSize(screenSize, self.previousScreenSize)) {
        [self injectJavaScript:[NSString stringWithFormat:@"mraid.setScreenSize(%d,%d);",
                                (int)screenSize.width,
                                (int)screenSize.height]];
        self.previousScreenSize = CGSizeMake(screenSize.width, screenSize.height);
        if (self.isInterstitial) {
            [self injectJavaScript:[NSString stringWithFormat:@"mraid.setMaxSize(%d,%d);",
                                    (int)screenSize.width,
                                    (int)screenSize.height]];
            [self injectJavaScript:[NSString stringWithFormat:@"mraid.setDefaultPosition(0,0,%d,%d);",
                                    (int)screenSize.width,
                                    (int)screenSize.height]];
        }
    }
}

-(void)setSupports:(NSArray *)currentFeatures
{
    for (id aFeature in self.mraidFeatures) {
            [self injectJavaScript:[NSString stringWithFormat:@"mraid.setSupports('%@',%@);", aFeature,[currentFeatures containsObject:aFeature]?@"true":@"false"]];
    }
}

#pragma mark - UIWebViewDelegate

- (void)webViewDidStartLoad:(UIWebView *)wv
{
}

- (void)webViewDidFinishLoad:(UIWebView *)wv
{
    @synchronized(self) {
        // If wv is webViewPart2, that means the part 2 expanded web view has just loaded.
        // In this case, state should already be MRAIDStateExpanded and should not be changed.
        // if (wv != webViewPart2) {
        
        if (SK_ENABLE_JS_LOG) {
            [wv stringByEvaluatingJavaScriptFromString:@"var enableLog = true"];
        }
        
        if (SK_SUPPRESS_JS_ALERT) {
            [wv stringByEvaluatingJavaScriptFromString:@"function alert(){}; function prompt(){}; function confirm(){}"];
        }
        
        if (self.state == MRAIDStateLoading) {
            self.state = MRAIDStateDefault;
            [self injectJavaScript:[NSString stringWithFormat:@"mraid.setPlacementType('%@');", (self.isInterstitial ? @"interstitial" : @"inline")]];
            [self setSupports:self.supportedFeatures];
            [self setDefaultPosition];
            [self setMaxSize];
            [self setScreenSize];
            [self fireStateChangeEvent];
            [self fireSizeChangeEvent];
            [self fireReadyEvent];
            
            if ([self.delegate respondsToSelector:@selector(mraidViewAdReady:)]) {
                [self.delegate mraidViewAdReady:self];
            }
            
            // Start monitoring device orientation so we can reset max Size and screenSize if needed.
            [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(deviceOrientationDidChange:)
                                                         name:UIDeviceOrientationDidChangeNotification
                                                       object:nil];
        }
    }
}

- (void)webView:(UIWebView *)wv didFailLoadWithError:(NSError *)error
{
}

- (BOOL)webView:(UIWebView *)wv shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    NSURL *url = [request URL];
    NSString *scheme = [url scheme];
    NSString *absUrlString = [url absoluteString];
    
    if ([scheme isEqualToString:@"mraid"]) {
        [self parseCommandUrl:absUrlString];

    } else if ([scheme isEqualToString:@"console-log"]) {

    } else {
        
        // Links, Form submissions
        if (navigationType == UIWebViewNavigationTypeLinkClicked) {
            // For banner views
            if ([self.delegate respondsToSelector:@selector(mraidViewNavigate:withURL:)]) {
                [self.delegate mraidViewNavigate:self withURL:url];
            }
        } else {
            // Need to let browser to handle rendering and other things
            return YES;
        }
    }
    return NO;
}

#pragma mark - MRAIDModalViewControllerDelegate

- (void)mraidModalViewControllerDidRotate:(SKMRAIDModalViewController *)modalViewController
{
    [self setScreenSize];
    [self fireSizeChangeEvent];
}

#pragma mark - internal helper methods

- (void)initWebView:(UIWebView *)wv
{
    wv.delegate = self;
    wv.opaque = NO;
    wv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight |
    UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
    UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    wv.autoresizesSubviews = YES;
    
    if ([self.supportedFeatures containsObject:MRAIDSupportsInlineVideo]) {
        wv.allowsInlineMediaPlayback = YES;
        wv.mediaPlaybackRequiresUserAction = NO;
    } else {
        wv.allowsInlineMediaPlayback = NO;
        wv.mediaPlaybackRequiresUserAction = YES;
    }
    
    // disable scrolling
    UIScrollView *scrollView;
    if ([wv respondsToSelector:@selector(scrollView)]) {
        // UIWebView has a scrollView property in iOS 5+.
        scrollView = [wv scrollView];
    } else {
        // We have to look for the UIWebView's scrollView in iOS 4.
        for (id subview in [self subviews]) {
            if ([subview isKindOfClass:[UIScrollView class]]) {
                scrollView = subview;
                break;
            }
        }
    }
    scrollView.scrollEnabled = NO;
    
    // disable selection
    NSString *js = @"window.getSelection().removeAllRanges();";
    [wv stringByEvaluatingJavaScriptFromString:js];
    
    // Alert suppression
    if (SK_SUPPRESS_JS_ALERT)
        [wv stringByEvaluatingJavaScriptFromString:@"function alert(){}; function prompt(){}; function confirm(){}"];
}

- (void)parseCommandUrl:(NSString *)commandUrlString
{
    NSDictionary *commandDict = [self.mraidParser parseCommandUrl:commandUrlString];
    if (!commandDict) {
        return;
    }
    
    NSString *command = [commandDict valueForKey:@"command"];
    NSObject *paramObj = [commandDict valueForKey:@"paramObj"];
    
    SEL selector = NSSelectorFromString(command);
    
    // Turn off the warning "PerformSelector may cause a leak because its selector is unknown".
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    
    [self performSelector:selector withObject:paramObj];
    
#pragma clang diagnostic pop
}

#pragma mark - Gesture Methods

-(void)setUpTapGestureRecognizer
{
    if(!SK_SUPPRESS_BANNER_AUTO_REDIRECT){
        return;  // return without adding the GestureRecognizer if the feature is not enabled
    }
    // One finger, one tap
    self.tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(oneFingerOneTap)];
    
    // Set up
    [self.tapGestureRecognizer setNumberOfTapsRequired:1];
    [self.tapGestureRecognizer setNumberOfTouchesRequired:1];
    [self.tapGestureRecognizer setDelegate:self];
    
    // Add the gesture to the view
    [self addGestureRecognizer:self.tapGestureRecognizer];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;   // required to allow UIWebview to work correctly, see  http://stackoverflow.com/questions/2909807/does-uigesturerecognizer-work-on-a-uiwebview
}

-(void)oneFingerOneTap
{
    self.bonafideTapObserved=YES;
    self.tapGestureRecognizer.delegate=nil;
    self.tapGestureRecognizer=nil;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    if (touch.view == self.resizeCloseRegion || touch.view == self.closeEventRegion){
        return NO;
    }
    return YES;
}

@end