// Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
// SPDX-License-Identifier: MIT
//
// host.c: minimal GTK3 + WebKit2GTK window host for fun-ui.
//
// This is the Linux counterpart of libwv2.dll, but much smaller: the page
// itself talks to the Fun process over the WebSocket transport from
// lib-ui2-proxy-unx.fun, so this host only needs to create a window, load a
// URL, and pump GTK events. There is no script-message handler, no shared
// buffer, and no fCAL response buffer here.
//
// Build with build.sh (pkg-config selects webkit2gtk-4.1 or 4.0).

#include <gtk/gtk.h>
#include <webkit2/webkit2.h>

static GtkWidget *g_window = NULL;
static GtkWidget *g_webview = NULL;
static int g_closed = 1;

static void on_destroy(GtkWidget *widget, gpointer data) {
    (void)widget;
    (void)data;
    g_closed = 1;
}

int ui2_gtk_init(void) {
    if (!gtk_init_check(NULL, NULL)) {
        return 0;
    }
    return 1;
}

// Returns 1 on success, 0 on failure. The caller only needs a flag, so no
// pointer crosses the Fun FFI boundary.
int ui2_gtk_show(const char *url, int width, int height, const char *title) {
    if (g_window != NULL) {
        return 1;
    }
    if (url == NULL || *url == '\0') {
        return 0;
    }
    if (width <= 0) width = 1024;
    if (height <= 0) height = 768;

    g_window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    if (g_window == NULL) {
        return 0;
    }
    gtk_window_set_title(GTK_WINDOW(g_window), title != NULL ? title : "fun-ui");
    gtk_window_set_default_size(GTK_WINDOW(g_window), width, height);
    g_signal_connect(g_window, "destroy", G_CALLBACK(on_destroy), NULL);

    g_webview = webkit_web_view_new();
    if (g_webview == NULL) {
        gtk_widget_destroy(g_window);
        g_window = NULL;
        return 0;
    }
    gtk_container_add(GTK_CONTAINER(g_window), g_webview);
    webkit_web_view_load_uri(WEBKIT_WEB_VIEW(g_webview), url);
    gtk_widget_show_all(g_window);

    g_closed = 0;
    return 1;
}

// Pump pending GTK/WebKit events without blocking. Returns 1 while the window
// is alive, 0 after it was closed.
int ui2_gtk_iterate(void) {
    while (gtk_events_pending()) {
        gtk_main_iteration_do(FALSE);
    }
    return g_closed ? 0 : 1;
}

int ui2_gtk_closed(void) {
    return g_closed;
}

int ui2_gtk_set_title(const char *title) {
    if (g_window == NULL) {
        return 0;
    }
    gtk_window_set_title(GTK_WINDOW(g_window), title != NULL ? title : "fun-ui");
    return 1;
}

int ui2_gtk_close(void) {
    if (g_window != NULL) {
        gtk_widget_destroy(g_window);
        g_window = NULL;
    }
    g_webview = NULL;
    g_closed = 1;
    return 1;
}

int ui2_gtk_free(void) {
    ui2_gtk_close();
    return 1;
}
