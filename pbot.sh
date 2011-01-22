#!/bin/sh

mv log/log log/log-`date +%Y%m%d-%H:%M.%N` &> /dev/null
mv log/stderr_log log/stderr_log-`date +%Y%m%d-%H:%M.%N` &> /dev/null

perl pbot.pl 2> log/stderr_log
cat log/stderr_log
