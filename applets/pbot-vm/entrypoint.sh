#!/bin/bash

# socat -d -d pty,raw,link=/tmp/ttyS2,echo=0 pty,raw,link=/tmp/ttyS2x,echo=0 &
# socat -d -d pty,raw,link=/tmp/ttyS3,echo=0 pty,raw,link=/tmp/ttyS3x,echo=0 &

cd /opt/pbot/applets/pbot-vm/guest/bin && ./guest-server &
cd /opt/pbot/applets/pbot-vm/host/bin && ./docker-server