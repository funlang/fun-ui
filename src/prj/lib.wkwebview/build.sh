#!/bin/sh
# Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
# SPDX-License-Identifier: MIT
#
# Build the macOS AppKit + WKWebView window host.
#
#   ./build.sh              # libui2wkwebview.dylib next to host.m
#   CC=clang ./build.sh
#
# Requires the macOS SDK (Cocoa and WebKit) and a compiler with ARC support.

set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
CC="${CC:-clang}"
OUT="$HERE/libui2wkwebview.dylib"

if ! command -v "$CC" >/dev/null 2>&1; then
    echo "build.sh: $CC not found" >&2
    exit 1
fi

set -- -O2 -fobjc-arc -fPIC -Wall -Wextra -Wno-deprecated-declarations \
    -dynamiclib -framework Cocoa -framework WebKit \
    -o "$OUT" "$HERE/host.m"

echo "Building libui2wkwebview.dylib with $CC"
"$CC" "$@"

# Apple Silicon requires a code signature. clang's linker usually adds an
# ad-hoc one for arm64; make it explicit so the dylib also loads when copied
# to another machine.
if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - "$OUT" >/dev/null 2>&1 || true
fi

echo "Built $OUT"
