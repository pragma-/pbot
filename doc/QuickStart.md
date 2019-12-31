QuickStart
==========
PBot is an IRC bot written in Perl. This is a work-in-progress rough draft Quick Start guide.
This notification will be removed when this guide is mature.

<!-- md-toc-begin -->
* [QuickStart](#quickstart)
  * [Installing](#installing)
    * [Prerequisites](#prerequisites)
      * [Installing CPAN modules](#installing-cpan-modules)
  * [First-time Configuration](#first-time-configuration)
    * [Clone data-directory](#clone-data-directory)
    * [Edit Registry](#edit-registry)
      * [Notable settings](#notable-settings)
      * [Recommended settings for IRC Networks](#recommended-settings-for-irc-networks)
        * [Freenode](#freenode)
        * [IRCnet](#ircnet)
        * [Other networks](#other-networks)
    * [Adding Channels](#adding-channels)
    * [Adding Admins](#adding-admins)
    * [Loading Plugins](#loading-plugins)
<!-- md-toc-end -->

Installing
----------

### Prerequisites

#### Installing CPAN modules

PBot has many features; some of these depend on Perl modules written by others.
This list can be found in the `MODULES` file in the root directory of this source.

The modules may be installed with a simple command:

    cpan -f -i $(cat MODULES)

Some CPAN modules may fail to pass certain tests due to outdated variables.
Despite these test failures, their core functionality should still work as
expected.

First-time Configuration
------------------------

### Clone data-directory

PBot uses a data-directory to store all its configuration settings and data. It
is **_strongly_** recommended to clone the default data-directory for each PBot
connection.

Here we clone the data-directory for two PBot instances, naming them after the
IRC network they will connect to:

    cp -r data freenode
    cp -r data ircnet

Alternatively, you could name it after your bot's nickname:

    cp -r data coolbot

### Edit Registry

PBot configuration is stored as key/value pairs grouped by sections. We call this the Registry.
See https://github.com/pragma-/pbot/blob/master/doc/Registry.md for more details.

Now you may edit the `registry` file in your data-directory to configure PBot settings.

#### Notable settings

Some settings you may be interested in configuring:

Registry key | Description | Default value
--- | --- | ---:
irc.botnick | IRC nickname. This is the name people see when you talk. | _undefined_
irc.username | IRC username. This is the `USER` field of your hostmask. | pbot3
irc.ircname | IRC gecos/realname. This is the `general information` or `real-name` field, as seen in `WHOIS`. | https://github.com/pragma-/pbot
irc.ircserver | IRC server to connect | irc.freenode.net
irc.port | IRC server port | 6667
irc.identify_password | Password to use to identify to NickServ/service bot. | _undefined_
irc.randomize_nick | Randomize IRC nickname when connecting to server. PBot will change to irc.botnick when connected or logged-in. | 0
general.trigger | Bot trigger | [!]
general.autojoin_wait_for_nickserv | Wait for NickServ login before auto-joining channels. | 0
general.identify_nick | Who to /msg for login/identify/authentication. Defaults to NickServ, can be overridden to a custom bot. | NickServ
general.identify_command | Command to send to `general.identify_nick` to login. | identify $nick $password
general.op_nick | Who to /msg to request channel OP status. Defaults to ChanServ, can be overridden to a custom bot. | ChanServ
general.op_command | Command to send to `general.op_nick` to request channel OP status. | op $channel
googlesearch.api_key | API key for Google Custom Search. | _undefined_
googlesearch.context | Google Custom Search context key. | _undefined_

#### Recommended settings for IRC Networks
##### Freenode

The default settings are tailored for the Freenode IRC network. It is strongly recommended that
you register an account with its NickServ service and to request a hostmask cloak. It is strongly
recommended to register your channels with its ChanServ service. These services will protect your
nick, IP address and channels.

Once you register your botnick with NickServ, it is recommended to set `irc.randomize_nick` to `1`.
This will cause PBot to connect to the network with a randomized nickname, which will prevent users
from watching for your connection to attempt to capture your IP address.

Then set `irc.autojoin_wait_for_nickserv` to `1`. This will cause PBot to wait until logged into NickServ
before attempting to auto-join your channels, to ensure your NickServ host cloak is applied beforehand.

##### IRCnet

IRCnet is one of the oldest IRC networks still running. It has no Services like NickServ and ChanServ.
Instead, its nicknames and channels are protected by custom bots. You may configure the
`general.identify_nick`, `general.identify_command`, `general.op_nick` and `general.op_command` settings
to point at custom bots and commands to login/request OP.

##### Other networks

Other networks are untested. They should be very similiar to either Freenode or IRCnet, and so one of those
recommended settings should work. If you have any issues, please report them at https://github.com/pragma-/pbot/issues
or in the `#pbot2` channel on the Freenode network.

### Adding Channels

### Adding Admins

### Loading Plugins



