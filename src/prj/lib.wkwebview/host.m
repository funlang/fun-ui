// Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// host.m: minimal AppKit + WKWebView window host for fun-ui on macOS.
//
// This is the macOS counterpart of src/prj/lib.webkitgtk/host.c. Like the
// Linux host it only creates a window, loads a URL, pumps events, and sets the
// title: the page talks to Fun over the WebSocket transport from
// lib-ui2-proxy-unx.fun, so there is no script-message bridge here.
//
// Build with build.sh, then point Ui2Form.hostLib at the resulting
// libui2wkwebview.dylib.
//
// All entry points must be called on the main thread. Fun's poll loop owns the
// main thread, so ui2_wk_iterate() drains AppKit and WebKit work on each round.

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

#include <fenv.h>
#include <stdio.h>
#include <string.h>

#define UI2_EXPORT __attribute__((visibility("default")))

static NSWindow *gWindow = nil;
static WKWebView *gWebView = nil;
static WKWebViewConfiguration *gConfiguration = nil;

@interface Ui2NavigationDelegate : NSObject <WKNavigationDelegate>
@end

@interface Ui2WindowDelegate : NSObject <NSWindowDelegate>
@end

@interface Ui2MenuTarget : NSObject
- (void)ui2CloseWindow:(id)sender;
- (void)ui2Quit:(id)sender;
@end

static Ui2NavigationDelegate *gNavigationDelegate = nil;
static Ui2WindowDelegate *gWindowDelegate = nil;
static Ui2MenuTarget *gMenuTarget = nil;

static int gInitialized = 0;
static int gClosed = 1;

// FPC unmasks floating-point exceptions by default. AppKit, WebKit and Skia
// raise them during normal operation, so restore the C environment before
// entering framework code, exactly as the Linux GTK host does.
static void ui2MaskFP(void) {
    fesetenv(FE_DFL_ENV);
}

static void ui2PumpEvents(NSApplication *app, double seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([deadline timeIntervalSinceNow] > 0) {
        @autoreleasepool {
            NSEvent *event = [app
                nextEventMatchingMask:NSEventMaskAny
                            untilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]
                               inMode:NSDefaultRunLoopMode
                              dequeue:YES];
            if (event != nil) {
                [app sendEvent:event];
            }
            [app updateWindows];
        }
    }
}

@implementation Ui2NavigationDelegate

- (void)webView:(WKWebView *)webView
    didFinishNavigation:(WKNavigation *)navigation {
    (void)webView;
    (void)navigation;
    fprintf(stderr, "ui2_wk: navigation finished\n");
}

- (void)webView:(WKWebView *)webView
    didFailNavigation:(WKNavigation *)navigation
            withError:(NSError *)error {
    (void)webView;
    (void)navigation;
    fprintf(stderr, "ui2_wk: navigation failed: %s\n",
            [[error localizedDescription] UTF8String]);
}

- (void)webView:(WKWebView *)webView
    didFailProvisionalNavigation:(WKNavigation *)navigation
                       withError:(NSError *)error {
    (void)webView;
    (void)navigation;
    fprintf(stderr, "ui2_wk: provisional navigation failed: %s\n",
            [[error localizedDescription] UTF8String]);
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    (void)webView;
    fprintf(stderr, "ui2_wk: web content process terminated\n");
}

@end

@implementation Ui2WindowDelegate

- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
    fprintf(stderr, "ui2_wk: window closed\n");
    gClosed = 1;
}

@end

@implementation Ui2MenuTarget

- (void)ui2CloseWindow:(id)sender {
    (void)sender;
    if (gWindow != nil) {
        [gWindow performClose:nil];
    }
}

- (void)ui2Quit:(id)sender {
    (void)sender;
    gClosed = 1;
    if (gWindow != nil) {
        [gWindow orderOut:nil];
        [gWindow close];
    }
}

@end

static void ui2InstallMenu(NSApplication *app) {
    gMenuTarget = [[Ui2MenuTarget alloc] init];

    NSMenu *menubar = [[NSMenu alloc] init];

    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    [menubar addItem:appItem];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"fun-ui"];
    [appItem setSubmenu:appMenu];

    NSMenuItem *closeItem =
        [appMenu addItemWithTitle:@"Close Window"
                           action:@selector(ui2CloseWindow:)
                    keyEquivalent:@"w"];
    [closeItem setTarget:gMenuTarget];
    NSMenuItem *quitItem =
        [appMenu addItemWithTitle:@"Quit fun-ui"
                           action:@selector(ui2Quit:)
                    keyEquivalent:@"q"];
    [quitItem setTarget:gMenuTarget];

    NSMenuItem *editItem = [[NSMenuItem alloc] init];
    [menubar addItem:editItem];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editItem setSubmenu:editMenu];
    [editMenu addItemWithTitle:@"Undo"
                        action:@selector(undo:)
                 keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"Redo"
                        action:@selector(redo:)
                 keyEquivalent:@"Z"];
    [editMenu addItemWithTitle:@"Cut"
                        action:@selector(cut:)
                 keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy"
                        action:@selector(copy:)
                 keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste"
                        action:@selector(paste:)
                 keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All"
                        action:@selector(selectAll:)
                 keyEquivalent:@"a"];

    [app setMainMenu:menubar];
}

