Administrative
--------------


<!-- md-toc-begin -->
  * [Administrative](#administrative)
    * [login](#login)
    * [logout](#logout)
    * [Admin Management](#admin-management)
      * [adminadd](#adminadd)
        * [Admin Levels](#admin-levels)
      * [adminrem](#adminrem)
      * [adminset](#adminset)
        * [Admin Metadata List](#admin-metadata-list)
      * [adminunset](#adminunset)
    * [ignore](#ignore)
    * [unignore](#unignore)
    * [whitelist](#whitelist)
    * [blacklist](#blacklist)
    * [ban](#ban)
    * [unban](#unban)
    * [kick](#kick)
    * [export](#export)
    * [refresh](#refresh)
    * [sl](#sl)
    * [die](#die)
<!-- md-toc-end -->


### login
You cannot use any of the admin commands unless you login first. Note that login requires that your hostmask matches PBot's records.

Usage:  `login <password>`

### logout
Logs out of PBot.

### Admin Management
#### adminadd
Adds a bot admin.

Usage: `adminadd <name> <channel> <hostmask> <level> <password>`

* `name`: a unique name to identify this account (usually the `nick` of the admin, but can be any identifier).

* `channel`: which channel the admin can administrate; use `global` for all channels. This field cannot be changed without removing and re-adding the admin.

* `hostmask`: a *regular expression* of what hostmask the admin is recognized/allowed to login from (e.g., `somenick!.*@.*.somedomain.com` or `.*@unaffiliated/someuser`). This field cannot be changed without removing and re-adding the admin.

* `level`: an integer representing their level of privileges. See [admin-levels](#Admin_Levels).

* `password`: the password the admin will use to login (from /msg!). A password is not required if the `stayloggedin` and `loggedin` meta-data are set for the admin; however, a dummy password still needs to be set.

##### Admin Levels
This is a list of admin commands allowed by each admin level. Higher level admins have access to all lower level admin commands.

* `10`: whitelist, blacklist, chanlist, ban, unban, mute, unmute, kick, ignore, unignore
* `40`: chanset, chanunset, chanadd, chanrem, join, part
* `60`: adminadd, adminrem, adminset, adminunset, akalink, akaunlink, regadd, regrem, regset, regunset, regchange
* `90`: sl, load, unload, export, rebuildaliases, refresh, die

#### adminrem
Removes a bot admin. You can use the name field or the hostmask field that was set via adminadd.

Usage: `adminrem <channel> <name/hostmask>`

#### adminset
Sets meta-data for an admin account. You can use the `name` field or the `hostmask` field that was set via `adminadd`. See also: [admin metadata list](#Admin_Metadata_List).

If `key` is omitted, it will list all the keys and values that are set.  If `value` is omitted, it will show the value for `key`.

Usage: `adminset <channel> <name/hostmask> [<key> [value]]`

##### Admin Metadata List
This is a list of recognized meta-data keys for admin accounts.

* `name`: A unique name identifying this admin account.
* `level`: The privilege level of the admin. See [admin levels](#Admin_Levels).
* `password`: The password for this admin account.
* `loggedin`: Whether the admin is logged in or not.
* `stayloggedin`: Do not log the admin out when they part/quit.

#### adminunset
Deletes a meta-data key from an admin account.  You can use the name `field` or the `hostmask` field that was set via adminadd.

Usage: `adminunset <channel> <name/hostmask> <key>`

### ignore
Ignore a user.

Usage: `ignore <hostmask regex> [channel [timeout]]`

Timeout can be specified as an relative time in English; for instance, `5 minutes`, `1 month and 2 weeks`, `next thursday`, `friday after next`, and so on.

### unignore
Unignores a user.

Usage:  `unignore <hostmask regex> [channel]`

### whitelist
Whitelists a hostmask to be exempt from ban evasions.

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

### ban
Bans a user. If the argument is a `nick` instead of a `hostmask`, it will determine an appropriate banmask for that nick.

Usage: `ban <nick or hostmask> [channel [timeout]]`

If `timeout` is omitted, PBot will ban the user for 24 hours. Timeout can be specified as an relative time in English; for instance, `5 minutes`, `1 month and 2 weeks`, `next thursday`, `friday after next`, and so on.

### unban
Unbans a user. If the argument is a `nick` instead of a `hostmask`, it will find all bans that match any of that nick's hostmasks or NickServ accounts and unban them.

Usage: `unban <nick or hostmask> [channel]`

### kick
Removes a user from the channel. `nick` can be a comma-separated list of multiple users. If `reason` is omitted, a random insult will be used.

Usage from channel:   `kick <nick> [reason]`
From private message: `kick <channel> <nick> [reason]`

### export
Exports specified list to website.

 Usage:  export `<commands|factoids|quotegrabs|admins|channels>`

### refresh
Refreshes/reloads PBot core modules and plugins (not the command-line modules since those are executed/loaded each time they are invoked).

### sl
Sends a raw IRC line to the server.

Usage: `sl <ird command>`

    <pragma-> sl PRIVMSG #channel :Test message
       <PBot> Test message

### die
Kills PBot. :-(  Causes PBot to disconnect and exit.

