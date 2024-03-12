FROM perl:5.34

# Install system dependencies.
RUN apt-get update && apt-get install -y clang gcc clang g++ tcl ghc git cpanminus

# Need the sources.
COPY . /opt/pbot
RUN cd /opt/pbot && cpanm -n --installdeps . --with-all-features --without-feature=compiler_vm_win32

# Serial emulation.
RUN apt-get install -y socat
RUN sed -i -e "s/\/dev\/ttyS2/\/tmp\/ttyS2/g" /opt/pbot/applets/pbot-vm/guest/bin/guest-server
RUN sed -i -e "s/\/dev\/ttyS3/\/tmp\/ttyS3/g" /opt/pbot/applets/pbot-vm/guest/bin/guest-server

# Setup the guest server.
RUN cd /opt/pbot/applets/pbot-vm/guest/bin && ls -al
RUN cd /opt/pbot/applets/pbot-vm && ./guest/bin/setup-guest

# Prefer a non-root user.
RUN useradd -ms /bin/bash vm

# Just in case files are created in the working directory. 
WORKDIR /home/vm

# Single entry point for both the host and the guest.
USER vm
ENTRYPOINT ["/opt/pbot/applets/pbot-vm/entrypoint.sh"]