# Administrative

<!-- md-toc-begin -->
* [Logging in and out](#logging-in-and-out)
  * [login](#login)
  * [logout](#logout)
* [User management commands](#user-management-commands)
  * [useradd](#useradd)
  * [userdel](#userdel)
    * [Admin levels](#admin-levels)
  * [userset](#userset)
  * [userunset](#userunset)
    * [User metadata list](#user-metadata-list)
  * [Listing users](#listing-users)
* [Channel management commands](#channel-management-commands)
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
  * [whitelist](#whitelist)
  * [blacklist](#blacklist)
  * [op](#op)
  * [deop](#deop)
  * [voice](#voice)
  * [devoice](#devoice)
  * [mode](#mode)
  * [ban/mute](#banmute)
  * [unban/unmute](#unbanunmute)
  * [invite](#invite)
  * [kick](#kick)
* [Module management commands](#module-management-commands)
  * [load](#load)
  * [unload](#unload)
  * [Listing modules](#listing-modules)
* [Plugin management commands](#plugin-management-commands)
  * [plug](#plug)
  * [unplug](#unplug)
  * [replug](#replug)
  * [pluglist](#pluglist)
* [Command metadata commands](#command-metadata-commands)
  * [cmdset](#cmdset)
  * [cmdunset](#cmdunset)
  * [Command metadata list](#command-metadata-list)
* [Miscellaneous commands](#miscellaneous-commands)
  * [export](#export)
  * [refresh](#refresh)
  * [reload](#reload)
  * [sl](#sl)
  * [die](#die)
<!-- md-toc-end -->

## Logging in and out
You cannot use any of the admin commands unless you login. Note that the [`login`](#login) command requires that your currently
connect IRC hostmask matches the hostmask configured for the user account.

You can keep your user account permanently logged in by setting a couple of [user metadata](#user-metadata-list) values. See
the [user metadatalist](#user-metadata-list) for more information.

### login
Logs into PBot.

Usage:  `login [channel] <password>`

### logout
Logs out of PBot.

Usage: `logout`

## User management commands
### useradd
Adds a new user to PBot.

Usage: `useradd <account name> <channel> <hostmask> [level] [password]`

Parameter | Description
--- | ---
`<account name>` | A unique name to identify this account (usually the `nick` of the user, but it can be any identifier).
`<channel>` | The channel this user belongs to; use `global` for all channels. This field cannot be changed without removing and re-adding the user.
`<hostmask>` | The hostmask from which this user is recognized/allowed to login from (e.g., `somenick!*@*.somedomain.com` or `*!*@unaffiliated/someuser`). This field cannot be changed without removing and re-adding the user.
`[level]` | An integer representing the user's level of privileges. See [admin-levels](#admin-levels). Defaults to `0` if omitted (i.e., a normal unprivileged user).
`[password]` | The password the user will use to login (from `/msg`, obviously). Generates a random password if omitted. Users may view and set their password by using the [`my`](Commands.md#my) command.

### userdel
Removes a user from PBot. You can use the `account name` field or the `hostmask` field that was set via the [`useradd`](#useradd) command.

Usage: `userdel <channel> <account name or hostmask>`

#### Admin levels
This is a list of admin commands allowed by each admin level, by default. You
can use [`cmdset`](#cmdset) to adjust any command's admin level.

Higher level admins have access to all lower level admin commands.

Note that Plugins may also add new admin commands, so this list may be incomplete
if you have third-party Plugins loaded.

Level | Commands
--- | ---
10 | actiontrigger, antispam, whitelist, blacklist, chanlist, ban, unban, mute, unmute, op, deop, voice, devoice, invite, kick, ignore, unignore
40 | chanset, chanunset, chanadd, chanrem, join, part, mode
60 | useradd, userdel, userset, userunset, akalink, akaunlink, regset, regunset, regsetmeta, regunsetmeta, regchange, dumpbans
90 | sl, plug, unplug, replug, load, unload, reload, export, rebuildaliases, refresh, die
99 | eval

### userset
Sets metadata for a user account. You can use the `account name` field or the `hostmask` field that was set via the [`useradd`](#useradd) command. See also: [user metadata list](#user-metadata-list).

If `key` is omitted, it will list all the keys and values that are set.  If `value` is omitted, it will show the value for `key`.

Usage: `userset <channel> <account name or hostmask> [<key> [value]]`

### userunset
Deletes a metadata key from a user account.  You can use the `account name` field or the `hostmask` field that was set via the [`adminadd`](#adminadd) command.

Usage: `userunset <channel> <account name or hostmask> <key>`

#### User metadata list
This is a list of recognized metadata keys for user accounts.

Name | Description
--- | ---
`name` | A unique name identifying the user account.
`level` | The privilege level of the user. See [admin levels](#admin-levels).
`password` | The password for the user account.
`loggedin` | Whether the user is logged in or not.
`stayloggedin` | Do not log the user out when they part/quit.
`autologin` | Automatically log the user in when they join the channel. *Note: make sure the user's hostmask wildcards are as restrictive as possible.*
`autoop` | Give the user `operator` status when they join the channel. *Note: make sure the admin's hostmask wildcards are as restrictive as possible.*
`autovoice` | Give the user `voiced` status when they join the channel. *Note: make sure the admin's hostmask wildcards are as restrictive as possible.*

### Listing users
To list user accounts, use the `list users` command. This is not an admin command, but
it is included here for completeness.

Usage: `list users [channel]`

When the optional `[channel]` argument is provided, only users for that channel
will be listed; no global users will be listed.

When `[channel]` is omitted and the command is used in a channel, it will list
the users for that channel, plus all global users.

When `[channel]` is omitted and the command is used from private message, it will
list all users from all channels, including global users.

## Channel management commands

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

### whitelist
Whitelists a hostmask regex to be exempt from ban evasions or anti-flood enforcement.

Usages:

- `whitelist <show/list>`
- `whitelist add <channel> <hostmask>`
- `whitelist remove <channel> <hostmask>`

### blacklist
Blacklists a hostmask regex from joining a channel.

Usages:

- `blacklist <show/list>`
- `blacklist add <hostmask regex> [channel]`
- `blacklist remove <hostmask regex> [channel]`

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
The argument can be a comma-separated list of multiple nicks or masks.

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

## Module management commands

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

## Plugin management commands

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
       <PBot> Loaded plugins: ActionTrigger, AntiAway, AntiKickAutoRejoin, AntiNickSpam, AntiRepeat, AntiTwitter, AutoRejoin, GoogleSearch, Quotegrabs, RemindMe, UrlTitles

## Command metadata commands

### cmdset
Use `cmdset` to set various [metadata](#command-metadata-list) for built-in commands.

Usage: `cmdset <command> [key [value]]`

Omit `<key>` and `<value>` to list all the keys and values for a command.  Specify `<key>`, but omit `<value>` to see the value for a specific key.

### cmdunset
Use `cmdset` to delete various [metadata](#command-metadata-list) from built-in commands.

Usage: `cmdunset <command> <key>`

### Command metadata list

Name | Description
--- | ---
`help` | The text to display for the [`help`](Commands.md#help) command.
`level` | The admin level of this command. See also [admin-levels](#admin-levels)

## Miscellaneous commands

These are some of the miscellaneous admin commands that have not been covered
above or in the rest of the PBot documentation.

### export
Exports specified list to HTML file in `$data_dir`.

Usage:  `export <factoids|quotegrabs>`

### refresh
Refreshes/reloads PBot core modules and plugins (not the command-line modules since those are executed/loaded each time they are invoked).

### reload
Reloads a data or configuration file from `$data_dir`. This is useful if you
manually edit a data or configuration file and you want PBot to know about the
modifications.

Usage `reload <admins|bantimeouts|blacklist|channels|factoids|funcs|ignores|mutetimeouts|registry|whitelist>`

### sl
Sends a raw IRC command to the server. Use the `sl` command when
PBot does not have a built-in command to do what you need.

Usage: `sl <irc command>`

    <pragma-> sl PRIVMSG #channel :Test message
       <PBot> Test message

### die
Tells PBot to disconnect and exit.

