# Administrative

<!-- md-toc-begin -->
* [Logging in and out](#logging-in-and-out)
  * [login](#login)
  * [logout](#logout)
* [User-management](#user-management)
  * [useradd](#useradd)
  * [userdel](#userdel)
  * [userset](#userset)
  * [userunset](#userunset)
    * [User metadata list](#user-metadata-list)
  * [Listing users](#listing-users)
* [User capabilities](#user-capabilities)
  * [Introduction](#introduction)
  * [cap](#cap)
    * [Listing capabilities](#listing-capabilities)
    * [Grouping capabilities](#grouping-capabilities)
      * [Creating a new group or adding to an existing group](#creating-a-new-group-or-adding-to-an-existing-group)
      * [Removing capabilites from a group or deleting a group](#removing-capabilites-from-a-group-or-deleting-a-group)
    * [Giving capabilities to users](#giving-capabilities-to-users)
    * [Checking user capabilities](#checking-user-capabilities)
    * [Listing users who have a capability](#listing-users-who-have-a-capability)
    * [User capabilities list](#user-capabilities-list)
* [Channel management](#channel-management)
  * [join](#join)
  * [part](#part)
  * [chanadd](#chanadd)
  * [chanrem](#chanrem)
  * [chanset](#chanset)
  * [chanunset](#chanunset)
  * [chanlist](#chanlist)
    * [Channel metadata list](#channel-metadata-list)
  * [ignore](#ignore)
  * [unignore](#unignore)
  * [blacklist](#blacklist)
  * [nicklist](Admin.md#nicklist)
  * [banlist](Admin.md#banlist)
  * [checkban](Admin.md#checkban)
  * [checkmute](Admin.md#checkmute)
  * [op](#op)
  * [deop](#deop)
  * [voice](#voice)
  * [devoice](#devoice)
  * [mode](#mode)
  * [ban/mute](#banmute)
  * [unban/unmute](#unbanunmute)
  * [invite](#invite)
  * [kick](#kick)
* [Module-management](#module-management)
  * [load](#load)
  * [unload](#unload)
  * [Listing modules](#listing-modules)
* [Plugin-management](#plugin-management)
  * [plug](#plug)
  * [unplug](#unplug)
  * [replug](#replug)
  * [pluglist](#pluglist)
* [Command metadata](#command-metadata)
  * [cmdset](#cmdset)
  * [cmdunset](#cmdunset)
  * [Command metadata list](#command-metadata-list)
* [Event-queue management](#event-queue-management)
  * [eventqueue](#eventqueue)
* [Process-management](#process-management)
  * [ps](#ps)
  * [kill](#kill)
* [Message-history/user-tracking](#message-historyuser-tracking)
  * [recall](#recall)
  * [id](#id)
  * [aka](#aka)
  * [akalink](#akalink)
  * [akaunlink](#akaunlink)
  * [akadelete](#akadelete)
* [Miscellaneous](#miscellaneous)
  * [export](#export)
  * [refresh](#refresh)
  * [reload](#reload)
  * [sl](#sl)
  * [die](#die)
<!-- md-toc-end -->

## Logging in and out
You cannot use any of the admin commands unless you login. Note that the [`login`](#login) command requires that your currently
connected IRC hostmask matches the hostmask configured for the user account.

You can keep your user account permanently logged in by setting a couple of [user metadata](#user-metadata-list) values. See
the [user metadata list](#user-metadata-list) for more information.

### login
Logs into PBot.

Usage:  `login [channel] <password>`

### logout
Logs out of PBot.

Usage: `logout`

## User-management
### useradd
Adds a new user to PBot.

Usage: `useradd <username> <hostmasks> [channels [capabilities [password]]]`

Parameter | Description
--- | ---
`username` | A unique name to identify this account (usually the `nick` of the user, but it can be any identifier).
`hostmasks` | The hostmasks from which this user is recognized/allowed to login from (e.g., `somenick!*@*.somedomain.com` or `*!*@unaffiliated/someuser`). Can be a comma-separated list of values.
`channels` | The channels this user belongs to; use `global` for all channels. Can be a comma-separated list of values.
`capabilities` | A comma-separated list of [user-capabilities](#user-capabilities) for this user.
`password` | The password the user will use to login (from `/msg`, obviously). Generates a random password if omitted. Users may view and set their password by using the [`my`](Commands.md#my) command.

### userdel
Removes a user from PBot.

Usage: `userdel <username>`

### userset
Sets [metadata](#user-metadata-list) or [user-capabilities](#user-capabilities-list) for a user account. See also: [user metadata list](#user-metadata-list).

If `key` is omitted, it will list all the keys and values that are set.  If `value` is omitted, it will show the value for `key`.

Usage: `userset <username> [<key> [value]]`

### userunset
Deletes a [metadata](#user-metadata-list) or [user-capability](#user-capabilities-list) from a user account.

Usage: `userunset <username> <key>`

#### User metadata list
This is a list of recognized metadata keys for user accounts.

Name | Description
--- | ---
`autologin` | Automatically log the user in when they join the channel. *Note: make sure the user account's hostmask wildcards are as restrictive as possible.*
`autoop` | Give the user `operator` status when they join the channel. *Note: make sure the user account's hostmask wildcards are as restrictive as possible.*
`autovoice` | Give the user `voiced` status when they join the channel. *Note: make sure the user account's hostmask wildcards are as restrictive as possible.*
[capabilities](#user-capabilities-list) | [User-capabilities](#user-capabilities) are managed as user metadata.
`channels` | A comma-separated list of channels this user belongs to.
`hostmasks` | A comma-separated list of hostmasks this user is recognized by.
`location` | Sets your location for using the [`weather`](Commands.md#weather) command without any arguments.
`loggedin` | Whether the user is logged in or not.
`notyposub` | Disallows `s///` typo substitutions.
`password` | The password for the user account.
`stayloggedin` | Do not log the user out when they part/quit.
`timezone` | Sets your timezone for using the [`date`](Commands.md#date) command without any arguments.
`units` | Sets the unit for Wolfram\|Alpha answers (`imperial` or `metric`)

### Listing users
To list user accounts, use the `users` command. This is not an admin command, but
it is included here for completeness. Users with a plus (+) sign next their name have
[user-capabilities](#user-capabilities) set on their account.

Usage: `users [channel]`

When the optional `[channel]` argument is provided, only users for that channel
will be listed; no global users will be listed.

When `[channel]` is omitted and the command is used in a channel, it will list
the users for that channel, plus all global users.

When `[channel]` is omitted and the command is used from private message, it will
list all users from all channels, including global users.

## User capabilities
PBot uses a user-capability system to control what users can and cannot do. User-capabilities
provides fine-grained permissions over various PBot functionality.

### Introduction
For example, imagine a user named alice. alice has no capabilities granted yet.
She tries to use the [`ban`](#banmute) command:

    <alice> !ban somebody
     <PBot> The ban command requires the can-ban capability, which your user account does not have.

Suppose alice tries to grant herself the can-ban capability:

    <alice> !my can-ban 1
     <PBot> The can-ban metadata requires the can-modify-capabilities capability, which your user account does not have.

To grant her the `can-ban` capability, a user with the `can-userset` and `can-modifiy-capabilities` capabilities
can use the [`userset`](#userset) command:

    <bob> !userset alice can-ban 1

Now alice can use the `ban` command.

Let's consider the [`mode`](#mode) command. Channel operators can use their IRC client's `/mode` command to
set any channel modes, including any undesirable modes (such as +k). Suppose you'd prefer to limit
their modes to just a specific subset of all modes. You can do this with user-capabilities. To do so,
instead of making them channel operators you can make them PBot users and grant them specific PBot
user-capabilities.

First grant the user the `can-mode` capability so they can use the PBot [`mode`](#mode) command. Then grant them the specific
`can-mode-<flag>` capabilities. To allow them to set any modes without restriction, grant them the `can-mode-any`
capability.

See this demonstration:

    <alice> !mode +b test
     <PBot> The mode command requires the can-mode capability, which your user account does not have.
      <bob> !userset alice can-mode 1
    <alice> !mode +b test
     <PBot> Your user account does not have the can-mode-b capability required to set this mode.
      <bob> !userset alice can-mode-b 1
    <alice> !mode +b test
          * PBot sets mode +b test!*@*
    <alice> !mode +k lol
     <PBot> Your user account does not have the can-mode-k capability required to set this mode.

As you can see, user-capabilities can be very flexible and very powerful in configuring your
channel users. Check out [grouping capabilities](#grouping-capabilities) in the upcoming section
of this document, as well. Read on!

### cap
Use the `cap` command to list capabilities, to manage capability groups and to
see what capabilities a user has.

Usage:

    cap list [capability] |
    cap group <existing or new capability group> <existing capabilities...> |
    cap ungroup <existing capability group> <grouped capability> |
    cap userhas <user> [capability] |
    cap whohas <capability>

#### Listing capabilities
Use `cap list [capability]` to list user-capabilities.

If `[capability]` is omitted, the command will list all available capabilities.

    <pragma-> cap list
       <PBot> Capabilities: admin (25 caps), botowner (71 caps), can-ban (1 cap), can-deop (1 cap),
              can-devoice (1 cap), can-mode-any (53 caps), can-mute (1 cap), can-op (1 cap), can-unban (1 cap),
              can-unmute (1 cap), can-voice (1 cap), chanmod (4 caps), chanop (10 caps), moderator (4 caps),
              can-actiontrigger, can-akalink, can-akaunlink, can-antispam, can-blacklist, ...


#### Grouping capabilities
Capabilities can be grouped together into a collection, which can then be applied to a user.
Capability groups can contain nested groups.

In the [listing capabilities](#listing-capabilities) example, the `admin` capability is
a group containing several capabilities, including other grouped capabilites such as the `chanop` capability
group which itself can contain more groups and capabilities.

Observe.

    <pragma-> cap list admin
       <PBot> Grouped capabilities for admin: can-mode-any (53 caps), chanop (10 caps),
              can-actiontrigger, can-akalink, can-akaunlink, can-antispam, can-blacklist,
              can-chanlist, can-clear-bans, can-clear-mutes, can-countertrigger, can-ignore,
              can-in, can-join, can-kick-wildcard, can-mode, can-op-wildcard, can-part,
              can-unignore, can-useradd, can-userdel, can-userset, can-userunset, can-voice-wildcard
<!-- -->
    <pragma-> cap list chanop
       <PBot> Grouped capabilities for chanop: can-ban (1 cap), can-deop (1 cap), can-devoice (1 cap),
              can-mute (1 cap), can-op (1 cap), can-unban (1 cap), can-unmute (1 cap), can-voice (1 cap),
              can-invite, can-kick
<!-- -->
    <pragma-> cap list can-ban
       <PBot> Grouped capabilities for can-ban: can-mode-b

##### Creating a new group or adding to an existing group
To create a new capability group or to add capabilities to an existing group,
use the `cap group` command.

Usage: `cap group <existing or new capability group> <existing capabilities...>`

For example, to create a new capability group called `moderator` who can strictly
only set `mode +m` or `mode -m` and use the `voice` and `devoice` commands:

    <pragma-> cap group moderator can-voice can-devoice can-mode can-mode-m
<!-- -->
    <pragma-> cap list moderator
       <PBot> Grouped capabilities for moderator: can-devoice (1 cap), can-voice (1 cap),
              can-mode, can-mode-m

Then you can set this capability group on users with the [`userset`](#userset) command.

##### Removing capabilites from a group or deleting a group
To remove capabilities from a group or to delete a group, use the `cap ungroup`
command.

Usage: `cap ungroup <existing capability group> <grouped capability>`

When the last capability is removed from a group, the group itself will be deleted.

#### Giving capabilities to users
To give capabilities to a user, use the [`useradd`](#useradd) or the [`userset`](#userset) commands.

    <pragma-> useradd alice global alice!*@* moderator

or

    <pragma-> userset alice moderator 1

#### Checking user capabilities
To see what capabilities a user account has, use the `cap userhas` command.

Usage: `cap userhas <user> [capability]`

If the `[capability]` argument is omitted, the command will list all capability
groups and capabilities the user account has.

If the `[capability]` argument is provided, the command will determine if the
capability is granted to the user account.

    <pragma-> cap userhas alice
       <PBot> User alice has capabilities: moderator (4 caps)
<!-- -->
    <pragma-> cap userhas alice can-voice
       <PBot> Yes. User alice has capability can-voice.
<!-- -->
    <pragma-> cap userhas alice can-op
       <PBot> No. User alice does not have capability can-op.

#### Listing users who have a capability
To list all the users that have a capability, use the `cap whohas` command.

Usage: `cap whohas <capability>`

    <pragma-> cap whohas moderator
       <PBot> Users with capability moderator: alice
<!-- -->
    <pragma-> cap whohas can-voice
       <PBot> Users with capability can-voice: alice

#### User capabilities list
This is a list of built-in capability groups and capabilities. You can create
new custom capability groups with the [`cap group`](#creating-a-new-group-or-adding-to-an-existing-group) command.

Please note that PBot is sometimes updated more frequently than this list is updated. To see the most
current list of capabilities, use the [`cap list`](#listing-capabilities) command or see the
[`data/capabilities`](../data/capabilities) file.

Name | Description | Belongs to group
--- | --- | ---
`botowner` | The most powerful capability group. Contains all capabilities.| none
`admin` | The admin capability group. Contains the basic administrative capabilities. | botowner
`chanop` | Channel operator capability group. Contains the basic channel management capabilities. | botowner, admin
`chanmod` | Channel moderator capability group. Grants `can-voice`, `can-devoice` and the use of the `mod` command without being voiced. | botowner
`can-<command name>` | If a command `<command name>` has the `cap-required` [command metadata](#command-metadata-list) then the user's account must have the `can-<command name>` capability to invoke it. For example, the [`op`](#op) command requires users to have the `can-op` capability. | botowner, various groups
`can-mode-<flag>` | Allows the [`mode`](#mode) command to set mode `<flag>`. For example, to allow a user to set `mode +m` give them the `can-mode` and `can-mode-m` capabilities. `<flag>` is one mode character. | botowner, can-mode-any
`can-mode-any` | Allows the [`mode`](#mode) command to set any mode flag. | botowner
`can-modify-admins` | Allows the user to modify user accounts that have the `admin` capability | botowner
`can-modify-capabilities` | Allows the user to use the [`useradd`](#useradd) or [`userset`](#userset) commands to add or remove capabilities from users. | botowner
`can-group-capabilities` | Allows the user to use the [`cap group`](#cap) and [`cap ungroup`](#cap) commands to modify capability groups. | botowner
`can-clear-bans` | Allows the user to use [`unban *`](#unbanunmute) to clear a channel's bans. | botowner, admin
`can-clear-mutes` | Allows the user to use [`unmute *`](#unbanunmute) to clear a channel's mutes. | botowner, admin
`can-kick-wildcard` | Allows the user to use wildcards with the [`kick`](#kick) command. | botowner, admin
`can-op-wildcard` | Allows the user to use wildcards with the [`op`](#op) command. | botowner, admin
`can-voice-wildcard` | Allows the user to use wildcards with the [`voice`](#voice) command. | botowner, admin, chanop, chanmod
`is-whitelisted` | The user is exempt from anti-flood, ban-evasion checks, wild-card kicking, etc. | botowner, admin, chanop

## Channel management
### join
To temporarily join a channel, use the `join` command. The channels may be a comma-
separated list.

Usage: `join <channel(s)>`

### part
To temporarily leave a channel (that is, without removing it from PBot's list
of channels), use the `part` command. The channels may be a comma-separated
list.

Usage `part <channel(s)>`

### chanadd
`chanadd` permanently adds a channel to PBot's list of channels to auto-join and manage.

Usage: `chanadd <channel>`

### chanrem
`chanrem` removes a channel from PBot's list of channels to auto-join and manage.

Usage: `chanrem <channel>`

### chanset
`chanset` sets a channel's metadata. See [channel metadata list](#channel-metadata-list)

Usage: `chanset <channel> [key [value]]`

If both `key` and `value` are omitted, chanset will show all the keys and values for that channel. If only `value` is omitted, chanset will show the value for that key.

### chanunset
`chanunset` deletes a channel's metadata key.

Usage: `chanunset <channel> <key>`

### chanlist
`chanlist` lists all added channels and their metadata keys and values.

#### Channel metadata list
Name | Description
--- | ---
`enabled` | When set to a true value, PBot will auto-join this channel after identifying to NickServ (unless `general.autojoin_wait_for_nickserv` is `0`, in which case auto-join happens immediately).
`chanop` | When set to a true value, PBot will perform channel management (anti-flooding, ban-evasion, etc).
`permop` | When set to a true value, PBot will automatically op itself when joining and remain opped instead of automatically opping and deopping as necessary.

### ignore
Ignore a user. If you omit `[channel]` PBot will ignore the user in all channels, including private messages.

Usage: `ignore <hostmask regex> [channel [timeout]]`

Timeout can be specified as an relative time in English; for instance, `5 minutes`, `1 month and 2 weeks`, `next thursday`, `friday after next`, `forever` and such.

### unignore
Unignores a user. If you omit `[channel]` PBot will unignore the user from all channels, including private messages.

Usage:  `unignore <hostmask regex> [channel]`

### blacklist
Blacklists a hostmask regex from joining a channel.

Usages:

- `blacklist <show/list>`
- `blacklist add <hostmask regex> [channel]`
- `blacklist remove <hostmask regex> [channel]`

### [nicklist](Admin.md#nicklist)
The `nicklist` command displays information about entries in PBot's internal nicklist.

Usage: `nicklist (<channel [nick]> | <nick>) [-sort <by>] [-hostmask] [-join]`

Option | Description
--- | ---
`-hostmask` | shows full hostmasks instead of nicks
`-join` | include join timestamps

Examples:

    <pragma-> nicklist #c
       <PBot> 701 nicks in #c: pragma-: last spoken 1h ago, etc...

    <pragma-> nicklist #c pragma-
       <PBot> Nicklist information for pragma-!~chaos@user/pragmatic-chaos in #c: last spoken 1h ago, etc...

### [banlist](Admin.md#banlist)
The `banlist` command displays information about entries in PBot's internal banlist.  PBot's internal banlist
remembers the original setters and timestamps of ban entries when the IRC server forgets them. PBot's internal
banlist can store extra metadata such as ban-reasons, ban-timeouts, etc.

Usage: `banlist <channel>`

Example:

    <pragma-> banlist #c
       <PBot> Ban list for #c: 1 ban: loser!*@* on Tue Aug 31 06:41:24 2021 PDT (14d15h ago) by candide!~pbot3@about/c/bot/candide for chat-flooding (2h remaining); 0 mutes.

### [checkban](Admin.md#checkban)
The `checkban` command displays information about an entry in PBot's internal banlist. PBot's internal banlist
remembers the original setters and timestamps of ban entries when the IRC server forgets them. PBot's internal
banlist can store extra metadata such as ban-reasons, ban-timeouts, etc.

Usage: `checkban <mask> [channel]`

If the `[channel]` option is omitted, the channel in which the command is invoked will be used.

Example:

    <pragma-> checkban loser!*@*
       <PBot> loser!*@* banned in #c on Tue Aug 31 06:41:24 2021 PDT (14d15h ago) by candide!~pbot3@about/c/bot/candide for chat-flooding (2h remaining)

### [checkmute](Admin.md#checkmute)
The `checkmute` command is identical to the [`checkban`](#checkban) command, except for mutes instead of bans.

Usage: checkban <mask> [channel]

### op
### deop
### voice
### devoice
The `op`, `deop`, `voice` and `devoice` commands all perform their respective named action.

The `targets` parameter can be a list of multiple nicks, optionally containing
wildcards. If `targets` is omitted, the action will be performed on the caller.

Usages:

In channel:

* `op [targets]`
* `deop [targets]`
* `voice [targets]`
* `devoice [targets]`

From private message:

* `op <channel> [targets]`
* `deop <channel> [targets]`
* `voice <channel> [targets]`
* `devoice <channel> [targets]`

### mode
Sets or unsets channel or user modes.

Usage: `mode [channel] <flags> [targets]`

PBot extends the IRC `MODE` command in useful ways. For instance, the `targets`
parameter may contain wildcards. To op everybody whose nick ends with `|dev` you
can do `!mode +o *|dev` in a channel.

### ban/mute
Bans or mutes a user. If the argument is a nick instead of a hostmask, it will determine an appropriate banmask for that nick.
The argument can be a comma-separated list of multiple nicks or masks.

Usages:
- `ban <nick or hostmask> [channel [timeout]]`
- `mute <nick or hostmask> [channel [timeout]]`

If `timeout` is omitted, PBot will ban the user for 24 hours. Timeout can be specified as an relative time in English; for instance, `5 minutes`, `1 month and 2 weeks`, `next thursday`, `friday after next`, `forever` and such.

### unban/unmute
Unbans or unmutes a user. If the argument is a nick instead of a hostmask, it will find all bans that match any of that nick's hostmasks or NickServ accounts and unban them.
The argument can be a comma-separated list of multiple nicks or masks. If the argument is `*` then all bans/mutes for the channel will be removed.

Usages:
- `unban <nick or hostmask> [channel]`
- `unmute <nick or hostmask> [channel]`

### invite
Invites a user to a channel.

Usage: `invite [channel] <nick>`

### kick
Removes a user from the channel. `<nick>` can be a comma-separated list of multiple users, optionally containing wildcards. If `[reason]` is omitted, a random insult will be used.

Usage from channel:   `kick <nick> [reason]`
From private message: `kick <channel> <nick> [reason]`

## Module-management
Note that modules are "reloaded" each time they are executed. There is no need to `refresh` after editing a module.

### load
This command loads a module in `$data_dir/modules/` as a PBot command. It is
equivalent to `factadd`ing a new keyword and then setting its `type` to `module`.

Usage: `load <keyword> <module>`

For example, to load `$data_dir/modules/qalc.sh` as the `qalc` command:

    <pragma-> !load qalc qalc.sh

### unload
This command unloads a module. It is equivalent to deleting the factoid keyword
the module was loaded as.

Usage: `unload <keyword>`

### Listing modules
To list the loaded modules, use the `list modules` command. This is not an admin command, but
it is included here for completeness.

Usage: `list modules`

## Plugin-management
### plug
Loads a plugin into PBot.

Usage: `plug <plugin>`

### unplug
Unloads a plugin from PBot.

Usage: `unplug <plugin>`

### replug
Reloads a plugin into PBot. The plugin is first unloaded and then it is loaded again.

Usage: `replug <plugin>`

### pluglist
Lists all currently loaded plugins. This isn't an admin command, but it is included here for completeness.

Usage: `pluglist`

    <pragma-> !pluglist
       <PBot> Loaded plugins: ActionTrigger, AntiAway, AntiKickAutoRejoin, AntiNickSpam,
              AntiRepeat, AntiTwitter, AutoRejoin, Battleship, Connect4, Counter, Date,
              GoogleSearch, Quotegrabs, RemindMe, RestrictedMod, Spinach, TypoSub, UrlTitles,
              Weather, Wolfram, Wttr

## Command metadata
### cmdset
Use `cmdset` to set various [metadata](#command-metadata-list) for built-in commands.

Usage: `cmdset <command> [key [value]]`

Omit `<key>` and `<value>` to list all the keys and values for a command.  Specify `<key>`, but omit `<value>` to see the value for a specific key.

### cmdunset
Use `cmdunset` to delete various [metadata](#command-metadata-list) from built-in commands.

Usage: `cmdunset <command> <key>`

### Command metadata list
Name | Description
--- | ---
`help` | The text to display for the [`help`](Commands.md#help) command.
`cap-required` | When set to a true value then the command requires that users have the `can-<command name>` [capability](#user-capabilities) before they can invoke it.
`dont-replace-pronouns` | When set to a true value then pronouns such as "my", "me", "your", etc, will not be intuitively replaced with nicks and such.
`background-process` | When set to a true value then this command will be executed as a background process. Use this for commands that can potentially take a long time to complete.
`process-timeout` | The timeout, in seconds, before the process is automatically killed. If not set then the `processmanager.default_timeout` [registry](Registry.md) value will be used.

## Event-queue management
### eventqueue
PBot uses an event queue to schedule future tasks or commands. The `eventqueue` command can
be used to list or remove upcoming events. It can also be used to schedule a command.

Usage: `eventqueue list [filter regex] | add <relative time> <command> [-repeat] | remove <event>`

For example, to schedule a command to run 1 hour from now:

    <pragma-> eventqueue add "1 hour" echo Ta-da!
       <PBot> Command added to event queue.

    <pragma-> eventqueue list
       <PBot> Queued events: 1) in 1h: command #channel echo Ta-da!

    ... 1 hour later ...

       <PBot> Ta-da!

The `remove` command's `<event>` argument can include wildcards. For example,
to remove all `command` events:

    <pragma-> eventqueue remove command *
       <PBot> Removed 1 event.

Or to remove all `command` events in `#channel`:

    <pragma-> eventqueue remove command #channel *

## Process-management
### ps
Lists all currently running background processes.

Usage: `Usage: ps [-atu]`

Option | Description
--- | ---
`-a` | show all information
`-t` | show running time
`-u` | show user and channel

### kill
Sends the interrupt signal to selected running background processes.

Usage: `Usage: kill [-a] [-t <seconds>] [-s <signal>] [pids...]`

Option | Description
--- | ---
`-a` | kill all processes
`-t <seconds>` | kill processes running longer than `<seconds>`
`-s <signal>` | send `<signal>` to processes instead of interrupt signal
`pids...` | space-delimited list of PIDs to kill

If neither options `-a` or `-t` are provided then the `pids...` option is required.

## Message-history/user-tracking
Message history has an advanced user tracking algorithm in order to ensure that
messages are being stored in the right message history accounts. The following commands
query and manipulate the message history account links.

Note that "message history account" and "PBot user account" are distinct accounts.

### recall
The `recall` command queries the message history and displays matching results.

Usage: `recall [nick [history [channel]]] [-c <channel>] [-t <text>] [-b <context before>] [-a <context after>] [-x <filter to nick>] [-n <count>] [-r raw mode] [+ ...]`

You can chain multiple recalls together with the `+` operator.

Option | Description
--- | ---
`-c <channel>` | Filter to messages only in `<channel>`
`-t <text>` | Filter to messages containing `<text>`
`-b <context before>` | Show `<context before>` (integral) count messages appearing immediately before matching messages
`-a <context after>` | Show `<context after>` (integral) count messages appearing immediately after matching messages
`-x <filter to nick>` | Filter messages to only those spoken by `<filter to nick>`
`-n <count>` | Limit results to `<count>` (integral); implies `-x`
`-r` | Show only the message without any nickname or timestamp prefixes

Examples:

    <pragma-> hello
       <garp> hi there
       <john> hey
    <pragma-> PBot: recall garp
       <PBot> [20s ago] <garp> hi there
     <pragma> PBot: recall garp -b1 -a1
       <PBot> [35s ago] <pragma-> hello [20s ago] <garp> hi there [10s ago] <john> hey
     <pragma> PBot: recall -t hey
       <PBot> [10s ago] <john> hey

### id
The `id` command lists various user-tracking and user-account metadata about a user hostmask.

Usage: `id [nickname | hostmask | message account id]`

If no argument is provided, your own id information will be shown. The `hostmask` form accepts wildcards.
The `message account id` form is an integer.

Examples:

    <pragma-> id
       <PBot> pragma- (pragma-!~chaos@user/pragmatic-chaos): user id: 2; user account: pragma- (logged in); NickServ: pragma-

    <pragma-> id pragma-
       <PBot> pragma- (pragma-!~chaos@user/pragmatic-chaos): user id: 2; user account: pragma- (logged in); NickServ: pragma-

    <pragma-> id 2
       <PBot> pragma- (pragma-!~chaos@user/pragmatic-chaos): user id: 2; user account: pragma- (logged in); NickServ: pragma-

    <pragma-> id *!*@*/pragmatic-chaos
       <PBot> pragma- (pragma-!~chaos@user/pragmatic-chaos): user id: 2; user account: pragma- (logged in); NickServ: pragma-

    <pragma-> id *!*@user/*
       <PBot> Multiple accounts found: PBot!pbot3@user/pbot (1), pragma-!~chaos@user/pragmatic-chaos (2), ...

### aka
The `aka` command lists all known aliases for a given message history account.

Usage: `aka [-hilngr] <nick> [-sort <by>]`

Option | Description
--- | ---
`-h` | show hostmasks
`-i` | show ids
`-l` | show last seen timestamps
`-n` | show nickserv accounts
`-g` | show gecos
`-r` | show relationships

Sort by | Description
--- | ---
`gecos`    | GECOS field
`host`     | host portion of hostmask
`hostmask` | hostmask
`id`       | account id
`nick`     | nick portion of hostmask
`nickserv` | NickServ account
`seen`     | last seen timestamp
`user`     | user portion of hostmask

Examples:

    <pragma-> aka bob
       <PBot> bob also known as: bob, bobby, robert

    <pragma-> aka -hl bob
       <PBot> bob also known as: bob!~bob@user/bob (seen 5m ago), bobby!~bob@user/bob (seen 6d ago), robert!~bob@127.0.0.1 (seen 20d ago)

### akalink
The `akalink` command manually links two message history accounts together.

Usage: `akalink <target id> <alias id> [type]`

The optional `type` argument can be `0` (weak) or `1` (strong). Defaults to `1`.

Use the [`id`](#id) command to look up message history account ids for a given hostmask.

### akaunlink
The `akaunlink` command manually unlinks two message history accounts from each other.

Usage: `akaunlink <target id> <alias id>`

Use the `-r` option with the `aka` command to see the `target -> alias` relationship.

### akadelete
The `akadelete` command deletes message history account metadata or entire message history accounts.

Usage: `akadelete [-hn] <account id or hostmask>`

Option | Description
--- | ---
`-h` | delete only hostmask
`-n` | delete only nickserv accounts

If neither options `-h` or `-n` are given, then the entire message history account will be deleted.

## Miscellaneous
These are some of the miscellaneous admin commands that have not been covered
above or in the rest of the PBot documentation.

### export
Exports specified list to HTML file in `$data_dir`.

Usage:  `export <factoids|quotegrabs>`

### refresh
Refreshes/reloads PBot core modules and plugins (not the command-line modules since those are executed/loaded each time they are invoked).

For example, suppose you edit some PBot source file, be it a core file such as PBot/Factoids.pm or
a Plugin such as Plugins/Wttr.pm. Rather than shut the bot down and restart it, you can simply use
the `refresh` command to reload all modified PBot core files and Plugins.

### reload
Reloads a data or configuration file from `$data_dir`. This is useful if you
manually edit a data or configuration file and you want PBot to know about the
modifications.

Usage `reload <admins|bantimeouts|blacklist|channels|factoids|funcs|ignores|mutetimeouts|registry>`

### sl
Sends a raw IRC command to the server. Use the `sl` command when
PBot does not have a built-in command to do what you need.

Usage: `sl <irc command>`

    <pragma-> sl PRIVMSG #channel :Test message
       <PBot> Test message

### die
Tells PBot to disconnect and exit.

