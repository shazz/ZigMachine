#!/usr/bin/env python3
"""Serve docs/ for development, with caching DISABLED and a loud port check.

WHY NO-STORE: python -m http.server sends no cache headers at all, so Chrome is
free to reuse sealed.html indefinitely — and does. A ?v= bump inside the HTML
cannot help when the HTML itself is the stale copy, and Ctrl+Shift+R does not
always dislodge it. That cost a debugging cycle: loader changes appeared not to
land while the console still showed the previous ?v=.

WHY THE PORT CHECK: a second server started from a second WORKTREE can fail to
bind in a way that is easy to miss when backgrounded, and you then test the other
checkout while reading this source tree. That happened to a parallel session; the
only tell was the served sealed-loader.js being shorter than the file on disk.

WHY A FILE AND NOT `python3 -c` INSIDE serve.sh: it was inline, and an apostrophe
in a comment closed the single-quoted shell string, spilling the rest into
argv — a bug with no plausible connection to its symptom. Prose belongs in a file
the shell does not parse.

Development only: no-store is the opposite of what a real site wants.

Usage: tools/serve.py [port]      (default 3333; use one port per worktree)
"""
import http.server
import os
import socket
import sys

DEFAULT_PORT = 3333


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def log_message(self, fmt, *args):  # quieter: one line per request, no date noise
        sys.stderr.write("  %s\n" % (fmt % args))


def port_is_serving(port: int) -> bool:
    """True if something already answers on this port."""
    probe = socket.socket()
    probe.settimeout(0.25)
    try:
        probe.connect(("127.0.0.1", port))
        return True
    except OSError:
        return False
    finally:
        probe.close()


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PORT
    if port_is_serving(port):
        sys.exit(
            f"serve.py: port {port} is ALREADY SERVING something, probably another "
            f"worktree.\nRefusing to start: the usual symptom is testing that "
            f"checkout while reading this one.\nPick another port, e.g. "
            f"tools/serve.py {port + 2}"
        )
    print(f"ZigMachine on http://localhost:{port}/sealed.html")
    print(f"  serving {os.path.realpath(os.getcwd())}")
    print("  no-store: every reload is fresh")
    http.server.test(HandlerClass=NoCacheHandler, port=port, bind="127.0.0.1")


if __name__ == "__main__":
    main()
