// Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// wkwebview_probe: can this machine create an AppKit window with a WKWebView,
// load a page, and run JavaScript? Used by .github/workflows/macos-probe.yml
// to decide whether a native macOS host can be tested on a hosted runner.
//
//     clang -fobjc-arc -framework Cocoa -framework WebKit \
//       test/macos/wkwebview_probe.m -o probe
//
//     ./probe html                       # load an HTML string
//     ./probe http://127.0.0.1:8765/x.html
//     ./probe html --accessory           # no Dock icon
//     ./probe html --hidden              # window not ordered front
//     ./probe --ws=ws://127.0.0.1:18766/ # page opens a WebSocket
//
// Exit status: 0 on success; 2 window/setup failure; 3 navigation failure or
// timeout; 4 JavaScript evaluation failure; 5 title mismatch; 6 WebSocket did
// not open.

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

#include <fenv.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static volatile int gLoaded = 0;
static volatile int gNavFailed = 0;

@interface ProbeNavigation : NSObject <WKNavigationDelegate>
@end

@implementation ProbeNavigation

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
  (void)webView;
  (void)navigation;
  fprintf(stderr, "CHECKPOINT didFinishNavigation\n");
  gLoaded = 1;
}

- (void)webView:(WKWebView *)webView
    didFailNavigation:(WKNavigation *)navigation
            withError:(NSError *)error {
  (void)webView;
  (void)navigation;
  fprintf(stderr, "CHECKPOINT didFailNavigation: %s\n",
          [[error localizedDescription] UTF8String]);
  gNavFailed = 1;
}

- (void)webView:(WKWebView *)webView
    didFailProvisionalNavigation:(WKNavigation *)navigation
                       withError:(NSError *)error {
  (void)webView;
  (void)navigation;
  fprintf(stderr, "CHECKPOINT didFailProvisionalNavigation: %s\n",
          [[error localizedDescription] UTF8String]);
  gNavFailed = 1;
}

@end

