#!/usr/bin/env bash
set -u
cd "$(dirname "$0")"
./target/release/omaviz --seconds 12 >/dev/null 2>&1 &
P=$!
sleep 2
T0=$(awk '{print $14+$15}' /proc/$P/stat)
sleep 8
T1=$(awk '{print $14+$15}' /proc/$P/stat)
wait $P
HZ=$(getconf CLK_TCK)
awk -v a=$T0 -v b=$T1 -v hz=$HZ "BEGIN{printf \"daemon CPU over 8s: %.2f%%\\n\", (b-a)*100/hz/8}"
