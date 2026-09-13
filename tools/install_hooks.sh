#!/bin/sh
# Turn on the repository's git hooks (.githooks/): pre-commit rebuilds docs/ when
# source is staged, pre-push runs the full ./build.sh gate. This sets
# core.hooksPath in the SHARED repository config, so it applies to every
# worktree of this clone at once.
set -e
cd "$(dirname "$0")/.."
chmod +x .githooks/* tools/prepare_pages.sh
git config core.hooksPath .githooks
echo "hooks: on (core.hooksPath = .githooks). Turn off: git config --unset core.hooksPath"
