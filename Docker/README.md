# Docker instructions

### Install Docker

Install docker:

    zypper install docker docker-compose docker-compose-switch

If not using openSUSE, replace `zypper` with appropriate package manager, e.g. `apt`, `yum`, `dnf`, `apk`, etc.

To start docker daemon during boot:

    sudo systemctl enable docker

Restart docker daemon:

    sudo systemctl restart docker

Verify docker is running:

    docker version

Join docker group:

    sudo usermod -G docker -a $USER

Log in to the docker group:

    newgrp docker

If the above does not work, e.g. because you are in a tmux session, you can `su $USER` instead.

### Build image and configure PBot

Build image:

    docker build . -t pbot

Copy data directory. The `$DATA_DIR` should be a unique name identifying the purpose of the bot, i.e. its name or the IRC server.

    copy -r ../data $DATA_DIR

I like to use `<server>-<nick>` when naming my data directories. For example:

    copy -r ../data ircnet-candide
    copy -r ../data libera-candide
    copy -r ../data libera-cantest

Create and start a new container the for the first time with options configuring the botnick and IRC server. We will use the `-ti`
flags for `docker run` so we can access PBot's terminal console to run commands like `useradd` to create
your bot-admin account, etc.

See [Configuration](../doc/QuickStart.md#configuration) in the [QuickStart guide](../doc/QuickStart.md) for
more information about the available configuration options.

`$DATA_DIR` here must be the full path, i.e. `$HOME/pbot/Docker/libera-candide`.

    docker run --name pbot -ti -v $DATA_DIR:/opt/pbot/persist-data pbot irc.botnick=$NICK irc.server=$SERVER irc.port=$PORT

For example, to connect securely via TLS to irc.libera.chat with botnick `coolbot`:

    docker run --name pbot -ti -v $DATA_DIR:/opt/pbot/persist-data pbot irc.botnick=coolbot irc.server=irc.libera.chat irc.port=6697 irc.tls=1

Follow the steps in [Additional configuration](../doc/QuickStart.md#additional-configuration) in the [QuickStart guide](../doc/QuickStart.md)
to create your bot-admin account, add channels, etc.

To shutdown the bot, press `^C` (ctrl-c) or enter `die` into the PBot terminal console.

### Running PBot

To start the bot again in the future:

    docker start pbot

This will start the bot in the background. You can reattach to its PBot terminal console with:

    docker attach --detach-keys="ctrl-x" pbot

Press `^X` (ctrl-x) to detach or `^C` (ctrl-c) to shutdown the bot.

### Further Reading

See [Further Reading](../doc/QuickStart.md#further-reading) in the [QuickStart guide](../doc/QuickStart.md) for additional information.
