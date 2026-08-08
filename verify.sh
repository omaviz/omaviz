#!/usr/bin/env bash
# End-to-end verification: daemon -> unix socket -> mini (waybar) client.
set -u
cd "$(dirname "$0")"
BIN=./target/release/omaviz

echo "== visuals discovered =="
$BIN visuals

echo
echo "== starting daemon =="
$BIN daemon --seconds 20 >/dev/null 2>/tmp/omaviz-daemon.log &
DPID=$!
sleep 1.5
echo "socket: $(ls -l "${XDG_RUNTIME_DIR:-/tmp}/omaviz.sock" 2>&1)"

echo
echo "== playing tone + sampling mini (waybar) output =="
speaker-test -c2 -t sine -f 440 -l 1 >/dev/null 2>&1 &
SPID=$!
sleep 1
timeout 6 $BIN mini --width 14 > /tmp/omaviz-mini.jsonl 2>&1
kill $SPID 2>/dev/null

echo "mini emitted $(wc -l < /tmp/omaviz-mini.jsonl) json lines; sample:"
tail -5 /tmp/omaviz-mini.jsonl

echo
echo "== vu variant =="
speaker-test -c2 -t sine -f 220 -l 1 >/dev/null 2>&1 &
SPID=$!
sleep 1
timeout 4 $BIN mini --width 10 --visual vu > /tmp/omaviz-vu.jsonl 2>&1
kill $SPID 2>/dev/null
tail -3 /tmp/omaviz-vu.jsonl

echo
echo "== daemon CPU while serving a client =="
T0=$(awk '{print $14+$15}' /proc/$DPID/stat 2>/dev/null || echo 0)
timeout 5 $BIN mini --width 14 >/dev/null 2>&1
T1=$(awk '{print $14+$15}' /proc/$DPID/stat 2>/dev/null || echo 0)
HZ=$(getconf CLK_TCK)
awk -v a=$T0 -v b=$T1 -v hz=$HZ 'BEGIN{printf "daemon CPU over 5s with client attached: %.2f%%\n",(b-a)*100/hz/5}'

wait $DPID 2>/dev/null
echo
echo "== daemon log =="
cat /tmp/omaviz-daemon.log
