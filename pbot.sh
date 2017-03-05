#!/bin/sh
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

mv log/log log/log-`date +%Y%m%d-%H:%M.%N` 2> /dev/null
perl pbot.pl 2>> log/log
