#!/bin/bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

#host=bofh.jeffballard.us
#port=666
#grep excuse < /dev/tcp/$host/$port | sed 's/Your excuse is: //'

sort -R excuses.txt | head -n 1
