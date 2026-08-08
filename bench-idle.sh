#!/usr/bin/env bash
# Measures the daemon's idle cost (no clients attached, no audio).
set -u
P=$(pgrep -f "omaviz daemon" | head -1)
if [ -z "$P" ]; then echo "no daemon running"; exit 1; fi
HZ=$(getconf CLK_TCK)
T0=$(awk '{print $14+$15}' /proc/$P/stat)
sleep 8
T1=$(awk '{print $14+$15}' /proc/$P/stat)
awk -v a=$T0 -v b=$T1 -v hz=$HZ 'BEGIN{printf "idle daemon CPU over 8s: %.2f%%\n",(b-a)*100/hz/8}'
awk '{printf "daemon RSS: %.1f MB\n",$1/1024}' /proc/$P/statm 2>/dev/null || \
  ps -o rss= -p $P | awk '{printf "daemon RSS: %.1f MB\n",$1/1024}'
