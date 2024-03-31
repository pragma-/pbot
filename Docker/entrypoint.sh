#!/bin/bash

# File: entrypoint.sh
# Purpose: Docker/Podman/etc entry-point. Ensures user has mounted data, etc.

# SPDX-FileCopyrightText: 2001-2023 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

if ! mountpoint -q /opt/pbot/persist-data; then
    cat <<EOF
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
You did not specify a location on the host machine
to store your data. This means NOTHING will persist
if this docker container is deleted or updated, such
as factoids, message history, users, bans, etc.

In other words, you will LOSE YOUR DATA!

Run the container with the -v option:

docker ... -v /path/to/your/data/:/opt/pbot/persist-data
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
EOF
    exit 1
fi

cd /opt/pbot/
exec bin/pbot data_dir=persist-data "$@"
