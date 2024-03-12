FROM perl:5.34

# Install major dependencies.
RUN apt-get update && apt-get install -y libssl-dev libexpat1-dev zlib1g libdbd-sqlite3-perl cpanminus wamerican pip
# Enable contrib packages.
RUN apt-get install -y software-properties-common && apt-add-repository contrib && apt-get update
# Translate shell.
RUN apt-get install -y libfribidi0 libfribidi-bin gawk libsigsegv2 translate-shell

# Prefer a non-root user.
RUN useradd -ms /bin/bash pbot

# Location for perl libraries.
RUN su pbot && cpanm --local-lib=/home/pbot/perl5 local::lib && eval $(perl -I /home/pbot/perl5/lib/perl5/ -Mlocal::lib)

# Install pbot from sources and get dependencies.
COPY . /opt/pbot
RUN cd /opt/pbot && cpanm -n --installdeps . --with-all-features --without-feature=compiler_vm_win32

# Wiktionary parser.
RUN pip install git+https://github.com/pragma-/WiktionaryParser

# Mount point to persist the bot's data.
RUN mkdir /mnt/persistent

# Just in case files are created in the working directory. 
WORKDIR /home/pbot

# Entry point, running the executable as pbot user.
USER pbot
ENTRYPOINT /opt/pbot/bin/pbot