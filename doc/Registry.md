Registry
========
PBot's behavior can be customized via a central registry of key/value pairs segregated by sections.


<!-- md-toc-begin -->
* [Registry](#registry)
  * [Overriding registry values per-channel](#overriding-registry-values-per-channel)
  * [regadd](#regadd)
  * [regrem](#regrem)
  * [regshow](#regshow)
  * [regset](#regset)
    * [Registry metadata list](#registry-metadata-list)
  * [regunset](#regunset)
  * [regchange](#regchange)
  * [regfind](#regfind)
  * [Creating array values](#creating-array-values)
  * [List of recognized registry items](#list-of-recognized-registry-items)
<!-- md-toc-end -->


There are two types of registry values: literals and arrays.  Literals can be strings, floats or integers.  Arrays are comma-separated lists of literals.

Overriding registry values per-channel
--------------------------------------
Some key/value pairs belonging to a specific section may be overridden on a per-channel basis by setting the key/value in a channel-specific section.

For example, the bot's trigger is defined in `general.trigger`. You may add a trigger key in `#channel` to override the trigger value for that channel: `#channel.trigger`.

For another example, the anti-flood max lines is defined in `antiflood.chat_flood_threshold`. To override this setting in `#neatchannel`, you can set `#neatchannel.chat_flood_threshold`.

regadd
------
`regadd` adds a new registry value to a specific section/channel.

Usage: `regadd <section> <key> <value>`

For example, to override the trigger for #mychannel to be any of `,`, `!` or `%`:

    <pragma> regadd #mychannel trigger [,!%]
      <PBot> [#mychannel] trigger set to [,!%]

Some registry values can be *regular expressions*, like the above trigger example.  Setting `general.trigger` to the character class `[,!%]` means that it will respond to `,` `!` and `%` as trigger characters on a general basis.

regrem
------
`regrem` removes a registry key from a specific section/channel.

Usage: `regrem <section> <key>`

regshow
-------
`regshow` displays the type and value of a specific key.

Usage: `regshow <section> <key>`

    <pragma> regshow antiflood chat_flood_punishment
      <PBot> [antiflood] chat_flood_punishment: 60,300,3600,86400,604800,2419200 [array]

regset
------
`regset` sets the meta-data values for a specific registry key. See [registry meta-data list](#Registry_metadata_list).

If you omit the `<key>` argument, it will list all the defined keys and values for the registry item.  If you specify `<key>` but omit `<value>`, it will show the value for that specific key.

Usage: `regset <section> <item> [key [value]]`

     <pragma> regset irc botnick value pangloss
            * PBot changed nick to pangloss
    <pangloss> [irc] botnick: 'value' set to 'pangloss'

### Registry metadata list
This is a list of recognized registry meta-data keys.

* `type`: sets the type of this registry key; values can be `text` (literal) or `array`.
* `value`: the value of this registry key.
* `private`: whether the value of the registry key is displayed in regset, regshow or regfind. If set to a true value, the value of the registry key will be shown as "**\<private\>**".

regunset
--------
`regunset` deletes a meta-data key from a registry key.

Usage: `regunset <section> <item> <key>`

regchange
---------
`regchange` changes the value of a registry item using a *regular substitution expression*.

Usage: `regchange <section> <item> s/<pattern>/<replacement>/`

    <pragma> regadd foo bar Hello, world!
      <PBot> [foo] bar set to Hello, world!
    <pragma> regchange foo bar s/world/universe/
      <PBot> [foo] bar set to Hello, universe!

regfind
-------
`regfind` searches for registry items, and may optionally show the values of all matching items.

Usage: `regfind [-showvalues] [-section <section>] <regex>`

To limit the search to a specific section, use `-section <section>`. To dump the entire registry, use `regfind -showvalues .*`

Creating array values
---------------------
Use the [regset](#regset) command to change the `type` meta-data value to "array", and set the registry value to a comma-separated list of values.

    <pragma> regadd foo animals aardvark, badger, cat, dingo
      <PBot> [foo] animals set to aardvark, badger, cat, dingo
    <pragma> regset foo animals type array
      <PBot> [foo] animals: 'type' set to 'array'

List of recognized registry items
---------------------------------

* antiaway.bad_actions
* antiaway.bad_nicks
* antiaway.kick_msg
* antiflood.chat_flood_punishment
* antiflood.chat_flood_threshold
* antiflood.chat_flood_time_threshold
* antiflood.debug_checkban
* antiflood.dont_enforce_admins
* antiflood.enforce
* antiflood.enter_abuse_max_offenses
* antiflood.enter_abuse_punishment
* antiflood.enter_abuse_threshold
* antiflood.enter_abuse_time_threshold
* antiflood.join_flood_punishment
* antiflood.join_flood_threshold
* antiflood.join_flood_time_threshold
* antiflood.nick_flood_punishment
* antiflood.nick_flood_threshold
* antiflood.nick_flood_time_threshold
* antikickautorejoin.punishment
* antikickautorejoin.threshold
* bantracker.chanserv_ban_timeout
* bantracker.debug
* bantracker.mute_timeout
* factoids.default_rate_limit
* general.compile_blocks_channels
* general.compile_blocks
* general.compile_blocks_ignore_channels
* general.config_dir
* general.data_dir
* general.deop_timeout
* general.module_dir
* general.module_repo
* general.paste_ratelimit
* general.show_url_titles_channels
* general.show_url_titles
* general.show_url_titles_ignore_channels
* general.trigger
* interpreter.max_recursion
* irc.botnick
* irc.debug
* irc.identify_password
* irc.server
* irc.log_default_handler
* irc.max_msg_len
* irc.port
* irc.realname
* irc.show_motd
* irc.SSL_ca_file
* irc.SSL_ca_path
* irc.SSL
* irc.username
* lagchecker.lag_history_interval
* lagchecker.lag_history_max
* lagchecker.lag_threshold
* messagehistory.debug_aka
* messagehistory.debug_link
* messagehistory.max_messages
* messagehistory.sqlite_commit_interval
* messagehistory.sqlite_debug
* nicklist.debug
* [channel].dont_enforce_antiflood
* [channel].max_newlines
* [channel].no_url_titles
* [channel].no_compile_blocks
* [channel].preserve_newlines

