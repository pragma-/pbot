#!/bin/bash

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

#host=bofh.jeffballard.us
#port=666
#grep excuse < /dev/tcp/$host/$port | sed 's/Your excuse is: //'

sort -R excuses.txt | head -n 1
