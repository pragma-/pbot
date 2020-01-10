Registry
========

<!-- md-toc-begin -->
  * [About](#about)
    * [Types of values](#types-of-values)
    * [Creating array values](#creating-array-values)
    * [Overriding registry values per-channel](#overriding-registry-values-per-channel)
  * [Overriding Registry values via command-line](#overriding-registry-values-via-command-line)
  * [Registry commands](#registry-commands)
    * [regset](#regset)
    * [regunset](#regunset)
    * [regchange](#regchange)
    * [regshow](#regshow)
    * [regfind](#regfind)
    * [regsetmeta](#regsetmeta)
    * [regunsetmeta](#regunsetmeta)
  * [Editing Registry file](#editing-registry-file)
  * [Metadata list](#metadata-list)
  * [List of known registry items](#list-of-known-registry-items)
<!-- md-toc-end -->

## About
PBot's behavior can be customized via a central registry of key/value pairs segregated by sections.

### Types of values
There are two types of registry values: literals and arrays.  Literals can be strings, floats or integers.  Arrays are comma-separated lists of literals.

### Creating array values
Use the [regsetmeta](#regsetmeta) command to change the `type` [meta-data key](#metadata-list) to `array`, and set the registry value to a comma-separated list of values.

    <pragma-> !regset foo.animals aardvark, badger, cat, dingo
       <PBot> foo.animals set to aardvark, badger, cat, dingo

    <pragma-> !regsetmeta foo.animals type array
       <PBot> foo.animals: 'type' set to 'array'

### Overriding registry values per-channel
Some key/value pairs belonging to a specific section may be overridden on a per-channel basis by setting the key/value in a channel-specific section.

For example, the bot's trigger is defined in `general.trigger`. You may add a `trigger` registry item in `#channel` to override the value for that channel: `#channel.trigger`.

## Overriding Registry values via command-line
You may override the Registry values via the PBot start-up command-line. Such
overrides are permanent and will be saved.

    $ ./pbot data_dir=mybot irc.botnick=coolbot irc.server=freenode.net irc.port=6667

## Registry commands
### regset
`regset` sets a new registry item or updates an existing item.

Usage: `regset <section>.<item> <value>`

For example, to override the trigger for #mychannel to be any of `,`, `!` or `%`:

    <pragma> !regset #mychannel.trigger [,!%]
      <PBot> #mychannel.trigger set to [,!%]

### regunset
`regunset` removes a registry item from a specific section/channel.

Usage: `regunset <section>.<item>`

### regchange
`regchange` changes the value of a registry item using a *regular substitution expression*.

Usage: `regchange <section>.<item> s/<pattern>/<replacement>/`

    <pragma-> regset foo.bar Hello, world!
       <PBot> foo.bar set to Hello, world!

    <pragma-> regchange foo.bar s/world/universe/
       <PBot> foo.bar set to Hello, universe!

### regshow
`regshow` displays the type and value of a registry item.

Usage: `regshow <section>.<item>`

    <pragma-> !regshow antiflood.chat_flood_punishment
       <PBot> antiflood.chat_flood_punishment: 60,300,3600,86400,604800,2419200 [array]

### regfind
`regfind` searches for registry items, and may optionally show the values of all matching items.

Usage: `regfind [-showvalues] [-section <section>] <regex>`

To limit the search to a specific section, use `-section <section>`. To dump the entire registry, use `regfind -showvalues .*`

### regsetmeta
`regsetmeta` sets the meta-data values for a specific registry key. See [registry meta-data list](#metadata-list).

If you omit the `<key>` argument, it will list all the defined keys and values for the registry item.  If you specify `<key>` but omit `<value>`, it will show the value for that specific key.

Usage: `regsetmeta <section>.<item> [key [value]]`

For example, this directly sets the `value` meta-data key of `irc.botnick`.

     <pragma-> !regsetmeta irc.botnick value candide
             * PBot changed nick to candide
     <candide> irc.botnick: 'value' set to 'candide'

That example is equivalent to `regset irc.botnick candide`.

### regunsetmeta
`regunset` deletes a meta-data key from a registry item.

Usage: `regunset <section>.<item> <key>`

## Editing Registry file
You may edit the Registry file manually. It is located as `$data_dir/registry`. Its
contents are plain-text JSON.

This is a sample entry:

    "irc" : {
      "botnick" : {
         "type" : "text",
         "value" : "PBot"
      }
    }

After editing an entry in the Registry file, you may reload it with the `reload` command.

    <pragma-> !reload registry
       <PBot> Registry reloaded.

## Metadata list
This is a list of recognized registry meta-data keys.

Name | Description
--- | ---
`type` | Sets the type of the registry item; values can be `text` (literal) or `array`.
`value` | The value of the registry item.
`private` | Whether the value of the registry item is displayed in the `regset`, `regshow` or `regfind` commands. If set to a true value, the value of the registry key will be shown as `**\<private\>**`.

## List of known registry items
This is a list of recognized registry items at the time of this writing.

Name | Description | Default value
--- | --- | ---
antiaway.bad_actions | If a message matches against this regex, it is considered an Away action. |
antiaway.bad_nicks | If a user changes their nick and the new nick matches this regex, it is considered an Away nick. |
antiaway.kick_msg | The message to use when kicking Away offenders. |
antiflood.chat_flood_punishment ||
antiflood.chat_flood_threshold ||
antiflood.chat_flood_time_threshold ||
antiflood.debug_checkban ||
antiflood.dont_enforce_admins ||
antiflood.enforce ||
antiflood.enter_abuse_max_offenses ||
antiflood.enter_abuse_punishment ||
antiflood.enter_abuse_threshold ||
antiflood.enter_abuse_time_threshold ||
antiflood.join_flood_punishment ||
antiflood.join_flood_threshold ||
antiflood.join_flood_time_threshold ||
antiflood.nick_flood_punishment ||
antiflood.nick_flood_threshold ||
antiflood.nick_flood_time_threshold ||
antikickautorejoin.punishment ||
antikickautorejoin.threshold ||
bantracker.chanserv_ban_timeout ||
bantracker.debug ||
bantracker.mute_timeout ||
factoids.default_rate_limit ||
general.compile_blocks_channels ||
general.compile_blocks ||
general.compile_blocks_ignore_channels ||
general.config_dir ||
general.data_dir ||
general.deop_timeout ||
general.module_dir ||
general.module_repo ||
general.paste_ratelimit ||
general.show_url_titles_channels ||
general.show_url_titles ||
general.show_url_titles_ignore_channels ||
general.trigger ||
interpreter.max_recursion ||
irc.botnick ||
irc.debug ||
irc.identify_password ||
irc.server ||
irc.log_default_handler ||
irc.max_msg_len ||
irc.port ||
irc.realname ||
irc.show_motd ||
irc.SSL_ca_file ||
irc.SSL_ca_path ||
irc.SSL ||
irc.username ||
lagchecker.lag_history_interval ||
lagchecker.lag_history_max ||
lagchecker.lag_threshold ||
messagehistory.debug_aka ||
messagehistory.debug_link ||
messagehistory.max_messages ||
messagehistory.sqlite_commit_interval ||
messagehistory.sqlite_debug ||
nicklist.debug ||

Some items only exist as a channel-specific item.

Name | Description | Default value
--- | --- | ---
[channel].dont_enforce_antiflood ||
[channel].max_newlines ||
[channel].no_url_titles ||
[channel].no_compile_blocks ||
[channel].preserve_newlines ||

