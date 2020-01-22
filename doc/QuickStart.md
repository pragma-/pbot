# QuickStart

<!-- md-toc-begin -->
* [Installation](#installation)
  * [Installing Perl](#installing-perl)
  * [Installing CPAN modules](#installing-cpan-modules)
  * [Installing PBot](#installing-pbot)
    * [git (recommended)](#git-recommended)
    * [Download zip archive](#download-zip-archive)
* [First-time Configuration](#first-time-configuration)
  * [Clone data-directory](#clone-data-directory)
  * [Quick-start command](#quick-start-command)
  * [Edit Registry](#edit-registry)
    * [Recommended settings for IRC Networks](#recommended-settings-for-irc-networks)
      * [Freenode](#freenode)
      * [IRCnet](#ircnet)
      * [Other networks](#other-networks)
* [Starting PBot](#starting-pbot)
  * [Usage](#usage)
    * [Overriding directories](#overriding-directories)
    * [Overriding registry](#overriding-registry)
* [Additional Configuration](#additional-configuration)
  * [Adding Channels](#adding-channels)
  * [Adding Admins](#adding-admins)
  * [Loading Plugins](#loading-plugins)
* [Further Reading](#further-reading)
  * [Commands](#commands)
  * [Factoids](#factoids)
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

## First-time Configuration

After git-cloning (or unpacking the ZIP archive) you should have a directory named
`pbot/` (or `pbot-master/`). It should contain at least these directories and files:

Name | Description
--- | ---
[`PBot/`](https://github.com/pragma-/pbot/tree/master/PBot) | PBot source tree
[`Plugins/`](https://github.com/pragma-/pbot/tree/master/Plugins) | Dynamically loadable internal plugins
[`modules/`](https://github.com/pragma-/pbot/tree/master/modules) | External command-line executables invokable by PBot commands
[`data/`](https://github.com/pragma-/pbot/tree/master/data) | Default data-directory
[`doc/`](https://github.com/pragma-/pbot/tree/master/doc) | Helpful documentation
[`pbot`](https://github.com/pragma-/pbot/blob/master/pbot) | executable used to launch PBot

You may create a symbolic link to the `pbot` executable in `$HOME/bin/` or even
in `/usr/local/bin/`.

### Clone data-directory

PBot uses a data-directory to store all its configuration settings and data. You must
clone this data-directory for each instance of PBot you want to run.

Here we clone the data-directory for two PBot instances, naming them after the
IRC network they will connect to:

    $ cd pbot (or pbot-master)
    $ cp -r data freenode
    $ cp -r data ircnet

Alternatively, you could name it after your bot's nickname:

    $ cp -r data coolbot

### Quick-start command

At this point, you may start PBot if you wish. The default settings will connect
to the Freenode IRC network. Or you may read on to the next section for more
advanced configuration.

At minimum, the registry key `irc.botnick` must be set before PBot will connect
to any IRC servers. Here we will use the cloned data-directory `coolbot` named
after the botnick we'll use.

    $ pbot data_dir=coolbot irc.botnick=coolbot

### Edit Registry

PBot configuration is stored in a registry of key/value pairs grouped by sections.
For more details, see the [Registry documentation](Registry.md).

Now you may edit the `registry` file in your data-directory to configure PBot settings. Alternatively,
you may [override the registry entries via the command-line](#overriding-registry).

Some settings you may be interested in configuring:

Registry key | Description | Default value
--- | --- | ---:
irc.botnick | IRC nickname. This is the name people see when you talk. _Required._ | _undefined_
irc.username | IRC username. This is the `USER` field of your hostmask. | pbot3
irc.realname | IRC gecos/realname. This is the `general information` or `real-name` field, as seen in `WHOIS`. | https://github.com/pragma-/pbot
irc.server | IRC server address to connect. | irc.freenode.net
irc.port | IRC server port. | 6667
general.trigger | Bot trigger. Can be a character class containing multiple trigger characters. Can be overridden per-channel. | [!]

For a more comprehensive list see [this table](Registry.md#list-of-known-registry-items).

#### Recommended settings for IRC Networks
##### Freenode

The default settings are tailored for the Freenode IRC network. It is strongly recommended that
you register an account with NickServ and to request a hostmask cloak. Register your channels with
ChanServ. These services will protect your nickname, IP address and channels.

Once you register your botnick with NickServ, it is recommended to set these additional settings:

Registry key | Description | Recommended value
--- | --- | ---:
irc.identify_password | Password to use to identify to NickServ | `<password>`
irc.randomize_nick | Randomize IRC nickname when connecting to server. PBot will change to `irc.botnick` when logged-in. This prevents users from monitoring the botnick to catch its IP address before it is identified. | 1
general.autojoin_wait_for_nickserv | Wait for NickServ login before auto-joining channels. This prevents PBot from joining channels before it is identified and cloaked. | 1
general.identify_command | Command to send to NickServ to identify. `$nick` will be replaced with `irc.botnick`; `$password` will be replaced with `irc.identify_password`. If you wish to login to a NickServ account different than the `irc.botnick` you may replace the `$nick` text with a literal value. | `identify $nick $password`

##### IRCnet

IRCnet is one of the oldest IRC networks still running. It has no Services like NickServ and ChanServ.
Instead, its nicknames and channels are protected by custom bots.

These settings may be useful:

Registry key | Description | Default value| Recommended value
--- | --- | ---: | ---:
general.identify_nick | Who to /msg for login/identify/authentication. Defaults to NickServ, can be overridden to a custom bot. | NickServ | `<service botnick>`
general.identify_command | Command to send to `general.identify_nick` to login. | `identify $nick $password` | `<service bot command>`
general.op_nick | Who to /msg to request channel OP status. Defaults to ChanServ, can be overridden to a custom bot. | ChanServ | `<service botnick>`
general.op_command | Command to send to `general.op_nick` to request channel OP status. | `op $channel` | `<service bot command>`

##### Other networks

Other networks are untested. They should be very similiar to either Freenode or IRCnet, and so one or both of those
recommended settings should suffice. If you have any issues, please [report them here](https://github.com/pragma-/pbot/issues)
or in the `#pbot2` channel on the Freenode network.

## Starting PBot

### Usage

    $ pbot [directory overrides...; e.g. data_dir=...] [registry overrides...; e.g. irc.botnick=...]

#### Overriding directories

You may override PBot's default directory locations via the command-line.

    $ pbot data_dir=/path/to/data plugin_dir=/path/to/Plugins modules_dir=/path/to/modules

#### Overriding registry

You may override any of your Registry values via the command-line. Any overrides made will be
saved to the `registry` file. You do not need to use the override every time you launch PBot.

    $ pbot irc.botnick=coolbot irc.server=irc.freenode.net irc.port=6667

## Additional Configuration

Once you have launched PBot, you can type into the STDIN to execute commands within
the bot. Alternatively you can launch your own IRC client and `/msg` PBot.

Additional configuration can be done by sending the following commands to PBot.

### Adding Channels

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

### Adding Admins

To add admins to PBot, use the `adminadd` command.

    adminadd <name> <channel> <hostmask> <level> <password>

To change an admin's properties, use the `adminset` command.

    adminset <channel> <name or hostmask> [key [value]]

You may set the follow admin properties:

Name | Description
--- | ---
name | A unique name identifying this admin account.
level | The privilege level of this admin. See [this table](Admin.md#admin-levels) for more information.
password | The password for this admin account.
loggedin | If set to 1, the admin is logged in.
stayloggedin | If set to 1, the admin will not be logged out when they part/quit.

For more information, see the [Admin documentation](Admin.md#admin-management-commands).

### Loading Plugins

Plugins provide optional PBot features. The default plugins loaded by PBot is set by
the `plugin_autoload` file in your data-directory.

You may load plugins using the `plug` command.

    plug <plugin>

You may unload plugins using the `unplug` command.

    unplug <plugin>

Currently loaded plugins may be listed with the `pluglist` command.

    <pragma-> !pluglist
       <PBot> Loaded plugins: ActionTrigger, AntiAway, AntiKickAutoRejoin, AntiNickSpam, AntiRepeat, AntiTwitter, AutoRejoin, Counter, GoogleSearch, Quotegrabs, RemindMe, UrlTitles

For more information, see the [Plugins documentation](Plugins.md).

## Further Reading

That should get you started. For further information about PBot, check out these topics.

### Commands

PBot has several core built-in commands. You've seen some of them in this document,
for setting up channels and admins. Additional commands can be added to PBot through
Plugins and Factoids.

### Factoids

Factoids are a very special type of command. Anybody interacting with PBot
can create, edit, delete and invoke factoids. Factoids can be locked by the
creator of the factoid to prevent them from being edited by others.

At its most simple, factoids merely output the text the creator sets.

    <pragma-> !factadd hello /say Hello, $nick!
       <PBot> hello added to global channel.

    <pragma-> PBot, hello
       <PBot> Hello, pragma-!

Significantly more complex factoids can be built by using `$variables`, command-substitution,
command-piping, `/code` invocation, and more!

For more information, see the [Factoids documentation](Factoids.md).

### Modules

Modules are external command-line executable programs and scripts that can be
loaded via PBot Factoids.

Suppose you have the [Qalculate!](https://qalculate.github.io/) command-line
program and you want to provide a PBot command for it. You can create a _very_ simple
shell script containing:

    #!/bin/sh
    qalc "$*"

And let's call it `qalc.sh` and put it in PBot's `modules/` directory.

Then you can add the `qalc` factoid:

    !factadd global qalc qalc.sh

And then set its `type` to `module`:

    !factset global qalc type module

Alternatively, you can simply use the [`load`](Admin.md#load) command:

    !load qalc qalc.sh

Now you have a `qalc` calculator in PBot!

    <pragma-> !qalc 2 * 2
       <PBot> 2 * 2 = 4

For more information, see the [Modules documentation](Modules.md).
