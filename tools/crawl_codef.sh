#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# crawl_codef.sh — mirror shazz's Codef HTML5 remakes (source + assets) for
# reference when porting effects to ZigMachine.
#
# Two phases:
#   1. MIRROR  — recursive, no-parent wget over the Apache autoindex: grabs the
#                HTML/JS every directory links and lists.
#   2. HARVEST — the Codef demos load their assets (png/ym/mod/…) from JS string
#                tables (resources.js: `src: "screens/intro/logo.png"`), which
#                wget's link-follower never sees. This phase parses the fetched
#                JS/HTML/JSON for server-local asset paths, resolves each against
#                its own file URL, and fetches the missing ones (no-clobber).
#
# Usage:
#   tools/crawl_codef.sh [--assets-only] [SUBPATH] [OUTPUT_DIR]
#     --assets-only  skip the mirror; only run the HARVEST pass over OUTPUT_DIR
#                    (use when the mirror is already done and you just need the
#                    JS-referenced binaries — nothing already present is refetched)
#     SUBPATH        path under Remakes/ to mirror (default: whole tree)
#     OUTPUT_DIR     local destination (default: assets/oldies)
#
# Re-runs never re-download: the mirror uses -N (timestamping) and the harvest
# uses -nc (no-clobber), so only new/missing files are fetched.
# ---------------------------------------------------------------------------
set -euo pipefail

BASE="https://shazz.untergrund.net/codef/__Demos__/Remakes"
UA="Mozilla/5.0 (codef-mirror; +ZigMachine reference)"
JOBS="${CRAWL_JOBS:-8}"      # parallel workers for the harvest phase
MAX_404="${CRAWL_MAX_404:-20}" # abort the harvest if more than this many URLs 404

MIRROR=1
if [ "${1:-}" = "--assets-only" ]; then MIRROR=0; shift; fi
SUBPATH="${1:-}"
OUT="${2:-assets/oldies}"

# Normalise: ensure exactly one trailing slash on the start URL (wget needs the
# dir form so -np scopes to it, not its parent).
START="${BASE%/}/${SUBPATH#/}"
START="${START%/}/"

mkdir -p "$OUT"

# ---------------------------------------------------------------------------
# Phase 1 — MIRROR
# ---------------------------------------------------------------------------
if [ "$MIRROR" = 1 ]; then
  echo "== MIRROR =="
  echo "From: $START"
  echo "Into: $OUT"
  # -r/-np/-l inf : recurse the subtree, never ascend above START
  # -nH --cut-dirs=3 : drop host + "codef/__Demos__/Remakes", so demo folders
  #                    land directly under OUTPUT_DIR (oldies/, Union-.../, ...)
  # -R / --reject-regex : skip the autoindex sort links (?C=N;O=D ...) + junk
  # -e robots=off : shazz's own content; the codef tree ships no crawl budget
  # -N : timestamp so re-runs skip unchanged files
  #
  # wget exit 8 = server issued an error for SOME url (a page links a file that
  # 404s) — the mirror still completes, so 8 is a warning, not a failure.
  set +e
  wget \
    --recursive --no-parent --level=inf \
    --no-host-directories --cut-dirs=3 \
    --directory-prefix="$OUT" \
    --reject "index.html?*,desktop.ini,*.tmp" \
    --reject-regex='(\?C=[NMSD]|\?O=[AD]|;O=[AD])' \
    --execute robots=off \
    --timestamping \
    --retry-connrefused --tries=3 --timeout=30 \
    --wait=0.3 --random-wait \
    --user-agent="$UA" \
    "$START"
  rc=$?
  set -e
  if [ "$rc" -eq 8 ]; then
    echo "NOTE: wget exit 8 — some linked files 404'd (dead links); mirror is complete."
  elif [ "$rc" -ne 0 ]; then
    echo "WARNING: wget exited $rc — mirror may be incomplete (network/other error)."
  fi
fi

# ---------------------------------------------------------------------------
# Phase 2 — HARVEST (JS/HTML/JSON-referenced, server-local assets)
# ---------------------------------------------------------------------------
echo
echo "== HARVEST (assets referenced from JS/HTML/JSON) =="
LIST="$(mktemp)"
python3 - "$OUT" "$BASE" >"$LIST" <<'PY'
import os, re, sys
from urllib.parse import urljoin
out, base = sys.argv[1], sys.argv[2].rstrip('/') + '/'
# `base` maps to local `out` (cut-dirs=3 stripped codef/__Demos__/Remakes), so
# local out/REST corresponds to server base/REST.
exts = (r'png|jpe?g|gif|bmp|webp|ym|mod|sndh?|sam|raw|pcm|bin|binz|dat|'
        r'tmx|tsx|mp3|ogg|wav|mid|xm|s3m|it|nsf|zip|7z')
