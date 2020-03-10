# Registry

<!-- md-toc-begin -->
* [About](#about)
  * [Types of values](#types-of-values)
  * [Creating array values](#creating-array-values)
  * [Overriding Registry values per-channel](#overriding-registry-values-per-channel)
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
* [List of known Registry items](#list-of-known-registry-items)
  * [Channel-specific Registry items](#channel-specific-registry-items)
<!-- md-toc-end -->

## About
PBot's behavior can be customized via a central registry of key/value pairs segregated by sections.

These are represented as `<section>.<key>`. For example, `irc.port` is set to `6667` by default.

### Types of values
There are two types of registry values: literals and arrays.  Literals can be strings, floats or integers.  Arrays are comma-separated lists of literals.

### Creating array values
Use the [regsetmeta](#regsetmeta) command to change the `type` [metadata key](#metadata-list) to `array`, and set the registry value to a comma-separated list of values.

For example, we'll create a fictional Registry key `animals` in fictional section `foo` and then set its `type` to `array`.

    <pragma-> !regset foo.animals aardvark,badger,cat,dingo
       <PBot> foo.animals set to aardvark,badger,cat,dingo

    <pragma-> !regsetmeta foo.animals type array
       <PBot> foo.animals: 'type' set to 'array'

### Overriding Registry values per-channel
Some Registry items belonging to a specific section may be overridden on a per-channel basis by setting the item in a channel-specific section.

For example, the bot's trigger is defined in `general.trigger`. You may set a `trigger` registry item in section `#channel` to override the value for that channel: `#channel.trigger`.

## Overriding Registry values via command-line
You may override the Registry values via the PBot start-up command-line. These
overrides are not temporary; they will be saved.

    $ ./pbot data_dir=mybot irc.botnick=coolbot irc.server=freenode.net irc.port=6667

## Registry commands
### regset
`regset` sets a new registry item or updates an existing item.

Usage: `regset <section>.<item> <value>`

To override the trigger for #mychannel to `$`:

    <pragma-> !regset #mychannel.trigger $
       <PBot> #mychannel.trigger set to $

To override the trigger for #mychannel to be any of `,`, `!` or `%`, you can use
a character class:

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

To limit the search to a specific section, use `-section <section>`.

To dump the entire registry, use `regfind -showvalues .*`.

### regsetmeta
`regsetmeta` sets the metadata values for a specific registry key. See [registry metadata list](#metadata-list).

If you omit the `<key>` argument, it will list all the defined keys and values for the registry item.  If you specify `<key>` but omit `<value>`, it will show the value for that specific key.

Usage: `regsetmeta <section>.<item> [key [value]]`

For example, this directly sets the `value` metadata key of `irc.botnick`.

     <pragma-> !regsetmeta irc.botnick value candide
             * PBot changed nick to candide
     <candide> irc.botnick: 'value' set to 'candide'

That example is equivalent to `regset irc.botnick candide`.

### regunsetmeta
`regunset` deletes a metadata key from a registry item.

Usage: `regunset <section>.<item> <key>`

## Editing Registry file
You may edit the Registry file manually. It is located as [`$data_dir/registry`](../data/registry). Its
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
This is a list of recognized registry metadata keys.

Name | Description
--- | ---
`type` | Sets the type of the registry item; values can be `text` (literal) or `array`.
`value` | The value of the registry item.
`private` | Whether the value of the registry item is displayed in the `regset`, `regshow` or `regfind` commands. If set to a true value, the value of the registry key will be shown as `<private>`.

## List of known Registry items
This is a list of recognized registry items at the time of this writing.

Name | Description | Default value
--- | --- | ---
antiaway.bad_actions | If a message matches against this regex, it is considered an Away action. | `^/me (is (away\|gone)\|.*auto.?away)`
antiaway.bad_nicks | If someone changes their nick and the new nick matches this regex, it is considered an Away nick. | `(^z+[[:punct:]]\|`<br/>`[[:punct:]](afk\|brb\|bbl\|away\|sleep\|asleep\|nap\|`<br/>`z+\|work\|gone\|study\|out\|home\|busy\|off)`<br/>`[[:punct:]]*$\|afk$)`
antiaway.kick_msg | The message to use when kicking Away offenders. | http://sackheads.org/~bnaylor/spew/away_msgs.html
antiflood.chat_flood_punishment | The amount of time, in seconds, offenders will be muted/banned. | 60,300,3600,86400,604800,2419200
antiflood.chat_flood_threshold | The number of messages before this is considered a flood. | 4
antiflood.chat_flood_time_threshold | `chat_flood_threshold` number of messages within this amount of seconds will be considered a flood. | 5
antiflood.debug_checkban | Print verbose debugging information about the `checkban` function. | 0
antiflood.dont_enforce_admins | Do not enforce anti-flood detection against logged-in admins. | 1
antiflood.enforce | If set to a true value, anti-flood will be enforced. | 1
antiflood.enter_abuse_max_offenses | | 3
antiflood.enter_abuse_punishment || 60,300,3600,86400,604800,2419200
antiflood.enter_abuse_threshold || 4
antiflood.enter_abuse_time_threshold || 15
antiflood.join_flood_punishment || 115200,3600,10800,604800
antiflood.join_flood_threshold || 4
antiflood.join_flood_time_threshold || 1800
antiflood.nick_flood_punishment || 1800,3600,86400,604800
antiflood.nick_flood_threshold || 3
antiflood.nick_flood_time_threshold || 1800
antikickautorejoin.punishment || 300,900,1800,3600,28800
antikickautorejoin.threshold || 4
autorejoin.rejoin_delay | Delay before rejoining a channel after being kicked or requested to leave. | 900,1800,3600
bantracker.chanserv_ban_timeout || 604800
bantracker.debug | Log verbose debugging information about the Ban Tracker. | 0
bantracker.mute_timeout || 604800
battleship.channel | Sets the channel for the Battleship game plugin. | ##battleship
connect4.channel | Sets the channel for the Connect4 game plugin. | ##connect4
factoids.default_rate_limit | The default rate-limit to set when creating new factoids. | 10
factoids.max_channel_length | The maximum length the channel field can be. | 20
factoids.max_content_length | The maximum length the content field can be. | 8192
factoids.max_name_length | The maximum length the name field can be. | 100
factoids.max_undos | Maximum undo history entries. | 20
general.data_dir | Path to PBot `data/` directory. |
general.daemon | Run PBot in daemon mode. Closes stdin and stdout, writes only to logfile. | 0
general.deop_timeout | Time-out, in seconds, before PBot deops itself after being opped. | 300
general.default_ban_timeout | Default timeout for bans. | 24 hours
general.default_mute_timeout | Default timeout for mutes. | 24 hours
general.module_dir | Path to PBot `modules/` directory. |
general.module_repo | URL to source code of PBot modules; used in `factinfo` | https://github.com/pragma-/pbot/tree/master/modules
general.no_dehighlight_nicks | If set to at true value then  when outputting text PBot will not convert nicks to text that avoids triggering IRC client nick-highlighting | not defined
general.paste_ratelimit | How often, in seconds, between pastes to web paste-sites. |
general.send_who_on_join | When joining a channel, send the `WHO` command to get detailed information about who is present, and to check for ban-evasions. | 1
general.show_url_titles_channels | A regular-expression or comma-separated list of channels that should display titles for URLs. | `.*`
general.show_url_titles | If set to a true value, PBot will show titles for URLs. | 1
general.show_url_titles_ignore_channels | A regular-expression or comma-separated list of channels that will not display titles for URLs. |
general.trigger | The trigger character(s) or text that will invoke PBot commands. | [!]
interpreter.max_recursion | The maximum number of recursions allowed before the command interpreter will abort. | 100
irc.botnick | The IRC nickname of this PBot instance. |
irc.debug | Log verbose debugging information about the IRC engine. | 0
irc.identify_password | The password to identify to NickServ or other service bots. |
irc.server | The IRC server network address to connect to. | irc.freenode.net
irc.log_default_handler | If set to a true value, any IRC events that are not explicitly handled by PBot will be dumped to the log. | 1
irc.max_msg_len | The maximum length messages can be on this IRC server. | 425
irc.port | The IRC server network port to connect to. | 6667
irc.realname || https://github.com/pragma-/pbot
irc.show_motd | If set to a true value, the IRC server MOTD will be shown when connecting. | 1
irc.SSL_ca_file | Path to a specific SSL certificate authority file. |
irc.SSL_ca_path | Path to the SSL certificate authority directory containing certificate files. |
irc.SSL | If set to a true value, SSL will be enabled when connecting to the IRC server. | 0
irc.username || PBot
interpreter.max_recursion | Maximum recursion depth for bot command aliasing. | 10
lagchecker.lag_history_interval | How often, in seconds, to send a `PING` to the IRC server. | 10
lagchecker.lag_history_max | How many of the most recent `PING`s to average. | 3
lagchecker.lag_threshold | Duration, in milliseconds, of average lag before PBot thinks it is lagging too much to sensibly enforce anti-flood, etc. | 2000
messagehistory.debug_aka | Log verbose debugging information about the `aka` command. | 0
messagehistory.debug_link | Log verbose debugging information about account linking. | 0
messagehistory.sqlite_commit_interval | How often to commit SQLite transactions to the database. |
messagehistory.sqlite_debug | Log verbose debugging information about SQLite statements. | 0
nicklist.debug | Log verbose debugging information about the NickList. | 0
processmanager.default_timeout | The default timeout for background processes, in seconds. | 30
spinach.channel | Sets the channel for the Spinach game plugin. | ##spinach
typosub.ignore_commands | Do not apply `s//` substitution to bot commands.

### Channel-specific Registry items

All of above section-specific registry items can be overriden on a per-channel
basis if it makes sense for it to be able to do so.

However, some items exist only as a channel-specific item. You must [`regset`](#regset)
these for your channels. They are listed here.

Name | Description
--- | ---
[channel].default_ban_timeout | Overrides general.default_ban_timeout for this channel.
[channel].default_mute_timeout | Overrides general.default_mute_timeout for this channel.
[channel].dont_enforce_antiflood | Disables anti-flood enforcement for this channel.
[channel].max_newlines | The maximum number of lines to be sent before truncating to a paste site, if `preserve_newlines` is enabled.
[channel].no_url_titles | Disables display of URL titles for this channel.
[channel].notyposubs | Disables use of `s//` substitution to edit messages.
[channel].preserve_newlines | If set to a true value, newlines will not be replaced with spaces in this channel. Each line of output will be sent as a distinct message.
[channel].ratelimit_override | Duration, in seconds, of the rate-limit for factoids in this channel. To disable factoid rate-limiting for a channel, you can set this to `0`.
[channel].rejoin_delay | Overrides autorejoin.rejoin_delay for this channel.
[channel].strictnamespace | When enabled, factoids belonging to other channels will not show up in this channel unless specifically invoked.
[channel].trigger | Overrides the bot trigger for this channel.
[channel].typosub_ignore_commands | Do not apply `s//` substitution to bot commands.
