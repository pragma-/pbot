FROM perl:5.34

# Install system dependencies.
RUN apt-get update && apt-get install -y libssl-dev libexpat1-dev zlib1g libdbd-sqlite3-perl cpanminus wamerican pip

# Prefer a non-root user.
RUN useradd -ms /bin/bash pbot

# Install pbot and its own dependencies (replace nitrix with pragma- eventually).
RUN cd /opt && git clone --recursive --depth=1 https://github.com/nitrix/pbot

# Perl dependencies.
RUN cpanm --local-lib=/home/pbot/perl5 local::lib && eval $(perl -I /home/pbot/perl5/lib/perl5/ -Mlocal::lib)
RUN cd /opt/pbot && cpanm -n --installdeps . --with-all-features --without-feature=compiler_vm_win32

# Translate shell.
RUN sed -i 's/^Components: main$/& contrib/' /etc/apt/sources.list.d/debian.sources
RUN apt-get update && apt-get install -y libfribidi0 libfribidi-bin gawk libsigsegv2 translate-shell

# Wiktionary parser.
RUN pip install git+https://github.com/pragma-/WiktionaryParser --break-system-packages

# Mount point to persist the bot's data.
RUN mkdir /mnt/persistent

# Just in case files are created in the working directory. 
WORKDIR /home/pbot

# Entry point, running the executable as pbot user.
USER pbot
ENTRYPOINT /opt/pbot/bin/pbot