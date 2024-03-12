FROM perl:5.34

# Install system dependencies.
RUN apt-get update && apt-get install -y clang gcc clang g++ tcl ghc git cpanminus dos2unix policykit-1 fortune-mod astyle

# Need the sources.
COPY . /opt/pbot
RUN cd /opt/pbot && cpanm -n --installdeps . --with-all-features --without-feature=compiler_vm_win32

# Serial emulation.
RUN apt-get install -y socat
RUN sed -i -e "s/\/dev\/ttyS2/\/tmp\/ttyS2/g" /opt/pbot/applets/pbot-vm/guest/bin/guest-server
RUN sed -i -e "s/\/dev\/ttyS3/\/tmp\/ttyS3/g" /opt/pbot/applets/pbot-vm/guest/bin/guest-server

# Line endings on other platforms.
RUN find . -type f -print0 | xargs -0 dos2unix /opt/pbot/applets/pbot-vm/guest/bin/*
RUN find . -type f -print0 | xargs -0 dos2unix /opt/pbot/applets/pbot-vm/host/bin/*
RUN dos2unix /opt/pbot/applets/pbot-vm/entrypoint.sh
RUN chmod +x /opt/pbot/applets/pbot-vm/guest/bin/*
RUN chmod +x /opt/pbot/applets/pbot-vm/host/bin/*
RUN chmod +x /opt/pbot/applets/pbot-vm/entrypoint.sh

# Different location for Policykit
RUN sed -i -e "s/\/etc\/polkit-1\/rules.d\//\/usr\/share\/polkit-1\/rules.d\//g" /opt/pbot/applets/pbot-vm/guest/bin/setup-guest

# Give well-known host as CID.
RUN sed -i -e "s/\"cid\" : 7,/\"cid\" : 2,/g" /opt/pbot/applets/pbot-vm/host/config/vm-exec.json

# Permissions on some folders.
RUN chmod 777 /opt/pbot/applets/pbot-vm/host/history
RUN chmod 777 /opt/pbot/applets/pbot-vm/host/bin
RUN touch /opt/pbot/applets/pbot-vm/host/log.txt
RUN chmod 666 /opt/pbot/applets/pbot-vm/host/log.txt

# Fortunes
RUN ln -s /usr/games/fortune /usr/bin/fortune

# Setup the guest.
RUN cd /opt/pbot/applets/pbot-vm && ./guest/bin/setup-guest

# Prefer a non-root user.
RUN useradd -ms /bin/bash vm

# Just in case files are created in the working directory. 
WORKDIR /home/vm

# Single entry point for both the host and the guest.
USER vm
ENTRYPOINT ["/opt/pbot/applets/pbot-vm/entrypoint.sh"]