#!/bin/sh
# The green stamp: a list of source trees that passed the FULL gate, so the
# pre-push hook never gates the same bytes twice.
#
#   tools/gate_stamp.sh clean          exit 0 when the working tree is clean
#   tools/gate_stamp.sh env            the toolchain key a stamp is valid for
#   tools/gate_stamp.sh check <tree>   exit 0 when <tree> is stamped for this env
#   tools/gate_stamp.sh write          stamp HEAD's tree (refuses a dirty tree)
#
# A stamp is `<tree> <env> <date> <commit>`, one per line, in the git COMMON dir
# (.git/zm-gate-green): per clone, shared by its worktrees, never committed. It
# is keyed by the TREE hash, not the commit: a rebase or a merge commit that
# lands on the same bytes is the same tree, and the gate only ever saw bytes.
#
# "Clean" is no tracked change anywhere AND no untracked (non-ignored) file under
# the build's input dirs: an untracked scene the build compiles would make the
# gate pass on bytes that are not in the tree being stamped.
#
# The env key: zig and node versions, and whether prototypes/ exists (here and
# in the main checkout, which worktrees fall back to). That dir is gitignored,
# and some harnesses check more when it is there (they SKIP without it), so a
# stamp made without it must not excuse a checkout that has it. Its CONTENTS are
# not keyed: they are reference material, not the pushed bytes.
set -e
cd "$(git rev-parse --show-toplevel)"

stamps() { echo "$(git rev-parse --path-format=absolute --git-common-dir)/zm-gate-green"; }

env_key() {
    { zig version 2>&1 || echo "no zig"
      node --version 2>&1 || echo "no node"
      # harnesses read ./prototypes or, from a worktree, the main checkout's
      main=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
      for p in prototypes "$main/prototypes"; do
          if [ -d "$p" ]; then echo "$p: yes"; else echo "$p: no"; fi
      done
    } | sha256sum | cut -c1-16
}

# The dirs the build and the harnesses read. An untracked file elsewhere (a note
# at the root) cannot change what the gate sees; one in here can.
INPUTS="apps libs rom machine tools docs .githooks build.zig build.sh"

is_clean() {
    [ -z "$(git status --porcelain --untracked-files=no)" ] &&
    [ -z "$(git ls-files -o --exclude-standard -- $INPUTS)" ]
}

case "${1:-}" in
    clean) is_clean ;;
    env) env_key ;;
    check)
        [ -n "${2:-}" ] || { echo "gate_stamp.sh check <tree>" >&2; exit 2; }
        f=$(stamps)
        [ -f "$f" ] && grep -q "^$2 $(env_key) " "$f" ;;
    write)
        is_clean || { echo "gate_stamp: dirty working tree, NOT stamped" >&2; exit 1; }
        tree=$(git rev-parse 'HEAD^{tree}')
        f=$(stamps)
        line="$tree $(env_key) $(date -u +%Y-%m-%dT%H:%M:%SZ) $(git rev-parse HEAD)"
        # keep the newest 200: the list is only ever searched by tree
        { [ -f "$f" ] && grep -v "^$tree $(env_key) " "$f" | tail -199; echo "$line"; } > "$f.tmp"
        mv "$f.tmp" "$f"
        echo "gate_stamp: tree $tree is green" ;;
    *) echo "usage: gate_stamp.sh clean|env|check <tree>|write" >&2; exit 2 ;;
esac