static void pump(NSApplication *app, double seconds) {
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
  while ([deadline timeIntervalSinceNow] > 0) {
    @autoreleasepool {
      NSEvent *event =
          [app nextEventMatchingMask:NSEventMaskAny
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

static NSWindow *makeWindow(WKWebView *web, const char *title) {
  NSRect frame = NSMakeRect(0, 0, 800, 600);
  NSWindow *window = [[NSWindow alloc]
      initWithContentRect:frame
                styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                           NSWindowStyleMaskResizable)
                  backing:NSBackingStoreBuffered
                    defer:NO];
  if (window == nil) {
    return nil;
  }
  [window setTitle:[NSString stringWithUTF8String:title]];
  [window setContentView:web];
  [window center];
  return window;
}

static void installMenu(NSApplication *app) {
  NSMenu *menubar = [[NSMenu alloc] init];
  NSMenuItem *appItem = [[NSMenuItem alloc] init];
  [menubar addItem:appItem];
  [app setMainMenu:menubar];

  NSMenu *appMenu = [[NSMenu alloc] init];
  [appMenu addItemWithTitle:@"Quit"
                     action:@selector(terminate:)
              keyEquivalent:@"q"];
  [appItem setSubmenu:appMenu];
}

int main(int argc, char **argv) {
  @autoreleasepool {
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    // FPC unmasks floating-point exceptions by default. AppKit and WebKit raise
    // them during normal operation, so restore the C environment first, exactly
    // as the Linux GTK host does.
    fesetenv(FE_DFL_ENV);

    const char *urlArg = NULL;
    const char *wsArg = NULL;
    const char *expectTitle = NULL;
    int accessory = 0;
    int hidden = 0;

    for (int i = 1; i < argc; i++) {
      if (strcmp(argv[i], "--accessory") == 0) {
        accessory = 1;
      } else if (strcmp(argv[i], "--hidden") == 0) {
        hidden = 1;
      } else if (strncmp(argv[i], "--expect=", 9) == 0) {
        expectTitle = argv[i] + 9;
      } else if (strncmp(argv[i], "--ws=", 5) == 0) {
        wsArg = argv[i] + 5;
      } else if (urlArg == NULL) {
        urlArg = argv[i];
      }
    }

    const char *bundle = [[[NSBundle mainBundle] bundleIdentifier] UTF8String];
    fprintf(stderr, "PROBE: pid=%d bundle=%s\n", (int)getpid(),
            bundle != NULL ? bundle : "(none)");
    fprintf(stderr, "PROBE: accessory=%s hidden=%s target=%s ws=%s\n",
            accessory ? "yes" : "no", hidden ? "yes" : "no",
            urlArg != NULL ? urlArg : "(html string)",
            wsArg != NULL ? wsArg : "(none)");

    NSApplication *app = [NSApplication sharedApplication];
    if (app == nil) {
      fprintf(stderr, "PROBE: [NSApplication sharedApplication] failed\n");
      return 2;
    }
    [app setActivationPolicy:accessory ? NSApplicationActivationPolicyAccessory
                                       : NSApplicationActivationPolicyRegular];
    installMenu(app);
    [app finishLaunching];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    WKWebView *web = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)
                                        configuration:config];
    if (web == nil) {
      fprintf(stderr, "PROBE: WKWebView allocation failed\n");
      return 2;
    }
    ProbeNavigation *navigation = [[ProbeNavigation alloc] init];
    [web setNavigationDelegate:navigation];

    NSWindow *window = makeWindow(web, "wkwebview-probe");
    if (window == nil) {
      fprintf(stderr, "PROBE: NSWindow creation failed\n");
      return 2;
    }

    if (hidden) {
      [window orderOut:nil];
    } else {
      [window makeKeyAndOrderFront:nil];
      [app activateIgnoringOtherApps:YES];
    }

    if (urlArg != NULL) {
      NSString *urlString = [NSString stringWithUTF8String:urlArg];
      NSURL *url = [NSURL URLWithString:urlString];
      if (url == nil) {
        fprintf(stderr, "PROBE: invalid URL %s\n", urlArg);
        return 2;
      }
      [web loadRequest:[NSURLRequest requestWithURL:url]];
    } else if (wsArg != NULL) {
      NSString *wsURL = [NSString stringWithUTF8String:wsArg];
      NSString *html = [NSString
          stringWithFormat:
              @"<!doctype html><html><head><title>probe-ok</title></head>"
               "<body><h1>probe ws</h1><script>"
               "window.__wsState='connecting';"
               "try{var ws=new WebSocket('%@');"
               "ws.onopen=function(){window.__wsState='open';};"
               "ws.onerror=function(){if(window.__wsState!=='open')"
               "window.__wsState='error';};"
               "ws.onclose=function(){if(window.__wsState!=='open')"
               "window.__wsState='closed';};"
               "}catch(e){window.__wsState='throw:'+e.message;}"
               "</script></body></html>",
              wsURL];
      // WKWebView needs a base URL with a scheme; nil makes the load silently
      // fail with CFURLCopyResourcePropertyForKey "URL has no scheme".
      [web loadHTMLString:html
                  baseURL:[NSURL URLWithString:@"http://127.0.0.1/"]];
    } else {
      NSString *html =
          @"<!doctype html><html><head><title>probe-ok</title></head>"
           "<body><h1>probe</h1></body></html>";
      [web loadHTMLString:html
                  baseURL:[NSURL URLWithString:@"http://127.0.0.1/"]];
    }

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:20.0];
    while (!gLoaded && !gNavFailed && [deadline timeIntervalSinceNow] > 0) {
      pump(app, 0.1);
    }
    fprintf(stderr, "PROBE: load loaded=%d failed=%d remaining=%.1f\n", gLoaded,
            gNavFailed, [deadline timeIntervalSinceNow]);

    if (!gLoaded || gNavFailed) {
      fprintf(stderr, "PROBE: navigation did not complete\n");
      [web stopLoading];
      return 3;
    }

    if (wsArg != NULL) {
      __block NSString *wsState = nil;
      NSDate *wsDeadline = [NSDate dateWithTimeIntervalSinceNow:10.0];
      while ([wsDeadline timeIntervalSinceNow] > 0) {
        __block int stateDone = 0;
        [web evaluateJavaScript:@"window.__wsState || 'missing'"
              completionHandler:^(id result, NSError *error) {
                if (error == nil) {
                  wsState = [result description];
                } else {
                  wsState = [@"eval-error:" stringByAppendingString:
                                 [error localizedDescription]];
                }
                stateDone = 1;
              }];
        NSDate *stateDeadline = [NSDate dateWithTimeIntervalSinceNow:0.5];
        while (!stateDone && [stateDeadline timeIntervalSinceNow] > 0) {
          pump(app, 0.02);
        }
        fprintf(stderr, "PROBE: wsState=%s\n",
                wsState != nil ? [wsState UTF8String] : "(nil)");
        if (wsState != nil &&
            ([wsState isEqualToString:@"open"] ||
             [wsState hasPrefix:@"error"] ||
             [wsState hasPrefix:@"closed"] ||
             [wsState hasPrefix:@"throw"] ||
             [wsState hasPrefix:@"eval-error"])) {
          break;
        }
        pump(app, 0.2);
      }
      if (wsState == nil || ![wsState isEqualToString:@"open"]) {
        fprintf(stderr, "PROBE: WebSocket did not open\n");
        return 6;
      }
    }

    __block NSArray *jsResult = nil;
    __block NSString *jsError = nil;
    __block int jsDone = 0;
    NSString *script =
        @"[document.title, typeof WebSocket, typeof CompressionStream, "
         "typeof TextDecoder, navigator.userAgent]";
    [web evaluateJavaScript:script
          completionHandler:^(id result, NSError *error) {
            if (error != nil) {
              jsError = [error localizedDescription];
            } else if ([result isKindOfClass:[NSArray class]]) {
              jsResult = (NSArray *)result;
            } else {
              jsError = [NSString
                  stringWithFormat:@"unexpected result class %@",
                                   NSStringFromClass([result class])];
            }
            jsDone = 1;
          }];

    NSDate *jsDeadline = [NSDate dateWithTimeIntervalSinceNow:10.0];
    while (!jsDone && [jsDeadline timeIntervalSinceNow] > 0) {
      pump(app, 0.05);
    }

    if (!jsDone || jsResult == nil) {
      fprintf(stderr, "PROBE: evaluateJavaScript failed: %s\n",
              jsError != nil ? [jsError UTF8String] : "(timeout)");
      return 4;
    }

    fprintf(stderr, "PROBE: title=%s\n", [[jsResult[0] description] UTF8String]);
    fprintf(stderr, "PROBE: WebSocket=%s CompressionStream=%s TextDecoder=%s\n",
            [[jsResult[1] description] UTF8String],
            [[jsResult[2] description] UTF8String],
            [[jsResult[3] description] UTF8String]);
    fprintf(stderr, "PROBE: userAgent=%s\n",
            [[jsResult[4] description] UTF8String]);

    if (![[jsResult[1] description] isEqualToString:@"function"]) {
      fprintf(stderr, "PROBE: WebSocket is not available in this WebView\n");
      return 4;
    }
    if (expectTitle != NULL) {
      NSString *expected = [NSString stringWithUTF8String:expectTitle];
      if (![[jsResult[0] description] isEqualToString:expected]) {
        fprintf(stderr, "PROBE: title mismatch, expected %s\n", expectTitle);
        return 5;
      }
    }

    // Let WebKit finish a few pending callbacks before tearing down.
    pump(app, 0.3);
    [window orderOut:nil];
    fprintf(stderr, "PROBE: OK\n");
    return 0;
  }
}
