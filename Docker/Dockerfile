# File: Dockerfile
#
# Purpose: Builds a Docker/Podman/etc image of PBot.

# SPDX-FileCopyrightText: 2024 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

# Perl image on Debian 12 bookworm
FROM perl:5.36-bookworm

# There is some initial set-up that must be done as root
USER root

# add contrib to debian.sources
RUN sed -i 's/^Components: main$/& contrib/' /etc/apt/sources.list.d/debian.sources

# Install necessary packages
RUN apt update && apt-get -y --no-install-recommends install \
    cpanminus gcc g++ libssl-dev libexpat1-dev zlib1g libdbd-sqlite3-perl \
    python3 pip

# translate-shell
RUN apt-get -y --no-install-recommends install \
    libfribidi0 libfribidi-bin gawk libsigsegv2 translate-shell

# qalculate
RUN apt-get -y install qalc \
    && qalc 1+1 \
    && sed -i \
        -e 's/save_mode_on_exit=1/save_mode_on_exit=0/' \
        -e 's/auto_update_exchange_rates=-1/auto_update_exchange_rates=1/' \
        -e 's/colorize=1/colorize=0/' \
        -e 's/abbreviate_names=1/abbreviate_names=0/' ~/.config/qalculate/qalc.cfg

# wiktionary
RUN pip install git+https://github.com/pragma-/WiktionaryParser --break-system-packages

# unicode
RUN pip install git+https://github.com/garabik/unicode --break-system-packages

# paren/prec
RUN pip install 'pycparser==2.10' --break-system-packages

# cdecl
RUN apt-get -y install cdecl

WORKDIR /opt

# Get PBot from GitHub
RUN git clone --depth=1 --recursive https://github.com/pragma-/pbot

WORKDIR /opt/pbot

# Install PBot CPAN depedencies
RUN cpanm -n --installdeps .  --with-all-features --without-feature=compiler_vm_win32

# Compile qrpn
RUN gcc -Os -march=native /opt/pbot/applets/qrpn/qrpn.c -o /opt/pbot/applets/qrpn/qrpn -lm

COPY entrypoint.sh /opt/pbot/bin/

ENTRYPOINT ["/opt/pbot/bin/entrypoint.sh"]
