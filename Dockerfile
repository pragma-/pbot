FROM perl:5.34

# Install system dependencies.
RUN apt-get update && apt-get install -y make gcc clang cpanminus dos2unix wamerican

# Install pbot and its own dependencies.
# FIXME: Replace nitrix with pragma-.
RUN cd /opt && git clone --recursive https://github.com/nitrix/pbot
RUN cd /opt/pbot && cpanm -n --installdeps . --with-all-features --without-feature=compiler_vm_win32

# Mount point for to persist the bot's data.
RUN mkdir /mnt/persistent

# Just in case files are created in the working directory. 
WORKDIR /tmp

# Executable.
ENTRYPOINT /opt/pbot/bin/pbot
