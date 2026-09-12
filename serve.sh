#!/bin/sh
# Serve docs/ with caching DISABLED.
#
# python -m http.server sends no cache headers at all, so Chrome is free to reuse
# sealed.html indefinitely — and does. A ?v= bump inside the HTML cannot help when
# the HTML itself is the stale copy, and Ctrl+Shift+R does not always dislodge it
# either. That cost a debugging cycle: loader changes appeared not to land, while
# the console still showed the previous ?v=.
#
# So every response here carries no-store. Development only — this is the
# opposite of what you want in front of a real site.
cd "$(dirname "$0")/docs"
exec python3 -c '
import http.server, sys

class NoCache(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

port = int(sys.argv[1]) if len(sys.argv) > 1 else 3333
print(f"ZigMachine on http://localhost:{port}/sealed.html  (no-store: every reload is fresh)")
http.server.test(HandlerClass=NoCache, port=port, bind="127.0.0.1")
' "$@"
