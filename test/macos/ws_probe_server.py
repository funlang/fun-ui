#!/usr/bin/env python3
# Copyright (c) 2026 Zhang Weidong <zwd@funlang.org>
# SPDX-License-Identifier: MIT
#
# Minimal WebSocket handshake server for test/macos/wkwebview_probe.m.
# It accepts one connection, answers the upgrade, and keeps the socket open
# while the probe checks that WebKit fired `onopen`.
#
#     python3 test/macos/ws_probe_server.py 18766

import base64
import hashlib
import socket
import sys
import time

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def main() -> int:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18766
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", port))
    server.listen(1)
    print("listening", flush=True)

    conn, _ = server.accept()
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = conn.recv(4096)
        if not chunk:
            return 1
        data += chunk

    key = None
    for line in data.decode("latin1").split("\r\n"):
        if line.lower().startswith("sec-websocket-key:"):
            key = line.split(":", 1)[1].strip()
    if not key:
        print("missing Sec-WebSocket-Key", flush=True)
        return 1

    accept = base64.b64encode(
        hashlib.sha1((key + GUID).encode()).digest()
    ).decode()
    conn.sendall(
        (
            "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
        ).encode()
    )
    print("handshake ok", flush=True)

    # Keep the connection open while the probe polls window.__wsState.
    time.sleep(20)
    conn.close()
    server.close()
    print("closed", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