UI2_EXPORT int ui2_wk_init(void) {
    ui2MaskFP();
    if (gInitialized) {
        return 1;
    }
    if (![NSThread isMainThread]) {
        fprintf(stderr, "ui2_wk: init must run on the main thread\n");
        return 0;
    }
    @autoreleasepool {
        @try {
            NSApplication *app = [NSApplication sharedApplication];
            if (app == nil) {
                return 0;
            }
            [app setActivationPolicy:NSApplicationActivationPolicyRegular];
            ui2InstallMenu(app);
            [app finishLaunching];
            gInitialized = 1;
            return 1;
        } @catch (NSException *exception) {
            fprintf(stderr, "ui2_wk: init exception: %s\n",
                    [[exception reason] UTF8String]);
            return 0;
        }
    }
}

UI2_EXPORT int ui2_wk_show(const char *url, int width, int height,
                           const char *title) {
    ui2MaskFP();
    if (!gInitialized) {
        return 0;
    }
    if (gWindow != nil) {
        return 1;
    }
    if (url == NULL || *url == '\0') {
        return 0;
    }
    if (width <= 0) {
        width = 1024;
    }
    if (height <= 0) {
        height = 768;
    }

    @autoreleasepool {
        @try {
            NSRect frame = NSMakeRect(0, 0, width, height);
            gWindow = [[NSWindow alloc]
                initWithContentRect:frame
                          styleMask:(NSWindowStyleMaskTitled |
                                     NSWindowStyleMaskClosable |
                                     NSWindowStyleMaskResizable |
                                     NSWindowStyleMaskMiniaturizable)
                            backing:NSBackingStoreBuffered
                              defer:NO];
            if (gWindow == nil) {
                return 0;
            }
            [gWindow setTitle:[NSString stringWithUTF8String:
                                           title != NULL ? title : "fun-ui"]];
            [gWindow setReleasedWhenClosed:NO];

            gConfiguration = [[WKWebViewConfiguration alloc] init];
            gWebView = [[WKWebView alloc]
                initWithFrame:frame
                configuration:gConfiguration];
            if (gWebView == nil) {
                [gWindow close];
                gWindow = nil;
                return 0;
            }

            gNavigationDelegate = [[Ui2NavigationDelegate alloc] init];
            gWindowDelegate = [[Ui2WindowDelegate alloc] init];
            [gWebView setNavigationDelegate:gNavigationDelegate];
            [gWindow setDelegate:gWindowDelegate];
            [gWindow setContentView:gWebView];
            [gWindow center];
            [gWindow makeKeyAndOrderFront:nil];
            [NSApp activateIgnoringOtherApps:YES];

            NSString *urlString = [NSString stringWithUTF8String:url];
            NSURL *nsURL = [NSURL URLWithString:urlString];
            if (nsURL == nil) {
                fprintf(stderr, "ui2_wk: invalid URL: %s\n", url);
                [gWindow close];
                gWindow = nil;
                gWebView = nil;
                return 0;
            }
            [gWebView loadRequest:[NSURLRequest requestWithURL:nsURL]];

            gClosed = 0;
            return 1;
        } @catch (NSException *exception) {
            fprintf(stderr, "ui2_wk: show exception: %s\n",
                    [[exception reason] UTF8String]);
            return 0;
        }
    }
}

UI2_EXPORT int ui2_wk_iterate(void) {
    ui2MaskFP();
    if (gWindow == nil) {
        return 0;
    }
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        for (int i = 0; i < 200; i++) {
            NSEvent *event = [app
                nextEventMatchingMask:NSEventMaskAny
                            untilDate:[NSDate distantPast]
                               inMode:NSDefaultRunLoopMode
                              dequeue:YES];
            if (event == nil) {
                break;
            }
            [app sendEvent:event];
        }
        [[NSRunLoop currentRunLoop]
            runMode:NSDefaultRunLoopMode
            beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
        [app updateWindows];
    }
    return gClosed ? 0 : 1;
}

UI2_EXPORT int ui2_wk_set_title(const char *title) {
    ui2MaskFP();
    if (gWindow == nil) {
        return 0;
    }
    @autoreleasepool {
        [gWindow setTitle:[NSString stringWithUTF8String:
                                       title != NULL ? title : "fun-ui"]];
    }
    return 1;
}

UI2_EXPORT int ui2_wk_close(void) {
    ui2MaskFP();
    gClosed = 1;
    @autoreleasepool {
        if (gWebView != nil) {
            [gWebView stopLoading];
            [gWebView setNavigationDelegate:nil];
        }
        if (gWindow != nil) {
            [gWindow setDelegate:nil];
            [gWindow orderOut:nil];
            [gWindow close];
            gWindow = nil;
        }
        gWebView = nil;
        gConfiguration = nil;
        gNavigationDelegate = nil;
        gWindowDelegate = nil;

        // WebKit terminates its web and network processes asynchronously.
        // Drain the main run loop briefly so they are reaped before the Fun
        // process exits, as the Linux host does.
        NSApplication *app = [NSApplication sharedApplication];
        ui2PumpEvents(app, 0.75);
    }
    return 1;
}

UI2_EXPORT int ui2_wk_free(void) {
    return ui2_wk_close();
}
