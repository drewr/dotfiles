#!/bin/sh
# s6 service definition for the spike. s6-supervise runs this; it should stay in
# the foreground forever so s6 can supervise it.
echo "[echo-svc] starting: pid=$$"
i=0
while :; do
  echo "[echo-svc] tick $i pid=$$"
  i=$((i + 1))
  sleep 2
done
