# QuickStart

<!-- md-toc-begin -->
* [Installation](#installation)
  * [Installing Perl](#installing-perl)
  * [Installing CPAN modules](#installing-cpan-modules)
    * [re::engine::RE2](#reenginere2)
  * [Installing PBot](#installing-pbot)
    * [git (recommended)](#git-recommended)
    * [Download zip archive](#download-zip-archive)
* [Initial Setup](#initial-setup)
  * [Clone data-directory](#clone-data-directory)
  * [Configuration](#configuration)
    * [Recommended settings for IRC Networks](#recommended-settings-for-irc-networks)
      * [Libera.Chat](#liberachat)
      * [IRCnet](#ircnet)
      * [Other networks](#other-networks)
* [Starting PBot](#starting-pbot)
  * [Usage](#usage)
    * [rlwrap](#rlwrap)
    * [Overriding directories](#overriding-directories)
    * [Overriding registry](#overriding-registry)
  * [First-time start-up](#first-time-start-up)
    * [Using default settings](#using-default-settings)
    * [Using custom settings](#using-custom-settings)
      * [Custom recommended settings](#custom-recommended-settings)
      * [Custom recommended IRCnet/other network settings](#custom-recommended-ircnetother-network-settings)
  * [Regular start-up](#regular-start-up)
* [Additional configuration](#additional-configuration)
  * [Creating your bot owner admin account](#creating-your-bot-owner-admin-account)
  * [Adding other users and admins](#adding-other-users-and-admins)
  * [Adding channels](#adding-channels)
* [Further Reading](#further-reading)
  * [Commands](#commands)
  * [Factoids](#factoids)
  * [Plugins](#plugins)
  * [Modules](#modules)
<!-- md-toc-end -->

## Installation

### Installing Perl
PBot uses the [Perl programming language](https://www.perl.org/). Perl is usually
part of a base Linux install. If you do not have Perl installed, please see your
system's documentation to install it.

### Installing CPAN modules
Some of PBot's features depend on the availability of Perl modules written by
third parties. To use such PBot features, the modules listed in the [`MODULES`](../MODULES)
file need to be installed.

The modules may be installed with a simple command:

    $ cpan -f -i $(cat MODULES)

Some CPAN modules may fail to pass certain tests due to outdated variables.
Despite these test failures, their core functionality should still work as
expected.

#### re::engine::RE2
PBot uses the `re::engine::RE2` module for its regular expressions. This engine is safer
for user-submitted regular expressions.

If you could not install it through CPAN, you must install it manually.

* https://github.com/google/re2
* https://github.com/dgl/re-engine-RE2/

### Installing PBot

#### git (recommended)
The recommended way to install PBot is with `git`.  This will allow you easily update to
the latest version of PBot via the git update process by issuing the `git pull` command.
Also, if you become interested in contributing improvements to PBot, you will be able to
submit them through `git`.

The command to install with `git` is:

    $ git clone https://github.com/pragma-/pbot.git

#### Download zip archive
Alternatively, you may [download a ZIP archive](https://github.com/pragma-/pbot/archive/master.zip).

## Initial Setup
After git-cloning (or unpacking the ZIP archive) you should have a directory named
`pbot/` (or `pbot-master/`). It should contain at least these directories and files:

Name | Description
--- | ---
[`PBot/`](https://github.com/pragma-/pbot/tree/master/PBot) | PBot source tree
[`Plugins/`](https://github.com/pragma-/pbot/tree/master/Plugins) | Dynamically loadable internal plugins
[`modules/`](https://github.com/pragma-/pbot/tree/master/modules) | External command-line executables invokable as PBot commands
[`data/`](https://github.com/pragma-/pbot/tree/master/data) | Default data-directory
[`doc/`](https://github.com/pragma-/pbot/tree/master/doc) | Helpful documentation
[`pbot`](https://github.com/pragma-/pbot/blob/master/pbot) | executable used to launch PBot

You may create a symbolic link to the `pbot` executable in `$HOME/bin/` or even
in `/usr/local/bin/`.

### Clone data-directory
PBot uses a data-directory to store all its configuration settings and data. You must
clone this data-directory for each instance of PBot you want to run, otherwise they
will become quite confused with each other and things will break horribly.

Even if you're using just one instance of PBot it is still strongly recommended to clone
the default data-directory, especially if you used `git` to install PBot.

Here we clone the data-directory for two PBot instances, naming them after the
IRC network they will connect to:

    $ cd pbot (or pbot-master)
    $ cp -r data libera
    $ cp -r data ircnet

Alternatively, you could name your new data directory after your bot's nickname:

    $ cp -r data coolbot

### Configuration
PBot configuration is stored in a registry of key/value pairs grouped by sections.
For more information, see the [Registry documentation](Registry.md).

For initial first-time setup, you may configure registry settings via the PBot
command-line options. We'll show you [how to do that](#starting-pbot) soon! First, read on to
see what settings you should configure.

Alternatively, you can edit the `registry` file in your cloned data-directory.
See [editing registry file](Registry.md#editing-registry-file) for more
information.

Here is a table of basic initial settings you should configure:

Registry key | Description | Default value
--- | --- | ---:
irc.botnick | IRC nickname. This is the name people see when you talk. _Required._ | _undefined_
irc.username | IRC username. This is the `USER` field of your hostmask. | pbot3
irc.realname | IRC gecos/realname. This is the `general information` or `real-name` field, as seen in `WHOIS`. | https://github.com/pragma-/pbot
irc.server | IRC server address to connect. | irc.libera.chat
irc.port | IRC server port. | 6667 (secure port: 6697)
irc.identify_password | Password to authenticate with services or bots. | _undefined_
irc.sasl | Whether to use the IRCv3 SASL authentication mechanism. | 0 (1 to enable)
irc.tls | Whether to use TLS encryption. | 0 (1 to enable)
general.trigger | Bot trigger. Can be a character class containing multiple trigger characters. Can be overridden per-channel. | [!]

For a list of other available settings see [this table](Registry.md#list-of-known-registry-items) in the [Registry documentation](Registry.md).

#### Recommended settings for IRC Networks

##### Libera.Chat
The default settings are tailored for an insecure connection to the Libera.Chat IRC network.
To make the connection secure, set `irc.tls` to `1`. This will enable TLS encryption.
You may optionally set `irc.tls_ca_path` or `irc.tls_ca_file` if necessary. Be sure to
set `irc.port` to `6697` for the secure port.

It is strongly recommended that you register an account with NickServ and to enable SASL authentication.
Register your channels with ChanServ. You may request a host cloak from Libera staff. This will protect
your nickname, channels and IP address.

Once you register with NickServ, it is strongly recommended to enable `irc.sasl`. If you
choose not to use IRCv3 SASL authentication, then it is recommended to set these options:

<details><summary>Click to show recommended Libera.Chat settings with SASL disabled</summary>

Registry key | Description | Recommended value
--- | --- | ---:
irc.identify_password | Password to use to identify to NickServ | `<password>`
irc.randomize_nick | Randomize IRC nickname when connecting to server. PBot will change to `irc.botnick` when logged-in. This prevents users from monitoring the botnick to catch its IP address before it is identified. | 1
general.autojoin_wait_for_nickserv | Wait for NickServ login before auto-joining channels. This prevents PBot from joining channels before it is identified and cloaked. | 1
general.identify_command | Command to send to NickServ to identify. `$nick` will be replaced with `irc.botnick`; `$password` will be replaced with `irc.identify_password`. If you wish to login to a NickServ account different than the `irc.botnick` you may replace the `$nick` text with a literal value. | `identify $nick $password`

</details>

##### IRCnet
IRCnet is one of the oldest IRC networks still running. It has no Services like NickServ and ChanServ.
Instead, its nicknames and channels are protected by custom bots.

These settings may be useful:

<details><summary>Click to show recommended IRCnet settings</summary>

Registry key | Description | Default value| Recommended value
--- | --- | ---: | ---:
general.identify_nick | Who to /msg for login/identify/authentication. Defaults to NickServ, can be overridden to a custom bot. | NickServ | `<service botnick>`
general.identify_command | Command to send to `general.identify_nick` to login. | `identify $nick $password` | `<service bot command>`
general.op_nick | Who to /msg to request channel OP status. Defaults to ChanServ, can be overridden to a custom bot. | ChanServ | `<service botnick>`
general.op_command | Command to send to `general.op_nick` to request channel OP status. | `op $channel` | `<service bot command>`

</details>

##### Other networks
Other networks are untested. They should be very similiar to either Libera.Chat or IRCnet, and so one or both of the
recommended settings should suffice. If you have any issues, please [report them here](https://github.com/pragma-/pbot/issues)
or by sending `pragma-` a message on the Libera.Chat network.

## Starting PBot

### Usage
    $ pbot [directory overrides...] [registry overrides...]

#### rlwrap
It is recommended to use the `rlwrap` program for command-line history if you use
the PBot STDIN interface.

    $ rlwrap pbot [...]

#### Overriding directories
You may override PBot's default directory locations via the command-line.

    $ pbot data_dir=/path/to/data plugin_dir=/path/to/Plugins modules_dir=/path/to/modules

#### Overriding registry
You may override any of your Registry values via the command-line. Any overrides made will be
saved to the `registry` file. You do not need to use the override every time you launch PBot.

    $ pbot irc.botnick=coolbot irc.server=irc.example.com irc.port=6667 [...]

### First-time start-up

#### Using default settings
The default settings will connect to the Libera.Chat IRC network.

At minimum, the registry key `irc.botnick` must be set before PBot will connect to any IRC servers.

The following command will use the `coolbot` data-directory that we cloned in the [initial setup](#initial-setup),
and set the `irc.botnick` registry key to the same name. It will automatically connect to the Libera.Chat IRC network.

    $ pbot data_dir=coolbot irc.botnick=coolbot

#### Using custom settings
To connect to a specific IRC server or to configure additional settings, you may
[override the directory paths](#overriding-directories) and [override the registry values](#overriding-registry). Read on to the next section for examples.

##### Custom recommended settings
The following command is based on the [Recommended settings for IRC Networks](#recommended-settings-for-irc-networks) section earlier in this document.
The `irc.server` and `irc.port` settings are omitted because the default values will connect to the Libera.Chat IRC network.

Replace the placeholders, marked `X`, with values you want to use. Note that this is just for the first-time start-up. Regular subsequent start-up needs only `data_dir` to be overridden.

* If you have registered your botnick with the NickServ service, update the `irc.identify_password` entry in the `registry` file in your bot's data directory and then use this command:

    `pbot data_dir=X irc.botnick=X irc.sasl=1`

* Otherwise, use this one:

    `pbot data_dir=X irc.botnick=X`

##### Custom recommended IRCnet/other network settings
The following command is based on the [Recommended settings for IRC Networks](#recommended-settings-for-irc-networks) section earlier in this document.

Replace the placeholders, marked `X`, with values you want to use. Note that this is just for the first-time start-up. Regular subsequent start-up needs only `data_dir` to be overridden.

* If you want PBot to identify with a custom bot or service on IRCnet/other networks, use this command:

    `pbot data_dir=X irc.botnick=X irc.server=X irc.port=X general.identify_nick=X general.op_nick=X`

* Otherwise, use this one:

    `pbot data_dir=X irc.botnick=X irc.server=X irc.port=X`

### Regular start-up
After your initial start-up  command, you only need to use the `data_dir`
directory override when starting PBot. Any previously used registry overrides
have been saved to your data-directory's `registry` file.

    $ pbot data_dir=X

## Additional configuration
Once you've launched PBot, you can type directly into its terminal to execute
commands as the built-in PBot console admin user account. This will allow you
to use admin commands to create new users or join channels.

### Creating your bot owner admin account
To create your own fully privileged admin user account, use the following
commands in the PBot terminal console.

Suppose your nick is `Bob` and your hostmask is `Bob!~user@some.domain.com`.

    useradd Bob Bob!~user@*.domain.com global botowner

This will create a user account named `Bob` with the `botowner` [user-capability](Admin.md#user-capabilities) that can administrate
all channels. Note the wildcard replacing `some` in `some.domain.com`. Now as long as
your connected hostmask matches your user account hostmask, you will be recognized.

In your own IRC client, connected using the hostmask we just added, type the
following command:

    my password

This will show you the randomly generated password that was assigned to your
user account. You can change it -- if you want to -- with:

    my password <new password>

Then you can login with:

    login <password>

Now you can use `/msg` in your own IRC client to administrate PBot, instead of
the terminal console.

### Adding other users and admins
To add users to PBot, use the [`useradd`](Admin.md#useradd) command.

    useradd <username> <hostmasks> [channels [capabilities [password]]]

The `hostmasks` and `channels` arguments can be a comma-separated list of values.

If you omit the `capabilities` argument, the user will be a normal unprivileged user. See [user-capabilities](Admin.md#user-capabilities)
for more information about user-capabilities.

If you omit the `password` argument, a random password will be generated. The user
can use the [`my`](Commands.md#my) command to view or change it.

Users may view and change their own metadata by using the [`my`](Commands.md#my) command.

    my [key [value]]

For more information, see the [Admin documentation](Admin.md).

### Adding channels
To temporarily join channels, use the `join` command.

    join <channel>

To permanently add a channel to PBot, use the `chanadd` command. PBot will
automatically join permanently added channels.

    chanadd <channel>

To configure a permanent channel's settings, use the `chanset` command:

    chanset <channel> [key [value]]

You can `chanset` the following keys:

Name | Description | Default value
--- | --- | ---:
enabled | If set to false, PBot will not autojoin or respond to this channel. | 1
chanop | If set to true, PBot will perform OP duties in this channel. | 0
permop | If set to true, PBot will not de-OP itself in this channel. | 0

For more information, see the [Channels documentation](Admin.md#channel-management-commands).

## Further Reading
That should get you started. For further information about PBot, check out these topics.

### Commands
PBot has several core built-in commands. You've seen some of them in this document,
for setting up channels and admins. Additional commands can be added to PBot through
Plugins and Factoids.

For more information, see the [Commands documentation](Commands.md).

### Factoids
Factoids are a very special type of command. Anybody interacting with PBot
can create, edit, delete and invoke factoids.

In their most basic form, a factoid merely displays the text the creator sets.

    <pragma-> !factadd hello /say Hello, $nick!
       <PBot> hello added to global channel.

    <pragma-> PBot, hello
       <PBot> Hello, pragma-!

Significantly more complex factoids can be built by using `$variables`, command-substitution,
command-piping, `/code` invocation, and more!

For more information, see the [Factoids documentation](Factoids.md).

### Plugins
Plugins provide optional PBot features. The default plugins loaded by PBot is set by
the [`plugin_autoload`](../data/plugin_autoload) file in your data-directory. To autoload additional plugins,
add their name to this file.

You may manually load plugins using the `plug` command.

    plug <plugin>

You may unload plugins using the `unplug` command.

    unplug <plugin>

Plugins can be quickly reloaded by using the `replug` command.

    replug <plugin>

Currently loaded plugins may be listed with the `pluglist` command.

    <pragma-> !pluglist
       <PBot> Loaded plugins: ActionTrigger, AntiAway, AntiKickAutoRejoin, AntiNickSpam, AntiRepeat,
              AntiTwitter, AutoRejoin, Counter, Date, GoogleSearch, Quotegrabs, RemindMe, UrlTitles,
              Weather

For more information, see the [Plugins documentation](Plugins.md).

### Modules
Modules are external command-line executable programs and scripts that can be
loaded as PBot commands.

Suppose you have the [Qalculate!](https://qalculate.github.io/) command-line
program and you want to provide a PBot command for it. You can create a _very_ simple
shell script containing:

    #!/bin/sh
    qalc "$*"

And let's call it `qalc.sh` and put it in PBot's `modules/` directory.

Then you can use the PBot [`load`](Admin.md#load) command to load the `modules/qalc.sh` script as the `qalc` command:

    !load qalc qalc.sh

Now you have a [Qalculate!](https://qalculate.github.io/) calculator in PBot!

    <pragma-> !qalc 2 * 2
       <PBot> 2 * 2 = 4

For more information, see the [Modules documentation](Modules.md).