pat = re.compile(r'''["']([^"'<>\s]+?\.(?:%s))["']''' % exts, re.I)
scan = ('.js', '.html', '.htm', '.json')
absout = os.path.abspath(out)

def url_of(local_dir):
    rel = os.path.relpath(local_dir, out).replace(os.sep, '/')
    return base if rel == '.' else base + rel + '/'

# Codef asset paths are relative to the DEMO ROOT (the dir holding index.html),
# whatever nested .js names them — so root-relative refs like
# "screens/beatdis/beatdis.png" must resolve against that root, not the file's
# own dir (which produced the screens/beatdis/screens/beatdis doubling).
def demo_root_url(path):
    cur = os.path.abspath(os.path.dirname(path))
    while len(cur) >= len(absout):
        if os.path.exists(os.path.join(cur, 'index.html')):
            return url_of(cur)
        parent = os.path.dirname(cur)
        if parent == cur:
            break
        cur = parent
    return url_of(os.path.dirname(path))  # fallback: the file's own dir

seen = set()
for root, _, files in os.walk(out):
    low = (root + os.sep).lower()
    # skip framework dirs (melonJS etc.) — their .png strings are docs, not
    # assets — and base64/packed variants (b64/binz), whose assets are inlined
    # in the JS, so the paths they name don't exist as separate files.
    if os.sep + 'lib' + os.sep in low or 'b64' in low:
        continue
    for f in files:
        if not f.lower().endswith(scan):
            continue
        p = os.path.join(root, f)
        try:
            txt = open(p, encoding='utf-8', errors='replace').read()
        except OSError:
            continue
        file_dir_url = url_of(os.path.dirname(p))
        droot = demo_root_url(p)
        for m in pat.finditer(txt):
            ref = m.group(1)
            if ref.startswith(('http://', 'https://', '//', 'data:', '/')):
                continue
            # a path ref is root-relative; a bare filename is a sibling of the file
            u = urljoin(droot if '/' in ref else file_dir_url, ref)
            if not u.startswith(droot):   # keep within this demo's own tree
                continue
            if u not in seen:
                seen.add(u)
                print(u)
PY
n=$(grep -c . "$LIST" || true)
echo "Referenced server-local assets: $n unique URL(s)."
if [ "$n" -gt 0 ]; then
  # Pre-flight: check every candidate URL in parallel (1-byte range GET, no body
  # saved) and CIRCUIT-BREAK before downloading anything if more than $MAX_404
  # are missing — so a bad resolver run can't unleash a 404 storm.
  echo "Pre-flight: checking $n URL(s) with $JOBS workers (abort if >$MAX_404 are 404)..."
  STATUS="$(mktemp)"
  xargs -a "$LIST" -P "$JOBS" -I{} sh -c '
    code=$(curl -s -o /dev/null -w "%{http_code}" -r 0-0 --max-time 30 -A "$0" "$1")
    printf "%s %s\n" "$code" "$1"
  ' "$UA" {} >"$STATUS"
  missing=$(awk '$1=="404"{c++} END{print c+0}' "$STATUS")
  avail=$(awk '$1=="200"||$1=="206"{c++} END{print c+0}' "$STATUS")
  echo "Pre-flight result: $avail available, $missing not-found (404)."
  if [ "$missing" -gt "$MAX_404" ]; then
    echo "ABORT: $missing 404s exceeds limit ($MAX_404) — nothing downloaded."
    echo "First offending URLs:"
    awk '$1=="404"{print "  "$2}' "$STATUS" | head -20
    rm -f "$LIST" "$STATUS"
    exit 1
  fi
  # Download only the verified-present files, in parallel, no-clobber (skip
  # anything already on disk). -x --cut-dirs=3 -nH keeps the mirror's layout.
  awk '$1=="200"||$1=="206"{print $2}' "$STATUS" >"$STATUS.ok"
  echo "Fetching $avail asset(s) with $JOBS parallel workers (no-clobber)..."
  set +e
  xargs -a "$STATUS.ok" -P "$JOBS" -I{} \
    wget --no-host-directories --cut-dirs=3 --force-directories \
      --directory-prefix="$OUT" \
      --no-clobber \
      --execute robots=off \
      --retry-connrefused --tries=3 --timeout=30 \
      --user-agent="$UA" -q "{}"
  set -e
  rm -f "$STATUS" "$STATUS.ok"
fi
rm -f "$LIST"

echo
echo "=== Done. Summary of $OUT ==="
du -sh "$OUT" 2>/dev/null || true
echo "File-type counts:"
find "$OUT" -type f | sed -E 's/.*\.([A-Za-z0-9]+)$/\1/;t;s/.*/<noext>/' | tr 'A-Z' 'a-z' | sort | uniq -c | sort -rn | head -25
