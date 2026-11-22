#!/bin/sh
# The repository reorganisation (Matt, 13 Nov 2026), as four committed phases:
#
#   1. phase1_docs.py        docs/*.md, BUGS/PORTS/decisions.md, fpga/review + bench_results
#                            -> docs/guide, hardware(/studies), os, project; stubs at the old .md paths
#   2. phase2_harness.py     apps/*.mjs (+ fixtures, perf/) -> apps/harness/
#   3. phase3_site.py        the website, chips, carts, disks, music -> site/ (js/, carts/, disks/...)
#   4. phase4_prototypes.py  prototypes/*/ANALYSIS.md -> docs/ports/<tag>/, prototypes/ untracked
#
# Each phase reads a reviewed table (<phase>.tsv: what moves where, what is rewritten), applies
# hand patches (<phase>.patch: the references no table can see), rewrites every reference in
# every tracked text file (rewrite.py: relative links first, then repo-rooted paths, longest
# first, whole paths only), regenerates what is generated from the moved files, verifies that
# no old path is left (rewrite.py --verify) and commits. A phase refuses a dirty tree, says
# "already applied" when run twice, and prints everything it would do with --dry-run.
#
# WHEN: with no feature branch open (every open branch would conflict on every moved file).
# BEFORE phase 3 lands on main: switch GitHub Pages to the Actions source and enable
# .github/workflows/pages.yml (its header says how), or the live site goes dark.
#
#   tools/reorg/run_all.sh --dry-run       # every git mv and rewrite of phase 1 (later phases
#                                          # depend on it, so a dry run stops after phase 1)
#   tools/reorg/run_all.sh [--also]        # all four phases, four (+1 stub) commits
#   then: zig build && ./build.sh (the full gate) before pushing.
#
# --also rewrites the git-ignored local instructions too (.claude/ skills, agents, commands,
# hooks; tools/private_tools/): never committed. Run it in the main checkout.
set -e
cd "$(dirname "$0")/../.."
if [ "$(git rev-parse --abbrev-ref HEAD)" = main ]; then
    echo "reorg: on main. Run it on a branch (git switch -c chore/repo-reorg-run), gate, then merge."
    exit 1
fi
# Phases 2-4 build on the commits of the ones before, so only phase 1 has a real dry run here;
# to see all four, run them on a throwaway clone (git clone --shared . /tmp/x) as the trial did.
if [ "$1" = "--dry-run" ]; then
    exec python3 -I tools/reorg/phase1_docs.py --dry-run
fi
python3 -I tools/reorg/phase1_docs.py "$@"
python3 -I tools/reorg/phase2_harness.py "$@"
python3 -I tools/reorg/phase3_site.py "$@"
# Phase 4 lists every tracked file that names a prototypes/ file and STOPS on code ones: review
# that list, then REORG_ACCEPT_REFS=1 tools/reorg/run_all.sh (phases 1-3 say "already applied").
python3 -I tools/reorg/phase4_prototypes.py ${REORG_ACCEPT_REFS:+--accept-refs} "$@"
python3 -I tools/reorg/rewrite.py --verify tools/reorg/phase1_docs.tsv tools/reorg/phase2_harness.tsv \
    tools/reorg/phase3_site.tsv tools/reorg/phase4_prototypes.tsv
