#!/bin/sh
# Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
# SPDX-License-Identifier: MIT
#
# Build the GTK3 + WebKit2GTK window host.
#
#   ./build.sh              # libui2webkitgtk.so next to host.c
#   CC=clang ./build.sh
#
# Requires gtk+-3.0 and webkit2gtk-4.1 (or 4.0) development files.

set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
CC="${CC:-cc}"
PKG=""

for candidate in webkit2gtk-4.1 webkit2gtk-4.0; do
    if pkg-config --exists "gtk+-3.0" "$candidate" 2>/dev/null; then
        PKG="$candidate"
        break
    fi
done

if [ -z "$PKG" ]; then
    echo "build.sh: gtk+-3.0 and webkit2gtk-4.1/4.0 development files are required" >&2
    exit 1
fi

set -- -O2 -fPIC -shared -o "$HERE/libui2webkitgtk.so" "$HERE/host.c"
set -- "$@" $(pkg-config --cflags --libs "gtk+-3.0" "$PKG")

echo "Building libui2webkitgtk.so with $PKG"
exec "$CC" "$@"
