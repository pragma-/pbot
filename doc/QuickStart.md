
QuickStart
==========
This is a work-in-progress rough draft Quick Start guide. This notification will be removed when this guide is mature.

<!-- md-toc-begin -->
* [QuickStart](#quickstart)
  * [Installing](#installing)
    * [Prerequisites](#prerequisites)
      * [Requirements](#requirements)
      * [Installing CPAN modules](#installing-cpan-modules)
      * [Installing a crontab](#crontab)
  * [First-time Configuration](#first-time-configuration)
    * [Clone PBot & data-directory](#clone-data-directory)
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
<!-- md-toc-end -->

Installing
----------

### Prerequisites

#### Requirements *(root)*

	$ dnf -y install perl perl-CPAN git screen crontabs nano
> or 		$ aptitude install perl perl-CPAN git screen crontabs nano
> or 		$ apt-get install perl perl-CPAN git screen crontabs nano

	$ adduser -m pbot
	

#### Installing CPAN modules *(root)*

PBot has many features; some of these depend on Perl modules written by others.
This list can be found in the [`MODULES`](https://github.com/pragma-/pbot/blob/master/MODULES) file in the root directory of this source.

The modules may be installed with a simple command:

    $ cpan
	cpan[1]> force install <modules> 
	cpan[49]> exit

Some CPAN modules may fail to pass certain tests due to outdated variables.
Despite these test failures, their core functionality should still work as
expected.

#### Installing a crontab *(pbot)*

	$ su pbot
	$ crontab -e

0,5,10,15,20,25,30,35,40,45,50,55 * * * * screen -dmS pbot /home/pbot/pbot/pbot data_dir=/home/pbot/pbot/freenode >/dev/null 2>&1

>  or
>   0,15,30,45 * * * * screen -dmS pbot2 /home/pbot/pbot/pbot data_dir=/home/pbot/pbot/ircnet >/dev/null 2>&1
>> or
> 0,20,40 * * * * screen -dmS coolbot /home/pbot/pbot/pbot data_dir=/home/pbot/pbot/coolbot >/dev/null 2>&1

	

First-time Configuration
------------------------

### Clone PBot & data-directory *(pbot)*

PBot uses a data-directory to store all its configuration settings and data. It
is **_strongly_** recommended to clone the default data-directory for each PBot
connection.

Here we clone the data-directory for two PBot instances, naming them after the
IRC network they will connect to:

    $ su pbot
    $ cd /home/pbot
    $ git clone https://github.com/pragma-/pbot.git
    $ cd pbot
    $ cp -r data freenode
    $ cp -r data ircnet

Alternatively, you could name it after your bot's nickname:

    $ cp -r data coolbot

### Edit Registry *(pbot)*

	$ cd data
	$ nano registry
> or $ cd freenode && vi registry
> or $ cd coolbot
> ...

PBot configuration is stored in a registry of key/value pairs grouped by sections.
See https://github.com/pragma-/pbot/blob/master/doc/Registry.md for more details.

Now you may edit the `registry` file in your data-directory to configure PBot settings. Alternatively,
you may [override the registry entries via the command-line](#overriding-registry).

Some settings you may be interested in configuring:

Registry key | Description | Default value
--- | --- | ---:
irc.botnick | IRC nickname. This is the name people see when you talk. _Required._ | _undefined_
irc.username | IRC username. This is the `USER` field of your hostmask. | pbot3
realname | IRC gecos/realname. This is the `general information` or `real-name` field, as seen in `WHOIS`. | https://github.com/pragma-/pbot
server | IRC server address to connect. | irc.freenode.net
irc.port | IRC server port. | 6667
general.trigger | Bot trigger. Can be a character class containing multiple trigger characters. Can be overridden per-channel. | [!]

For a more comprehensive list see https://github.com/pragma-/pbot/blob/master/doc/Registry.md#list-of-recognized-registry-items.

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
recommended settings should suffice. If you have any issues, please report them at https://github.com/pragma-/pbot/issues
or in the `#pbot2` channel on the Freenode network.

Starting PBot
-------------

### Usage *(pbot)*

pbot [directory overrides...; e.g. data_dir=...] [registry overrides...; e.g. irc.botnick=...]

    $ screen -dmS pbot /home/pbot/pbot/pbot data_dir=/home/pbot/pbot/freenode
    $ screen -r pbot 	(for attaching to the screen named: pbot)
    ctrl+a than ctrl+d 	(for detaching without closing the screen)

> or $ screen -dmS coolbot /home/pbot/pbot/pbot data_dir=/home/pbot/pbot/coolbot
> or $ ./pbot data_dir=/home/pbot/pbot/...

#### Overriding directories
#### Overriding registry

Additional Configuration
------------------------

### Adding Channels

### Adding Admins

### Loading Plugins
