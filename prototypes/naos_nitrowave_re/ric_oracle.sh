#!/bin/sh
# ric_oracle.sh DUMP N OUT -- F1 is interrupt-driven: run N VBLs (IRQ through
# the $70 vector, until its rte) on Musashi from DUMP; RAM to OUT.
cd "$(dirname "$0")"
./m68run "$1" "$3" "frames:$2:vbl:0:calls:" 2>/dev/null
