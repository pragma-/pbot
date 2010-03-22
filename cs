#!/bin/sh

rm stderr_log log 2>/dev/null
./fpb
cat stderr_log
