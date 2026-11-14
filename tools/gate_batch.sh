#!/bin/sh
# gate_batch.sh: land every ready branch with ONE gate (Matt, 13 Nov: "at each unlock, check for merge /
# install, if queue, do it before locking again").
#
# Why: each branch used to run its own full gate + push (~20 min each, one at a time), so four ready
# branches cost ~80 min of lock and kept re-merging main. Here the lead merges the whole queue into one
# integration branch, gates it once (a clean full gate stamps the tree green, so the push is instant),
# pushes, then installs the board files once.
#
# The queue: prototypes/_gate_logs/merge_queue.txt, one ready branch a line ("<branch> <note>").
# Agents append their branch there when their `--only <tag>` gate is green, instead of running a full
# gate or pushing. Lines starting with # are ignored.
#
#   tools/gate_batch.sh list                     the queue, with each branch's head and commits ahead of main
#   tools/gate_batch.sh merge <name>             worktree ../ZigMachine-<name> from origin/main + every queued branch
#   tools/gate_batch.sh gate  <name>             full gate there under build.lock, then push to main if green
#
# A merge conflict stops the merge step and names the branch: resolve it in the worktree, commit, re-run.
set -eu
REPO=$(cd "$(dirname "$0")/.." && pwd)
MAIN=/home/matt/projects/ZigMachine
LOCK=$MAIN/prototypes/_gate_logs/build.lock
QUEUE=$MAIN/prototypes/_gate_logs/merge_queue.txt

branches() { [ -f "$QUEUE" ] && grep -v '^\s*#' "$QUEUE" | awk 'NF {print $1}' || true; }

cmd=${1:-list}
case $cmd in
list)
    git -C "$REPO" fetch -q origin
    for b in $(branches); do
        printf '%-32s %s ahead=%s\n' "$b" "$(git -C "$REPO" rev-parse --short "$b" 2>/dev/null || echo MISSING)" \
            "$(git -C "$REPO" rev-list --count "origin/main..$b" 2>/dev/null || echo ?)"
    done ;;
merge)
    name=${2:?name}; wt=$(dirname "$MAIN")/ZigMachine-$name
    git -C "$REPO" fetch -q origin
    git -C "$REPO" worktree add -q -b "integrate/$name" "$wt" origin/main
    ln -s "$MAIN/fpga/.tools" "$wt/fpga/.tools"   # untracked: wasm2c harnesses need it
    for b in $(branches); do
        echo "== merge $b"
        git -C "$wt" merge --no-edit "$b" || { echo "CONFLICT in $b: resolve in $wt, commit, then continue"; exit 1; }
    done
    echo "merged $(branches | wc -l) branches into integrate/$name ($wt)" ;;
gate)
    name=${2:?name}; wt=$(dirname "$MAIN")/ZigMachine-$name
    log=$MAIN/prototypes/_gate_logs/integrate-$name.log
    # Rebuild docs/ first (no lock: --fast) and commit it, so the full gate runs on a tree whose docs/
    # are already current and stamps THAT tree green: the push after it is then instant.
    (cd "$wt" && ./build.sh --fast > "$log.fast" 2>&1)
    fast=$(git -C "$wt" status --porcelain | awk '$1 != "??" {print $2}' | grep '^docs/' || true)
    [ -z "$fast" ] || { git -C "$wt" add $fast; git -C "$wt" commit -q -m "docs: carts rebuilt for the integration ($name)"; }
    flock "$LOCK" sh -c "cd '$wt' && ./build.sh > '$log' 2>&1"
    tail -3 "$log"
    # The gate may rebuild docs/ (carts, the ROM): those are the merged tree's real outputs.
    changed=$(git -C "$wt" status --porcelain | awk '$1 != "??" {print $2}' | grep '^docs/' || true)
    if [ -n "$changed" ]; then
        git -C "$wt" add $changed
        git -C "$wt" commit -q -m "docs: carts and ROM rebuilt by the integration gate ($name)"
    fi
    flock "$LOCK" git -C "$wt" push origin "HEAD:main"
    echo "pushed integrate/$name; now clear $QUEUE and install the board files once" ;;
*) echo "usage: $0 list | merge <name> | gate <name>" >&2; exit 2 ;;
esac
