# Sourced by build.sh: the gate's job queue. POSIX sh (the hook runs `sh build.sh`).
#
#   gate <tag> <cmd...>        a screen harness: queued, runs in the parallel pool
#   gate_timed <tag> <cmd...>  a harness that asserts WALL-CLOCK time (ms a frame,
#                              a 60 fps budget): queued, runs ALONE after the pool,
#                              so our own parallelism can never fail it. Never
#                              loosen its threshold to let it into the pool.
#   always <tag> <cmd...>      queued in the pool whatever the selection
#   early <tag> <cmd...>       a slow cross-cutting check started NOW, in the
#                              background, so it overlaps the native tests and
#                              the disk repack; run_gates waits for it
#   run_gates                  run the queue; exit 1 if any job failed
#
# Selection: SELECT_EXACT (from --changed / the hook: exact gate tags) or ONLY
# (from --only: substring, over-inclusive on purpose). Neither set = everything.
#
# Output stays readable: the pool prints one line per job as it finishes, then
# every job's full output IN QUEUE ORDER under its tag, then the serial jobs
# stream as before. A failure is re-printed (tail) at the very end.
#
# GATE_JOBS (default: half the cores, max 6) bounds the pool: docs/BUILDING.md
# has the RAM and time measurements behind it. GATE_JOBS=1 is the old serial gate.
# GATE_JOB_TIMEOUT (seconds, default 1800) kills a wedged harness: a hang must
# fail the gate loudly, not stall a push for ever.

# Default: half the cores, at most 6 (4 on the 8-core box). Every harness peaks
# under 320 MB RSS, so the bound is CPU, shared with whatever else is running.
_cores=$(nproc 2>/dev/null || echo 2)
_half=$((_cores / 2)); [ "$_half" -ge 1 ] || _half=1; [ "$_half" -le 6 ] || _half=6
GATE_JOBS=${GATE_JOBS:-$_half}
GATE_JOB_TIMEOUT=${GATE_JOB_TIMEOUT:-1800}
GATE_Q=$(mktemp -d)
_gate_n=0

_selected() { # <tag>
    if [ -n "${SELECT_EXACT+x}" ]; then
        for _s in $SELECT_EXACT; do [ "$_s" = "$1" ] && return 0; done
        return 1
    fi
    [ -z "$ONLY" ] && return 0
    for _s in $ONLY; do case "$1" in *"$_s"*) return 0 ;; esac; done
    return 1
}

_enqueue() { # <kind> <tag> <cmd...>
    _kind=$1 _tag=$2; shift 2
    _gate_n=$((_gate_n + 1))
    _id=$(printf '%03d' "$_gate_n")
    printf '%s\n' "$_tag" > "$GATE_Q/$_id.tag"
    printf 'exec ' > "$GATE_Q/$_id.cmd" # exec: the job IS the harness, so a timeout kills it
    for _a in "$@"; do
        printf "'%s' " "$(printf '%s' "$_a" | sed "s/'/'\\\\''/g")" >> "$GATE_Q/$_id.cmd"
    done
    mv "$GATE_Q/$_id.cmd" "$GATE_Q/$_id.$_kind"
}

gate() { _t=$1; _selected "$_t" && _enqueue pool "$@"; return 0; }
gate_timed() { _t=$1; _selected "$_t" && _enqueue timed "$@"; return 0; }
always() { _enqueue pool "$@"; }
early() {
    _enqueue early "$@"
    sh tools/gate_job.sh "$GATE_JOB_TIMEOUT" "$GATE_Q/$_id.early" > "$GATE_Q/$_id.status" &
    _early_pids="$_early_pids $!"
    # If the gate dies before run_gates (a failed native test), do not leave
    # the check running on its own: the gate lock is held until it ends.
    # `|| true`: under set -e a failing wait (pids already reaped by run_gates)
    # would otherwise BECOME the gate's exit status, 127 on a green gate.
    trap 'wait $_early_pids 2>/dev/null || true' EXIT
}

_wait_early() {
    [ -n "$_early_pids" ] || return 0
    wait $_early_pids || true
    for _j in $(ls "$GATE_Q"/*.early); do
        _b=${_j%.early}
        cat "$_b.status"
        echo "=== [$(cat "$_b.tag")] (started early) $(cat "$_j")"
        cat "$_b.out"
    done
}

_run_pool() {
    _jobs=$(ls "$GATE_Q"/*.pool 2>/dev/null || true)
    [ -z "$_jobs" ] && return 0
    echo "gate: $(echo "$_jobs" | wc -l) harness jobs, $GATE_JOBS at a time"
    printf '%s\n' "$_jobs" | xargs -P "$GATE_JOBS" -n 1 \
        sh tools/gate_job.sh "$GATE_JOB_TIMEOUT" || true
    for _j in $_jobs; do
        _b=${_j%.pool}
        echo "=== [$(cat "$_b.tag")] $(cat "$_j")"
        cat "$_b.out"
    done
}

_run_timed() {
    for _j in $(ls "$GATE_Q"/*.timed 2>/dev/null || true); do
        _b=${_j%.timed}
        echo "=== [$(cat "$_b.tag")] (alone: wall-clock budget) $(cat "$_j")"
        sh tools/gate_job.sh "$GATE_JOB_TIMEOUT" "$_j" > /dev/null
        cat "$_b.out"
    done
}

run_gates() {
    _run_pool
    _wait_early
    _run_timed
    _failed=""
    # Scan the JOBS, not the .rc files: a job that never wrote one never ran,
    # and that is a failure, not a pass.
    for _j in $(ls "$GATE_Q"/*.pool "$GATE_Q"/*.timed "$GATE_Q"/*.early 2>/dev/null || true); do
        _b=${_j%.*}
        [ "$(cat "$_b.rc" 2>/dev/null)" = 0 ] || _failed="$_failed $_b"
    done
    if [ -z "$_failed" ]; then
        echo "gate: all $_gate_n harness jobs passed"
        rm -rf "$GATE_Q"
        return 0
    fi
    for _b in $_failed; do
        echo "=== FAILED [$(cat "$_b.tag")] exit $(cat "$_b.rc" 2>/dev/null || echo "none: never ran"): $(cat "$_b.pool" "$_b.timed" "$_b.early" 2>/dev/null)"
        tail -40 "$_b.out" 2>/dev/null
    done
    echo "gate: FAILED ❌ $(for _b in $_failed; do cat "$_b.tag"; done | tr '\n' ' ')"
    echo "gate: every job's output is kept in $GATE_Q"
    return 1
}
