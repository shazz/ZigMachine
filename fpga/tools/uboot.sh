#!/bin/bash
# uboot.sh "cmd1" "cmd2" ... : send each U-Boot command at 921600, print the console reply.
P=${UBOOT_TTY:-$(readlink -f /dev/serial/by-id/*1a86* | head -1)}; OUT=$(mktemp)
stty -F $P 921600 raw -echo cs8 -cstopb -parenb -crtscts -ixon
timeout ${WAIT:-4} cat $P > $OUT & sleep 0.2
for c in "$@"; do printf '%s\r' "$c" > $P; sleep ${GAP:-0.6}; done
wait; tr -d '\r' < $OUT; rm -f $OUT
