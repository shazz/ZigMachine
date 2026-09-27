#!/bin/sh
# One queued gate job (see tools/gate_lib.sh): gate_job.sh <timeout-s> <queue>/<id>.<kind>
# Writes <id>.out (stdout+stderr), <id>.rc (exit status) and <id>.time
# ("<wall s> <max RSS KB>", when /usr/bin/time exists), then prints one status
# line. It never fails itself: the caller reads the .rc files, so one failed
# harness cannot stop xargs from running the rest.
limit=$1 job=$2 b=${2%.*}
tag=$(cat "$b.tag")
start=$(date +%s)
if [ -x /usr/bin/time ]; then
    /usr/bin/time -f '%e %M' -o "$b.time" timeout "$limit" sh "$job" > "$b.out" 2>&1
else
    timeout "$limit" sh "$job" > "$b.out" 2>&1
fi
rc=$?
[ "$rc" = 124 ] && echo "gate: KILLED after ${limit}s (GATE_JOB_TIMEOUT): a wedged harness" >> "$b.out"
echo "$rc" > "$b.rc"
secs=$(( $(date +%s) - start ))
if [ "$rc" = 0 ]; then st=ok; else st="FAILED (exit $rc)"; fi
printf '  %-22s %4ss  %s\n' "$tag" "$secs" "$st"
exit 0
