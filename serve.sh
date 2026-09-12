#!/bin/sh
# Serve docs/ for development. See tools/serve.py for what it does and why
# (no-store caching, and a refusal to start on a port that is already serving).
#
# Usage: ./serve.sh [port]     default 3333; use one port per worktree.
cd "$(dirname "$0")/docs" || exit 1
exec python3 ../tools/serve.py "$@"
