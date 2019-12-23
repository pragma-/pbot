PBot
====

About PBot
----------
PBot is an IRC bot written in Perl in pragma-'s spare time.

### Source
PBot's source may be found at these repositories:

 * [https://github.com/pragma-/pbot](https://github.com/pragma-/pbot)
 * [https://bitbucket.org/pragmasoft/pbot/src](https://bitbucket.org/pragmasoft/pbot/src)

The URL for the source of any loaded modules may be found by using the [factinfo](#factinfo) command:

    <pragma-> factinfo ##c faq
       <PBot> faq: Module loaded by pragma- on Fri Dec 31 02:34:04 2004 -> https://github.com/pragma-/pbot/blob/master/modules/cfaq.pl, used 512 times (last by ecrane)

### Bot Channel
You may test/play with PBot in the `#pbot2` channel on `irc.freenode.net`.

Trigger
-------
All of PBot's commands may begin with its name or its trigger, or be followed by its name.

The trigger character defaults to exclaimation mark `!`.

Note that commands need not be submitted to the channel; you can /msg it instead.  If you /msg PBot, it will respond with a private message in return.  In private message, you do not need to specify its name or one of the trigger symbols.

    <pragma-> !hi
    <pragma-> hi, PBot
    <pragma-> PBot: hi

### Embedded trigger
Many commands may be triggered from within a sentence by adding curly braces or backticks around the command after the trigger.  You can embed up to three commands in one message.

If the sentence begins with a nick that is currently in the channel, the command's response will be prefixed with that nick.

    <pragma-> Alice: Check out !{K&R} for a good book on C.  !`H&S` is also a great reference manual.
       <PBot> Alice: K&R is The C Programming Language, 2nd edition, by Kernighan and Ritchie - http://wayback.archive-it.org/5263/20150203070038/http://cm.bell-labs.com/cm/cs/cbook/ - errata: http://www.iso-9899.info/2ediffs.html
       <PBot> Alice: H&S is "C - A Reference Manual" by Harbison & Steele; a reference for C on par with K&R - http://www.amazon.com/Reference-Manual-Samuel-P-Harbison/dp/013089592X

### Directing output to a user
There are several ways to direct PBot to prepend the nickname of a specific person to a command in a channel.

You may state the nickname after the command (if the command doesn't take arguments):

    <pragma-> PBot: version defrost
       <PBot> defrost: PBot revision 387 2012-10-07

You may prefix a command with the nickname:

    <pragma-> randomjoe: !help cjeopardy
       <PBot> randomjoe: To learn all about cjeopardy, see http://www.iso-9899.info/wiki/PBot#cjeopardy

You may use [embedded command triggering](#Embedded_trigger) in a message addressed at a nickname:

    <pragma-> randomjoe: PBot is at !{version}, to learn more check out its !{help} page
       <PBot> randomjoe: PBot revision 387 2012-10-07
       <PBot> randomjoe: To learn all about me, see http://www.iso-9899.info/wiki/PBot

#### tell
You may use the `tell <nick> about <command>` syntax:

    <pragma-> PBot: tell defrost about help cc
       <PBot> defrost: To learn all about cc, see http://www.iso-9899.info/wiki/PBot#cc

Registry
========
PBot's behavior can be customized via a central registry of key/value pairs segregated by sections.

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
* irc.ircname
* irc.ircserver
* irc.log_default_handler
* irc.max_msg_len
* irc.port
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

Factoids
========

### Channel namespaces
Factoids added in one channel may be called/triggered in another channel or in private message, providing that the other channel doesn't already have a factoid of the same name (in which case that channel's factoid will be triggered).

Factoids may also be added to a special channel named `global` or `.*`.  Factoids that are set in this channel will be accessible to any channel, including private messages.  However, factoids that are set in a specific channel will override factoids of the same name that are set in the global channel or other channels.

For example, a factoid named `malloc` set in `##c` will be called instead of `malloc` set in `global`, if the factoid were triggered in `##c`; otherwise, the latter 'malloc' will be triggered if the factoid were triggered in another channel.

Similiarily, if there were no `malloc` factoid in the `global` namespace, but only in `##c` and you attempted to use this factoid in a channel other than `##c`, that channel will invoke `##c`'s version of `malloc`, providing that channel doesn't have its own `malloc` factoid.

Likewise, if there is a `malloc` factoid set in `##c++` and the factoid is triggered in the `##c++` channel, then this version of `malloc` will be called instead of the `##c` or the `global` factoid.

However, if you are in a channel that doesn't have a `malloc` factoid and there is no `malloc` factoid in the global channel, and you attempt to call `malloc` then the bot will display a message notifying you that `malloc` is ambiguous and which channels it belongs to so that you may use the [fact](#fact) command to call the correct factoid.

Adding a factoid
----------------
### factadd
Usage: `factadd [channel] <keyword> <description>`

To add a factoid to the global channel, use `global` or `.*` as the channel.  `.*` is regex-speak for "everything".

    <pragma-> factadd ##c c /say C rocks!

### Special commands
#### /say
If a factoid begins with `/say ` then PBot will not use the `<factoid> is <description>` format when displaying the factoid.

    <pragma-> factadd global hi /say Well, hello there, $nick.
       <PBot> 'hi' added to the global channel
       <prec> PBot, hi
       <PBot> Well, hello there, prec.

#### /me
If a factoid begins with `/me ` then PBot will ACTION the factoid.

    <pragma-> factadd global bounce /me bounces around.
       <PBot> 'bounce' added to the global channel
    <pragma-> bounce
            * PBot bounces around.

#### /call
If a factoid begins with `/call ` then PBot will call an existing command.

    <pragma-> factadd global boing /call bounce
       <PBot> 'boing' added to the global channel
    <pragma-> boing
            * PBot bounces around.

#### /msg
If a factoid begins with `msg <nick> ` then PBot will /MSG the factoid text to <nick>

### Special variables
You can use the following variables in a factoid or as an argument to one.

#### $nick
`$nick` expands to the nick of the caller.

#### $args
`$args` expands to any text following the keyword.  If there is no text then it expands to the nick of the caller.

#### $arg[n]
`$arg[n]` expands to the nth argument. Indexing begins from 0 (the first argument is `$arg[0]`).  You may use a negative number to count from the end; e.g., `$arg[-2]` means the 2nd argument from the end. Multiple words can be double-quoted to constitute one argument. If the argument does not exist, the variable and the leading space before it will be silently removed.

#### $arg[n:m]
`$arg[n:m]` expands to a slice of arguments between `n` and `m`.  Indexing begins from 0 (the first argument is `$arg[0]`).  Not specifying the `m` value means the rest of the arguments; e.g., `$arg[2:]` means the remaining arguments after the first two.  Multiple words can be double-quoted to constitute one argument. If the argument does not exist, the variable and the leading space before it will be silently removed.

#### $arglen
`$arglen` expands to the number of arguments provided to a factoid.

#### $channel
`$channel` expands to the name of the channel in which the factoid is used.

#### $randomnick
`$randomnick` expands to a random nick from the channel in which the factoid is used.

#### $0
`$0` expands to the original keyword used to invoke a factoid. See also [Overriding $0](#Overriding_$0).

### adlib list variables
You may create a list of adlib words by using the normal factoid creation method. Multiple words can be surrounded with quotes to constitute one element.

    <pragma-> factadd global colors is red green blue "bright yellow" pink "dark purple" orange
        <PBot> colors added to the global channel

Then you can instruct PBot to pick a random word from this list to use in another factoid by inserting the list as a variable.

    <pragma-> factadd global sky is /say The sky is $colors.
       <PBot> sky added to the global channel
    <pragma-> sky
       <PBot> The sky is dark purple.
    <pragma-> sky
       <PBot> The sky is green.

A practical example, creating the RTFM trigger:

    <pragma-> factadd global sizes is big large tiny small huge gigantic teeny
       <PBot> 'sizes' added to the global channel
    <pragma-> factadd global attacks is whaps thwacks bashes smacks punts whacks
       <PBot> 'attacks' added to the global channel
    <pragma-> factadd global rtfm is /me $attacks $args with a $sizes $colors manual.
       <PBot> 'rtfm' added to the global channel
    <pragma-> rtfm mauke
            * PBot thwacks mauke with a big red manual.

#### modifiers
Adlib list variables can accept trailing modifier keywords prefixed with a colon.  These can be chained together to combine their effects.

* `:uc` - uppercases the expansion
* `:lc` - lowercases the expansion
* `:ucfirst` - uppercases the first letter in the expansion
* `:title` - lowercases the expansion and then uppercases the initial letter of each word
* `:<channel>` - looks for variable in `<channel>` first; use `global` to refer to the global channel


    <pragma-> echo $colors:uc
       <PBot> RED
    <pragma-> echo $colors:ucfirst
       <PBot> Blue

### code-factoids
Code-factoids are a special type of factoid whose text is executed as Perl instructions. The return value from these instructions is the final text of the factoid. This final text is then parsed and treated like any other factoid text.

By default, the variables created within code-factoids do not persist between factoid invocations. This behavior can be overridden by factsetting a persist-key with a unique value.

To create a code-factoid, simply wrap the factoid text with curly braces.

    factadd keyword { code here }

#### Special variables

There are some special variables available to code-factoids.

* `@args` - any arguments passed to the factoid (note that invoker's nick is passed if no arguments are specified)
* `$nick` - nick of the person invoking the factoid
* `$channel` - channel in which the factoid is being invoked

#### testargs example

    <pragma-> factadd global testargs { return "/say No arguments!" if not @args;
              if (@args == 1) { return "/say One argument: $args[0]!" } elsif
              (@args == 2) { return "/say Two arguments: $args[0] and $args[1]!"; }
              my $results = join ', ', @args; return "/say $results"; }
       <PBot> testargs added to the global channel.
    <pragma-> testargs
       <PBot> One argument: pragma-!
    <pragma-> testargs "abc 123" xyz
       <PBot> Two arguments: abc 123 and xyz!

#### rtfm example

Remember that `rtfm` factoid from earlier? Let's modify it so that it doesn't attack Zhivago.

    <pragma-> forget rtfm
       <PBot> rtfm removed from the global channel.
    <pragma-> factadd global rtfm { return "/say Nonsense! Zhivago is a gentleman and
              a scholar." if $nick eq "Zhivago" or "@args" =~ /zhivago/i; return "/me
              $attacks $args[0] with a $sizes $colors manual." }
       <PBot> rtfm added to the global channel.
    <pragma-> rtfm luser
            * PBot smacks luser with a huge blue manual.
    <pragma-> rtfm Zhivago
       <PBot> Nonsense! Zhivago is a gentleman and a scholar.

#### poll example

An extremely basic aye/nay poll system. All code-factoids sharing the same persist-key will share the same persisted variables.

First we add the factoids:

    <pragma-> factadd global startpoll { %aye = (); %nay = (); $question = "@args";
              "/say Starting poll: $question" }
       <PBot> startpoll added to the global channel.
    <pragma-> factadd global aye { $aye{$nick} = 1; delete $nay{$nick}; "" }
       <PBot> aye added to the global channel.
    <pragma-> factadd global nay { $nay{$nick} = 1; delete $aye{$nick}; "" }
       <PBot> nay added to the global channel.
    <pragma-> factadd global pollresults { $ayes = keys %aye; $nays = keys %nay;
              "/say Results for poll \"$question\": ayes: $ayes, nays: $nays" }
       <PBot> pollresults added to the global channel.

Then we set their persist-key to the same value:

    <pragma-> factset global startpoll persist-key pragma-poll
       <PBot> [global] startpoll: 'persist-key' set to 'pragma-poll'
    <pragma-> factset global aye persist-key pragma-poll
       <PBot> [global] aye: 'persist-key' set to 'pragma-poll'
    <pragma-> factset global nay persist-key pragma-poll
       <PBot> [global] nay: 'persist-key' set to 'pragma-poll'
    <pragma-> factset global pollresults persist-key pragma-poll
       <PBot> [global] pollresults: 'persist-key' set to 'pragma-poll'

And action:

    <pragma-> startpoll Isn't this cool?
       <PBot> Starting poll: Isn't this cool?
    <pragma-> aye
    <luser69> nay
    <someguy> aye
    <pragma-> pollresults
       <PBot> Results for poll "Isn't this cool?": ayes: 2, nays: 1

* Exercise for the reader: extend this poll system to be per-channel using `$channel`.

* Experts: extend this to use a `vote <keyword>` factoid, and adjust `pollresults` to show a tally for each keyword.

### action_with_args

You can use the [factset](#factset) command to set a special factoid meta-data key named `action_with_args` to trigger an alternate message if an argument has been supplied.

    <pragma-> factadd global snack is /me eats a cookie.
       <PBot> 'snack' added to the global channel
    <pragma-> factset global snack action_with_args /me gives $args a cookie.
       <PBot> [Factoids] (global) snack: 'action_with_args' set to '/me gives $args a cookie.'
    <pragma-> snack
            * PBot eats a cookie.
    <pragma-> snack orbitz
            * PBot gives orbitz a cookie.

### add_nick

You can use the [factset](#factset) command to set a special factoid meta-data key named `add_nick` to prepend the nick of the caller to the output.  This is mostly useful for modules.

Deleting a factoid
------------------
### factrem
### forget

To remove a factoid, use the `factrem` or `forget` command.

Usage: `factrem <channel> <keyword>` `forget <channel> <keyword>`

Viewing/triggering a factoid
----------------------------
To view or trigger a factoid, one merely issues its keyword as a command.

    <pragma-> PBot, c?
       <PBot> C rocks!

Viewing/triggering another channel's factoid
--------------------------------------------
### fact
To view or trigger a factoid belonging to a specific channel, use the `fact` command.

Usage: `fact <channel> <keyword> [arguments]`

Aliasing a factoid
------------------
### factalias
To create an factoid that acts as an alias for a command, use the `factalias` command or set the factoid's `action` to `/call <command>`.

Usage: `factalias <channel> <new keyword> <command>`

    <pragma-> factadd ##c offtopic is /say In this channel, $args is off-topic.
    <pragma-> offtopic C++
       <PBot> In this channel, C++ is off-topic.
    <pragma-> factalias ##c C++ offtopic C++
    <pragma-> C++
       <PBot> In this channel, C++ is off-topic.

<!-- -->

    <pragma-> factadd ##c book is /me points accusingly at $args, "Where is your book?!"
       <PBot> 'book' added to ##c
    <pragma-> book newbie
            * PBot points accusingly at newbie, "Where is your book?!"
    <pragma-> factadd ##c rafb /call book
       <PBot> 'rafb' added to ##c
    <pragma-> rafb runtime
            * PBot points accusingly at runtime, "Where is your book?!"

Moving/renaming a factoid
-------------------------
### factmove
To rename a factoid or move a factoid to a different channel, use the `factmove` command:

Usage:  `factmove <source channel> <source factoid> <target channel/factoid> [target factoid]`

If three arguments are given, the factoid is renamed in the source channel.  If four arguments are given, the factoid is moved to the target channel with the target name.

Changing a factoid
------------------
### factchange
To change a factoid, use the `factchange` command:

Usage:  `factchange <channel> <keyword> s/<pattern>/<change to>/[gi]`

    <pragma-> c
       <PBot> C rocks!
    <pragma-> factchange ##c c s/rocks/rules/
       <PBot> c changed.
    <pragma-> c
       <PBot> C rules!

Note that the final argument is a Perl-style substitution regex.  See `man perlre` on your system.

For instance, it is possible to append to a factoid by using: `factchange channel factoid s/$/text to append/`

Likewise, you can prepend to a factoid by using: `factchange channel factoid s/^/text to prepend/`

Alternatively, you may append to a factoid by using `is also`:

    <pragma-> PBot, c is also See FAQ at http://www.eskimo.com/~scs/C-faq/top.html
       <PBot> Changed: c is /say C rules! ; See FAQ at http://www.eskimo.com/~scs/C-faq/top.html

### factundo
To revert to an older revision, use the `factundo` command. You can repeatedly factundo a factoid until it has no more remaining undos.

Usage: `factundo [channel] <keyword>`

### factredo
To revert to a newer revision, use the `factredo` command. You can repeatedly factredo a factoid until it has no more remaining redos.

Usage: `factredo [channel] <keyword>`

### factset
To view or set factoid meta-data, such as owner, rate-limit, etc, use the `factset` command. See also: [factoid metadata list](#Factoid_Metadata_List).

Usage:  `factset <channel> <factoid> [<key> [value]]`

Omit `<key>` and `<value>` to list all the keys and values for a factoid.  Specify `<key>`, but omit `<value>` to see the value for a specific key.

#### Factoid Metadata List
This is a list of recognized factoid meta-data fields. The number in parentheses next to the field is the minimum admin level necessary to modify it; if there is no such number then anybody may modify it.

*  `created_on` (90): The timestamp of when the factoid was created.
*  `enabled` (10): Whether the factoid can be invoked or not.
*  `last_referenced_in` (90): The channel or private-message in which the factoid was last used.
*  `last_referenced_on` (90): The timestamp of when the factoid was last used.
*  `modulelauncher_subpattern` (90): A substitution expression used to modify the arguments into a command-line.
*  `owner` (90): The creator of the factoid.
*  `rate_limit` (10): How often the factoid may be invoked, in seconds. Zero for unlimited.
*  `ref_count` (90): How many times the factoid has been invoked.
*  `ref_user` (90): The hostmask of the last person to invoke the factoid.
*  `type` (90): The type of the factoid. "text" for regular factoid; "module" for module.
*  `edited_by` (90): The hostmask of the person to last edit the factoid.
*  `edited_on` (90): The timestamp of when the factoid was last edited.
*  `locked` (10): If enabled, prevents the factoid from being changed or removed.
*  `add_nick` (10): Prepends the nick of the person invoking the factoid to the output of the factoid.
*  `nooverride` (10): Prevents the creation of a factoid with an identical name in a different channel.
*  `effective-level` (20): the effective admin level at which this factoid executes (i.e., for /kick, etc)
*  `persist-key` (20): the storage key for allowing code-factoids to persist variables
*  `action_with_args`: Alternate action to perform if an argument has been supplied when invoking the factoid.
*  `noembed`: Factoid will not be triggered if embedded within a sentence.
*  `interpolate`: when set to a false value, $variables will not be expanded.
*  `use_output_queue`: when set to a true value, the output will be delayed by a random number of seconds to simulate reading/typing.

### factunset

To unset factoid meta-data, use the `factunset` command.

Usage: `factunset <channel> <factoid> <key>`

Finding a factoid
-----------------
### factfind
To search the database for a factoid, use the 'factfind` command.  You may optionally specify whether to narrow by channel and/or include factoid owner and/or last referenced by in the search.

If there is only one match for the query, it will display that factoid and its text, otherwise it will list all matching keywords.

Usage: `factfind [-channel channel] [-owner nick] [-by nick] [-regex] [text]`

If you specify the `-regex` flag, the `text` argument will be treated as a regex.

    <pragma-> factfind cast
       <PBot> 3 factoids match: [##c] NULL casting dontcastmalloc

Information about a factoid
---------------------------
### factinfo
To get information about a factoid, such as who submitted it and when, use the `factinfo` command.

Usage: `factinfo [channel] <keyword>`

    <pragma-> factinfo ##c NULL
       <PBot> NULL: Factoid submitted by Major-Willard for all channels on Sat Jan 1 16:17:42 2005 [5 years and 178 days ago], referenced 39 times (last by pragma- on Sun Jun 27 04:40:32 2010 [5 seconds ago])

### factshow
To see the factoid `action` literal, use the `factshow` command.

Usage: `factshow [channel] <keyword>`

    <pragma-> factshow ##c hi
       <PBot> hi: /say $greetings, $nick.

### factset
To view factoid meta-data, such as owner, rate-limit, etc, use the `factset` command.

Usage:  `factset <channel> <factoid> [<key> [value]]`

Omit `<key>` and `<value>` to list all the keys and values for a factoid.  Specify `<key>`, but omit `<value>` to see the value for a specific key.

### factlog
To see a factoid's changelog history, use the `factlog` command.

Usage: `factlog [-h] [-t] [channel] <factoid>`

`-h` shows full hostmasks instead of just the nick. `-t` shows the actual timestamp instead of relative.

    <pragma-> factadd hi /say Hello there!
       <PBot> hi added to global channel.
    <pragma-> factchange hi s/!$/, $nick!/
       <PBot> Changed: hi is /say Hello there, $nick!
    <pragma-> forget hi
       <PBot> hi removed from the global channel.
    <pragma-> factadd hi /say Hi!

<!-- -->

    <pragma-> factlog hi
       <PBot> [3m ago] pragma- created: /say Hi! [5m ago] pragma- deleted [8m ago] pragma- changed to /say Hello there, $nick! [10m ago] pragma- created: /say Hello there!

### count
To see how many factoids and what percentage of the database `<nick>` has submitted, use the `count` command.

Usage: `count <nick>`

    <pragma-> count prec
       <PBot> prec has submitted 28 factoids out of 233 (12%)
    <pragma-> count twkm
       <PBot> twkm has submitted 74 factoids out of 233 (31%)
    <pragma-> count pragma
       <PBot> pragma has submitted 27 factoids out of 233 (11%)

### histogram
To see a histogram of the top factoid submitters, use the `histogram` command.

    <pragma-> histogram
       <PBot> 268 factoids, top 10 submitters: twkm: 74 (27%) Major-Willard: 64 (23%) pragma-: 40 (14%) prec: 39 (14%) defrost: 14 (5%) PoppaVic: 10 (3%) infobahn: 7 (2%) orbitz: 3 (1%) mauke: 3 (1%) Tom^: 2 (1%)

### top20
To see the top 20 most popular factoids, use the 'top20' command.

Commands
========
To see all the currently available commands, use the `list commands` command.

Some commands are:

Quotegrabs
----------
### grab
Grabs a message someone says, and adds it to the quotegrabs database.  You may grab multiple nicks/messages in one quotegrab by separating the arguments with a plus sign (the nicks need not be different -- you can grab multiple messages by the same nick by specifying a different history for each grab).

You can use the [recall](#recall) command to test the arguments before grabbing (please use a private message).

Usage: `grab <nick> [history [channel]] [+ ...]`
          where [history] is an optional argument regular expression used to search message contents;
          e.g., to grab a message containing the text "pizza", use: grab nick pizza

        <bob> Clowns are scary.
    <pragma-> grab bob clowns
       <PBot> Quote grabbed: 1: <bob> Clowns are scary.

<!-- -->

      <alice> Please put that in the right place.
        <bob> That's what she said!
    <pragma-> grab alice place + bob said
       <PBot> Quote grabbed 2: <alice> Please put that in the right place. <bob> That's what she said!

<!-- -->

    <charlie> I know a funny programming knock-knock joke.
    <charlie> Knock knock!
    <charlie> Race condition.
    <charlie> Who's there?
    <pragma-> grab charlie knock + charlie race + charlie there
       <PBot> Quote grabbed 3: <charlie> Knock knock! <charlie> Race condition. <charlie> Who's there?

### getq
Retrieves and displays a specific grabbed quote from the quotegrabs database.

Usage: `getq <quote-id>`

### rq
Retrieves and displays a random grabbed quote from the quotegrabs database.  You may filter by nick, channel and/or quote text.

Usage: `rq [nick [channel [text]]] [-c,--channel <channel>] [-t,--text <text>]`

### delq
Deletes a specific grabbed quote from the quotegrabs database.  You can only delete quotes you have grabbed unless you are logged in as an admin.

Usage: `delq <quote-id>`

### recall
Recalls messages from the chat history and displays them with a relative time-stamp.

Usage: `recall <[nick [history [channel]]] [-c,channel <channel>] [-t,text,h,history <history>] [-b,before <context before>] [-a,after <context after>] [-x,context <nick>] [-n,count <count>] [+ ...]>`

You can use `-b/-before` and `-a/-after` to display the messages before and after the result me For example, `recall ##c -b 99` would show the last 100 messages in the ##c channel.  `recall bob 50 -b 5 -a 5` would show the 50th most recent message from bob, including 5 messages before and 5 messages after that message.  If you also specify `-x <nick>`, then the before and after messages will be limited to messages from the `<nick>` argument; for example, `recall -x bob -b 10` would show bob's 10 most recent messages.

Alternatively, you can use `-n/-count` to display that many matches resulting from a `-h/-history` search; for example, `recall -h http -n 5` would show the last 5 messages containing "http". You can specify `-x/-context` to limit the search to a specific nick; for example, `recall -h http -x bob -n 5` would show bob's last 5 messages containing "http".

    <pragma-> recall alice + bob
       <PBot> [20 seconds ago] <alice> Please put that in the right place. [8 seconds ago] <bob> That's what she said!

Modules
-------

### cc
Code compiler (and executor).  This command will compile and execute user-provided code in a number of languages, and then display the compiler and/or program output.

The program is executed within a gdb debugger instance, which may be interacted with via the [gdb macros described below](#Using_the_GDB_debugger) or with the `gdb("command")` function.

The compiler and program are executed inside a virtual machine.  After each run, the virtual machine is restored to a previous state.  No system calls have been disallowed.  You can write to and read from the filesystem, provided you do it in the same program.  The network cable has been unplugged.  You are free to write and test any code you like.  Have fun.

#### Usage

- `cc [-lang=<language>] [-info] [-paste] [-args "command-line arguments"] [-stdin "stdin input"] [compiler/language options] <code>`
- `cc <run|undo|show|paste|copy|replace|prepend|append|remove|s/// [and ...]>`
- `cc <diff>`
- `[nick] { <same as above without the cc in front> }`

You can pass any gcc compiler options.  By default, `-Wall -Wextra -std=c11 -pedantic` are passed unless an option is specified.

The `-paste` option will pretty-format and paste the code/output to a paste site and display the URL (useful to preserve newlines in output, and to refer to line-numbers).

The `-nomain` flag will prevent the code from being wrapped with a `main()` function. This is not necessary if you're explicitly defining a `main` function; it's only necessary if you don't want a `main` function at all.

The `-noheaders` flag will prevent any of the default headers from being added to the code. This is not necessary if you explicitly include any headers since doing so will override the default headers. This flag is only necessary if you want absolutely no headers whatsoever.

The `-stdin <stdin input>` option provides STDIN input (i.e., `scanf()`, `getc(stdin)`, etc.).

The `-args <command-line arguments>` option provides command-line arguments (i.e., `argv`).

The `run`, `undo`, `show`, `replace`, etc commands are part of [interactive-editing](#Interactive_Editing).

The `diff` command can be used to display the differences between the two most recent snippets.

#### Supported Languages
The `-lang` option can be used to specify an alternate compiler or language. Use `-lang=?` to list available languages.

    <pragma-> cc -lang=?
       <PBot> Language '?' is not supported. Supported languages are: bash, bc, bf, c11, c89, c99, clang, clang11, clang89, clang99, clang++, clisp, c++, freebasic, go, haskell, java, javascript, ksh, lua, perl, php, python, python3, qbasic, ruby, scheme, sh, tcl, tendra, zsh

Most, if not all, of these languages have an direct alias to invoke them.

    <pragma-> factshow perl
       <PBot> [global] perl: /call cc -lang=perl $args
    <pragma-> perl print 'hi'
       <PBot> hi

#### Default Language
The default language (e.g., without an explicit `-lang` or `-std` option) is C11 pedantic; which is `gcc -Wall -Wextra -std=c11 -pedantic`.

#### Disallowed system calls
None.  The network cable has been unplugged.  Other than that, anything goes.  Have fun.

#### Program termination with no output
If there is no output, information about the local variables and/or the last statement will be displayed.

    <pragma-> cc int x = 5, y = 16; x ^= y, y ^= x, x ^= y;
       <PBot> pragma-:  no output: x = 16; y = 5

<!-- -->

    <pragma-> cc #include <sys/utsname.h> struct utsname u; uname(&u);
       <PBot> pragma-:  no output: u = {sysname = "Linux", nodename = "compiler", release = "3.2.0-8-generic", version = "#15-Ubuntu SMP Wed Jan 11 13:57:44 UTC 2012", machine = "x86_64",  __domainname = "(none)"}

<!-- -->

    <pragma-> cc int a = 2, b = 3;  ++a + b;
       <PBot> pragma-:  no output: ++a + b = 6; a = 3; b = 3

<!-- -->

    <pragma-> cc sizeof (char)
       <PBot> pragma-:  no output: sizeof (char) = 1

<!-- -->

    <pragma-> cc 2 + 2
       <PBot> pragma-:  no output: 2 + 2 = 4

#### Abnormal program termination
If a signal is detected, the bot will display useful information.

    < pragma-> cc char *p = 0; *p = 1;
        <PBot> pragma-: Program received signal 11 (SIGSEGV) at statement: *p = 1; <local variables: p = 0x0>

<!-- -->

    <pragma-> cc void bang() { char *p = 0, s[] = "lol"; strcpy(p, s); }  bang();
       <PBot> pragma-: Program received signal 11 (SIGSEGV) in bang () at statement: strcpy(p, s); <local variables: p = 0x0, s = "lol">

<!-- -->

    <pragma-> cc int a = 2 / 0;
       <PBot> pragma-: [In function 'main': warning: division by zero] Program received signal 8 (SIGFPE) at statement: int a = 2 / 0;

#### C and C++ Functionality
#### Using the preprocessor

##### Default #includes
These are the default includes for C11.  To get the most up-to-date list of #includes, use the `cc paste` command.

    #define _XOPEN_SOURCE 9001
    #define __USE_XOPEN
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <unistd.h>
    #include <math.h>
    #include <limits.h>
    #include <sys/types.h>
    #include <stdint.h>
    #include <stdbool.h>
    #include <stddef.h>
    #include <stdarg.h>
    #include <stdnoreturn.h>
    #include <stdalign.h>
    #include <ctype.h>
    #include <inttypes.h>
    #include <float.h>
    #include <errno.h>
    #include <time.h>
    #include <assert.h>
    #include <complex.h>

##### Using #include
In C and C++, you may `#include <file.h>` one after another on the same line.  The bot will automatically put them on separate lines.  If you do use `#include`, the files you specify will replace the default includes.  You do not need to append a `\n` after the `#include`.

    <pragma-> cc #include <sys/utsname.h> struct utsname u; uname(&u);
       <PBot> pragma-:  <no output: u = {sysname = "Linux", nodename = "compiler", release = "3.2.0-8-generic", version = "#15-Ubuntu SMP Wed Jan 11 13:57:44 UTC 2012", machine = "x86_64",  __domainname = "(none)"}>

<!-- -->

    <pragma-> cc #include <stdio.h> #include <stdlib.h> void func(void) { puts("Hello, world"); } func();
       <PBot> pragma-: Hello, World

In the previous examples, only the specified includes (e.g., `<sys/utsname.h>` in the first example, `<stdio.h>` and `<stdlib.h>` in the second, will be included instead of the default includes.

##### Using #define
You can also `#define` macros; however, `#defines` require an explicit `\n` sequence to terminate, oe the remainder of the line will be part of the macro.

    <pragma-> cc #define GREETING "Hello, World"\n puts(GREETING);
       <PBot> pragma-: Hello, World

#### main() Function Unnecessary
In C and C++, if there is no `main` function, then a `main` function will created and wrapped around the appropriate bits of your code (unless the `-nomain` flag was specified); anything outside of any functions, excluding preprocessor stuff, will be put into this new `main` function.

    <pragma-> cc -paste int add(int a, int b) { return a + b; } printf("4 + 6 = %d -- ", add(4, 6)); int add3(int a, int b, int c)
            { return add(a, b) + c; } printf("7 + 8 + 9 = %d", add3(7, 8, 9));
       <PBot> http://sprunge.us/ehRA?c

The `-paste` flag causes the code to be pretty-formatted and pasted with output in comments to a paste site, which displays the following:

    #define _XOPEN_SOURCE 9001
    #define __USE_XOPEN
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <unistd.h>
    #include <math.h>
    #include <limits.h>
    #include <sys/types.h>
    #include <stdint.h>
    #include <stdbool.h>
    #include <stddef.h>
    #include <stdarg.h>
    #include <stdnoreturn.h>
    #include <stdalign.h>
    #include <ctype.h>
    #include <inttypes.h>
    #include <float.h>
    #include <errno.h>
    #include <time.h>
    #include <assert.h>
    #include <complex.h>
    #include <prelude.h>


    int add(int a, int b) {
        return a + b;
    }

    int add3(int a, int b, int c) {
        return add(a, b) + c;
    }

    int main(void) {
        printf("4 + 6 = %d -- ", add(4, 6));

        printf("7 + 8 + 9 = %d", add3(7, 8, 9));
        return 0;
    }

    /************* OUTPUT *************
    4 + 6 = 10 -- 7 + 8 + 9 = 24
    ************** OUTPUT *************/

#### Embedding Newlines
Any `\n` character sequence appearing outside of a character literal or a string literal will be replaced with a literal newline.

#### Printing in binary/base2
A freenode ##c regular, Wulf, has provided a printf format specifier `b` which can be used to print values in base2.

    <Wulf> cc printf("%b", 1234567);
    <PBot> 000100101101011010000111

<!-- -->

    <Wulf> cc printf("%#'b", 1234567);
    <PBot> 0001.0010.1101.0110.1000.0111

#### Using the GDB debugger
The program is executed within a gdb debugger instance, which may be interacted with via the following gdb macros.

##### print
The `print()` macro prints the values of expressions.  Useful for printing out structures and arrays.

    <pragma-> cc int a[] = { 1, 2, 3 }; print(a);
       <PBot> pragma-: a = {1, 2, 3}

<!-- -->

    <pragma-> cc #include <sys/utsname.h> struct utsname u; uname(&u); print(u);
       <PBot> pragma-: u = {sysname = "Linux", nodename = "compiler", release = "3.2.0-8-generic", version = "#15-Ubuntu SMP Wed Jan 11 13:57:44 UTC 2012", machine = "x86_64",  __domainname = "(none)"}

<!-- -->

    <pragma-> cc print(sizeof(int));
       <PBot> pragma-: sizeof(int) = 4

<!-- -->

    <pragma-> cc print(2+2);
       <PBot> pragma-: 2 + 2 = 4

##### ptype
The `ptype()` macro prints the types of expressions.

    <pragma-> cc int *a[] = {0}; ptype(a); ptype(a[0]); ptype(*a[0]);
       <PBot> pragma-: a = int *[1]  a[0] = int *  *a[0] = int

##### watch
The `watch()` macro watches a variable and displays its value when it changes.

    <pragma-> cc int n = 0, last = 1; watch(n); while(n <= 144) { n += last; last = n - last; } /* fibonacci */
       <PBot> pragma-: n = 1  n = 2  n = 3  n = 5  n = 8  n = 13  n = 21  n = 34  n = 55  n = 89  n = 144

##### trace
The `trace()` macro traces a function's calls, displaying passed and returned values.

    <pragma-> ,cc trace(foo); char *foo(int n) { puo, world"); return "Good-bye, world"; } foo(42);
       <PBot> pragma-: entered [1] foo (n=42)  Hello, world  leaving [1] foo (n=42), returned 0x401006 "Good-bye, world"

##### gdb
The `gdb()` function takes a string argument which it passes to the gdb debugger and then displays the output if any.

    <pragma-> ,cc gdb("info macro NULL");
       <PBot> pragma-: Defined at /usr/lib/gcc/x86_64-linux-gnu/4.7/include/stddef.h:402  #define NULL ((void *)0)

<!-- -->

    <pragma-> ,cc void foo() { gdb("info frame"); } foo();
       <PBot> pragma-: Stack level 1, frame at 0x7fffffffe660: rip = 0x400e28 in foo (); saved rip 0x400e43 called by frame at 0x7fffffffe680, caller of frame at 0x7fffffffe650 source language c. Arglist at 0x7fffffffe650, args: Locals at 0x7fffffffe650, Previous frame's sp is 0x7fffffffe660 Saved registers: rbp at 0x7fffffffe650, rip at 0x7fffffffe658

#### Interactive Editing
The [cc](#cc) command supports interactive-editing.  The general syntax is:  `cc [command]`.

Each cc snippet is saved in a buffer which is named after the channel or nick it was used in.  You can use [show](#show) or [diff](#diff) with a buffer argument to view that buffer; otherwise you can use the [copy](#copy) command to copy the most recent snippet of another buffer into the current buffer and optionally chain it with another command -- for example, to copy the `##c` buffer (e.g., from a private message or a different channel) and paste it: `cc copy ##c and paste`.

The commands are:  [copy](#copy), [show](#show), [diff](#diff), [paste](#paste), [run](#run), [undo](#undo), [s//](#s.2F.2F), [replace](#replace), [prepend](#prepend), [append](#append), and [remove](#remove).  Most of the commands may be chained together by separating them with whitespace or "and".

The commands are described in more detail below:

##### copy
To copy the most recent snippet from another buffer (e.g., to copy another channel's or private message's buffer to your own private message or channel), use the `copy` command.  Other commands can optionally be chained after this command.

Usage: `cc copy <buffer> [and ...]`

##### show
To show the latest code in the buffer, use the `show` command.  This command can take an optional buffer argument.

    <pragma-> cc show
       <PBot> pragma-: printf("Hello, world!");

This command is stand-alone and cannot be chained with other interactive-editing commands.

##### diff
To see the differences between the two most recent snippets, use the `diff` command.  This command can take an optional buffer argument.

    <pragma-> cc diff
       <PBot> pragma: printf("<replaced `Hello` with `Good-bye`>, <replaced `world` with `void`>");

This command is stand-alone and cannot be chained with other interactive-editing commands.

##### paste
To paste the full source of the latest code in the buffer as the compiler sees it, use the `paste` command:

    <pragma-> cc paste
       <PBot> pragma-: http://some.random.paste-site.com/paste/results

This command is stand-alone and cannot be chained with other interactive-editing commands.

##### run
To attempt to compile and execute the latest code in the buffer, use the `run` command:

    <pragma-> cc run
       <PBot> pragma-: Hello, world!

This command is stand-alone and cannot be chained with other interactive-editing commands.

##### undo
To undo any changes, use `undo`.  The `undo` command must be the first command before any subsequent commands.

##### s//
To change the latest code in the buffer, use the `s/regex/substitution/[gi]` pattern.

    <pragma-> cc s/Hello/Good-bye/ and s/world/void/
       <PBot> pragma-: Good-bye, void!
    <pragma-> cc show
       <PBot> pragma-: printf("Good-bye, void!");

##### replace
Alternatively, you may use the `replace` command.  The usage is (note the required single-quotes):

`cc replace [all, first, second, ..., tenth, last] 'from' with 'to'`

##### prepend
Text may be prepended with the `prepend` command:

`cc prepend 'text'`

##### append
Text may be appended with the `append` command:

`cc append 'text'`

##### remove
Text may be deleted with the `remove` command:

`cc remove [all, first, second, ..., tenth, last] 'text'`

#### Some Examples

    <pragma-> cc int fib2(int n, int p0, int p1) { return n == 1 ? p1 : fib2(n  - 1, p1, p0 + p1); }
                int fib(int n) { return n == 0 ? 0 : fib2(n, 0, 1); } for(int i = 0; i < 21; i++) printf("%d ", fib(i));
       <PBot> pragma-: 0 1 1 2 3 5 8 13 21 34 55 89 144 233 377 610 987 1597 2584 4181 6765

<!-- -->

    <pragma-> cc int i = 0, last = 1; while(i <= 7000) { printf("%d ", i); i += last; last = i - last; }
       <PBot> pragma-: 0 1 1 2 3 5 8 13 21 34 55 89 144 233 377 610 987 1597 2584 4181 6765

<!-- -->

    <Icewing> cc int n=0, f[2]={0,1}; while(n<20) printf("%d ",f[++n&1]=f[0]+f[1]); // based on cehteh
       <PBot> Icewing: 1 1 2 3 5 8 13 21 34 55 89 144 233 377 610 987 1597 2584 4181 6765

<!-- -->

  <3monkeys> cc @p=(0,1); until($#p>20) { print"$p[-2]\n"; push @p, $p[-2] + $p[-1] } -lang=Perl
      <PBot> 3monkeys: 0 1 1 2 3 5 8 13 21 34 55 89 144 233 377 610 987 1597 2584 4181

<!-- -->

    <spiewak> cc -lang=Ruby p,c=0,1; 20.times{p p; c=p+p=c}
       <PBot> spiewak: 0 1 1 2 3 5 8 13 21 34 55 89 144 233 377 610 987 1597 2584 4181

<!-- -->

    <Jafet> cc main = print $ take 20 $ let fibs = 0 : scanl (+) 1 fibs in fibs; -lang=Haskell
     <PBot> Jafet: [0,1,1,2,3,5,8,13,21,34,55,89,144,233,377,610,987,1597,2584,4181]

### english
Converts C11 code into English sentences.

Usage: english `<C snippet>`

    <pragma-> english char (*a)[10];  char *b[10];
       <PBot> Let a be a pointer to an array of length 10 of type char. Let b be an array of length 10 of type pointer to char.

<!-- -->

    <pragma-> english for(;;);
       <PBot> Repeatedly do nothing.

<!-- -->

    <pragma-> english typedef char Batman; char Bruce_Wayne; char superhero = (Batman) Bruce_Wayne;
       <PBot> Let Batman be another name for a character. Let Bruce_Wayne be a character. Let superhero be a character, with value being Bruce_Wayne cast to a Batman.

### expand
Expands macros in C code and displays the resulting code.  Macros must be terminated by a `\n` sequence.  You may `#include` headers to expand macros defined within.

Usage: `expand <C snippet>`

    <pragma-> expand #define WHILE while ( \n #define DO ) { \n #define WEND } \n  int i = 5; WHILE --i DO puts("hi"); WEND
       <PBot> pragma-: int i = 5; while ( --i ) { puts("hi"); }
    <pragma-> expand #include <stdlib.h> NULL
       <PBot> pragma-: ((void *)0)

### prec
### paren
Shows operator precedence in C99 expressions by adding parentheses.
Usage: `prec <expression>` `paren <expression>`

    <pragma-> prec *a++
       <PBot> pragma-: *(a++)

<!-- -->

    <pragma-> prec a = b & c
       <PBot> pragma-: a = (b & c)

<!-- -->

    <pragma-> prec token = strtok(s, d) != NULL
       <PBot> pragma-: token = (strtok(s, d) != NULL)

### faq
Displays questions from the [http://http://www.eskimo.com/~scs/C-faq/top.html](comp.lang.c FAQ).  Some queries may return more than one result; if this happens, you may use the `match #` optional argument to specify the match you'd like to view.

Usage: `faq [match #] <search regex>`

    <pragma-> faq cast malloc
       <PBot> 2 results, displaying #1: 7. Memory Allocation, 7.6 Why am I getting ``warning: assignment of pointer from integer lacks a cast** for calls to malloc? : http://www.eskimo.com/~scs/C-faq/q7.6.html
    <pragma-> faq 2 cast malloc
       <PBot> 2 results, displaying #2: 7. Memory Allocation, 7.7 Why does some code carefully cast the values returned by  malloc to the pointer type being allocated? : http://www.eskimo.com/~scs/C-faq/q7.7.html
    <pragma-> faq ^6.4
       <PBot> 6. Arrays and Pointers, 6.4 Why are array and pointer declarations interchangeable as function formal parameters? : http://www.eskimo.com/~scs/C-faq/q6.4.html

### cfact
Displays a random C fact.  You may specify a search text to limit the random set to those containing that text.

`Usage: cfact [search text]`

    <pragma-> cfact
       <PBot> pragma-: [6.7.2.1 Structure and union specifiers] A structure or union may have a member declared to consist of a specified number of bits. Such a member is called a bit-field.

### cjeopardy
C Jeopardy is loosely based on the Jeopardy! game show. The questions are phrased in the form of an answer and are answered in the form of a question.

The `cjeopardy` command isplays a random C Jeopardy question.  You can specify a search text to limit the random set to those containing that text.  Answer the questions with `what is ...?`
Can be used to skip the current question.

Usage: `cjeopardy [search text]`

       <PBot> 1009) This macro expands to a integer constant expressions that can be used as the argument to the exit function to return successful termination status to the host environment.
    <pragma-> what is EXIT_SUCCESS?
       <PBot> pragma-: 'EXIT_SUCCESS' is correct! (1m15s)

#### hint
Displays a hint for the current C Jeopardy question. Each subsequent hint request reveals more of the answer.

#### what
#### w
Answers a C Jeopardy question. `w` may be used as an alternative short-hand.

Usage: `what is <answer>?`

Usage: `w <answer>`

#### filter
`filter` can skip questions containing undesirable words such as wide-character or floating-point.

Usage: `filter <comma or space separated list of words>` or `filter clear` to clear the filter

#### score
Shows the personal C Jeopardy statistics for a player. If used without any arguments, it shows your own statistics.

Usage: `score [player name]`

#### rank
Shows ranking for various C Jeopardy statistics, or your personal rankings in each of the statistics. If used without any arguments, it shows the available keywords for which statistics to rank.

Usage: `rank [keyword or player name]`

#### reset
Resets your personal C Jeopardy statistics for the current session. Your life-time records will still be retained.

#### qstats
Shows statistics specific to a C Jeopardy question. Can also rank questions by a specific statistic.

Usage: `qstats [question id]`

Usage: `qstats rank [keyword or question id]`

#### qshow
Displays a specific C Jeopardy question without making it the current question. Useful for seeing which question belongs to a question id; .e.g. with `qstats`.

Usage: `qshow <question id>`

### c99std
Searches ISO/IEC 9899:TC3 (WG14/N1256), also known as the C99 draft standard.   http://www.open-std.org/jtc1/sc22/WG14/www/docs/n1256.pdf

Usage: `c99std [-list] [-n#] [section] [search regex]`

If specified, `section` must be in the form of `X.YpZ` where `X` and `Y` are section/chapter and, optionally, `pZ` is paragraph.

To display a specific section and all its paragraphs, specify just the `section` without `pZ`.

To display just a specific paragraph, specify the full `section` identifier (`X.YpZ`).

You may use `-n #` to skip to the nth match.

To list only the section numbers containing 'search text', add `-list`.

If both `section` and `search regex` are specified, then the search space will be within the specified section identifier.

    <pragma-> c99std pointer value
       <PBot> Displaying #1 of 64 matches: 5.1.2.2.1p1: [Program startup] If they are declared, the parameters to the main function shall obey the following constraints: -- The value of argc shall be nonnegative. -- argv[argc] shall be a null pointer. -- If the value of argc is greater than zero, the array members argv[0] through argv[argc-1] inclusive shall contain pointers to st... truncated; see http://codepad.org/f2DULaGQ for full text.

<!-- -->

     <pragma-> c99std pointer value -list
        <PBot> Sections containing 'pointer value': 5.1.2.2.1p2, 5.1.2.3p9, 6.2.5p20, 6.2.5p27, 6.3.2.1p3, 6.3.2.1p4, 6.3.2.3p2, 6.3.2.3p6, 6.5.2.1p3, 6.5.2.2p5, 6.5.2.2p6, 6.5.2.4p1, 6.5.2.4p2, 6.5.3.1p1, 6.5.3.2p3, 6.5.3.2p4, 6.5.3.3p5, 6.5.3.4p5, 6.5.6p8, 6.5.6p9, 6.5.8p5, 6.5.15p6, 6.6p7, 6.6p9, 6.7.2.2p5, 6.7.2.3p7, 6.7.2.3p3, 6.7.5.1p3, 6.7.5.2p7, 7.1.1p1, 7.1.1p4, 7.1.4p1, 7... truncated; see http://codepad.org/qQlnJYJk for full text.

<!-- -->

    <pragma-> Hmm, how about just section 6.3?
    <pragma-> c99std pointer value 6.3
       <PBot> Displaying #1 of 4 matches: 6.3.2.1p1: [Lvalues, arrays, and function designators] Except when it is the operand of the sizeof operator or the unary & operator, or is a string literal used to initialize an array, an expression that has type ``array of type is converted to an expression with type ``pointer to type that points to the initial element of the array ob... truncated; see http://codepad.org/mf1RNnr2 for full text.

<!-- -->

    <pragma-> c99std pointer value 6.3 -list
       <PBot> Sections containing 'pointer value': 6.3.2.1p3, 6.3.2.1p4, 6.3.2.3p2, 6.3.2.3p6

<!-- -->

    <pragma-> c99std pointer value 6.3 -n3
       <PBot> Displaying #3 of 4 matches: 6.3.2.3p1: [Pointers] For any qualifier q, a pointer to a non-q-qualified type may be converted to a pointer to the q-qualified version of the type; the values stored in the original and converted pointers shall compare equal.

### c11std
Searches ISO/IEC 9811:201X (WG14/N1256), also known as the C11 draft standard.  http://www.open-std.org/jtc1/sc22/wg14/www/docs/n1570.pdf

Usage is identical to `c99std`.

### man
Displays manpage summaries and/or C related tidbits (headers, prototypes, specifications), as well as a link to the FreeBSD manpage.

Usage:  `man [section] query`

    <pragma-> man fork
       <PBot> Includes: sys/types.h, unistd.h - pid_t fork(void); - SVr4, SVID, POSIX, X/OPEN, BSD - fork creates a child process that differs from the parent process only in its PID and PPID, and in the fact that resource utilizations are set to 0 - http://www.iso-9899.info/man?fork

    <pragma-> man atexit
       <PBot> Includes: stdlib.h - int aid (*function)(void)); - SVID 3, BSD 4.3, ISO 9899 - atexit () function registers the given function to be called at normal program termination, whether via exit(3) or via return from the program's main - http://www.iso-9899.info/man?atexit

    <pragma-> man getcwd
       <PBot> Includes: unistd.h - char *getcwd(char *buf, size_t size); - POSIX.1 - getcwd () function copies an absolute pathname of the current working directory to the array pointed to by buf, which is of length size - http://www.iso-9899.info/man?getcwd

### google
Displays google results for a query.

Usage: `google [number of results] <query>`

    <pragma-> google brian kernighan
       <PBot> brian kernighan (115,000): Brian Kernighan's Home Page: (http://www.cs.princeton.edu/~bwk/)

 <!-- -->

    <pragma-> google 3 brian kernighan
       <PBot> brian kernighan (115,000): Brian Kernighan's Home Page: (http://www.cs.princeton.edu/~bwk/), An Interview with Brian Kernighan: (http://www-2.cs.cmu.edu/~mihaib/kernighan-interview/), Interview with Brian Kernighan | Linux Journal: (http://www.linuxjournal.com/article.php?sid=7035), Brian W. Kernighan: (http://www.lysator.liu.se/c/bwk/) ,Brian W. Kernighan: Programming in C: A Tutorial: (http://www.lysator.liu.se/c/bwk-tutor.html)

### define
### dict
Displays dictionary definitions from http://dict.org using DICT protocol.

Databases for the `-d` option are listed here: http://www.iso-9899.info/PBot/dict_databases.txt -- Note that there may be several commands aliased to one of these databases; for example, the `foldoc` command is an alias to `dict -d foldoc`.

Usage: `dict [-d database] [-n start from definition number] [-t abbreviation of word class type (n]oun, v]erb, adv]erb, adj]ective, etc)] [-search <regex> for definitions matching <regex>] <word>`

    <pragma-> dict hit
       <PBot> hit: n: 1) (baseball) a successful stroke in an athletic contest (especially in baseball); "he came all the way around on Williams' hit", 2) the act of contacting one thing with another; "repeated hitting raised a large bruise"; "after three misses she finally got a hit" [syn: hitting, striking], 3) a conspicuous success; "that song was his first hit and marked the beginning of his career"; "that new Broadway show is a real smasher"

<!-- -->

    <pragma-> dict -n 4 hit
       <PBot> hit: n: 4) (physics) an brief event in which two or more bodies come together; "the collision of the particles resulted in an exchange of energy and a change of direction" [syn: collision], 5) a dose of a narcotic drug, 6) a murder carried out by an underworld syndicate; "it has all the earmarks of a Mafia hit", 7) a connection made via the internet to another website; "WordNet gets many hits from users worldwide"

<!-- -->

    <pragma-> dict -t v hit
       <PBot> hit: v: 1) cause to move by striking; "hit a ball", 2) hit against; come into sudden contact with; "The car hit a tree"; "He struck the table with his elbow" [syn: strike, impinge on, run into, collide with] [ant: miss], 3) affect or afflict suddenly, usually adversely; "We were hit by really bad weather"; "He was stricken with cancer when he was still a teenager"; "The earstruck at midnight" [syn: strike], 4) deal a blow to

<!-- -->

    <pragma-> dict -search ball hit
       <PBot> hit: n: 1) (baseball) a successful stroke in an athletic contest (especially in baseball); "he came all the way around on Williams' hit", v: 1) cause to move by striking; "hit a ball"

<!-- -->

    <pragma-> dict -d eng-fra hit
       <PBot> hit: 1) [hit] battre, frapper, heurter frapper, heurter atteindre, frapper, parvenir, saisir

### foldoc
This is an alias for `dict -d foldoc`.

### vera
This is an alias for `dict -d vera`.

### udict
Displays dictionary definitions from http://urbandictionary.com.

Usage: `udict <query>`

### wdict
Displays Wikipedia article abstracts (first paragraph).  Note: case-sensitive and very picky.

Usage: `wdict <query>`

### acronym
Displays expanded acronyms.

Usage: `acronym <query>`

    <pragma-> acronym posix
       <PBot> posix (3 entries): Portable Operating System for Information Exchange, Portable Operating System Interface Extensions (IBM), Portable Operating System Interface for Unix
    <pragma-> acronym linux
       <PBot> linux (1 entries): Linux Is Not UniX

### math
### calc
Evaluate calculations.  Can also perform various unit conversions.

Usage:  `math <expression>` `calc <expression>`

    <pragma-> calc 5 + 5
       <PBot> 5 + 5 = 10

<!-- -->

    <pragma-> calc 80F to C
       <PBot> pragma-: 80F to C = 26.6666666666667 C

### qalc
Evaluate calculations using the `QCalculate!` program.

Usage: `qalc <expression>`

### compliment
Displays a random Markov-chain compliment/insult.

Usage: `compliment [nick]`

### insult
Displays a random insult.

Usage: `insult [nick]`

### excuse
Displays a random excuse.

Usage: `excuse [nick]`

### horoscope
Displays a horoscope for a Zodiac sign (google this if you don't know your sign).

Usage: `horoscope <sign>`

### horrorscope
Displays a horrorscope for a Zodiac sign.

Usage: `horrorscope <sign>`

### quote
Displays quotes from a popular quotation database.  If you use `quote` without arguments, it returns a random quote; if you use it
with an argument, it searches for quotes containing that text; if you add `--author <name>` at the end, it searches for a quote by
that author; if you specify `text` and `--author`, it searches for quotes by that author, containing that text.

Usage: `quote [search text] [--author <author name>]`

    <pragma-> quote
       <PBot> "Each success only buys an admission ticket to a more difficult problem." -- Henry Kissinger (1923 -  ).
    <pragma-> quote --author lao tzu
       <PBot> 41 matching quotes found. "A journey of a thousand miles begins with a single step." -- Lao-tzu (604 BC - 531 BC).
    <pragma-> quote butterfly
       <PBot> 11 matching quotes found. "A chinese philosopher once had a dream that he was a butterfly. From that day on, he was never quite certain that he was not a butterfly, dreaming that he was a man." -- Unknown.

Informative
-----------
### list
Lists information about specified argument

Usage: `list <modules|factoids|commands|admins>`

### info
Shows detailed information about a module or a factoid

Usage: `info [channel] <keyword>`

### version
Shows version information.

### source
Shows PBot's source information.

### help
Shows link to this page.

Administrative
--------------
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

### Channel Management
#### chanadd
`chanadd` adds a channel to PBot's list of channels to auto-join and manage.

Usage: `chanadd <channel>`

#### chanrem
`chanrem` removes a channel from PBot's list of channels to auto-join and manage.

Usage: `chanrem <channel>`

#### chanset
`chanset` sets a channel's meta-data. See [channel meta-data list](#Channel_Metadata_List)

Usage: `chanset <channel> [key [value]]`

If both `key` and `value` are omitted, chanset will show all the keys and values for that channel. If only `value` is omitted, chanset will show the value for that key.

##### Channel Metadata List
* `enabled`: when set to a true value, PBot will auto-join this channel after identifying to NickServ (unless `general.autojoin_wait_for_nickserv` is `0`, in which case auto-join happens immediately).
* `chanop`: when set to a true value, PBot will perform channel management (anti-flooding, ban-evasion, etc).
* `permop`: when set to a true value, PBot will automatically op itself when joining and remain opped instead of automatically opping and deopping as necessary.

#### chanunset
`chanunset` deletes a channel's meta-data key.

Usage: `chanunset <channel> <key>`

#### chanlist
`chanlist` lists all added channels and their meta-data keys and values.

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

Flood control
=============
PBot can monitor the channel for excessive rapid traffic originating from an individual and automatically ban the offender for a certain length of time.

Message flood
-------------
If four (4) or more messages are sent within five (5) seconds, the flood control is triggered.  The offender will be muted for 30 seconds for the first offense.  Each additional offense will result in the offender being muted for a much longer period.  For example, the first offense will result in 30 seconds, the 2nd offense will be 5 minutes, the 3rd will be 1 hour, and so on.  The offense counter is decremented once every 24 hours.

The offender will be sent the following private message: "You have been muted due to flooding.  Please use a web paste service such as http://ideone.com for lengthy pastes.  You will be allowed to speak again in $timeout."

Join flood
----------
If four (4) or more JOINs are observed within thirty (30) minutes *without any messages in between joins*, the offender will be forwarded to another channel for a limited time: 2^(number_of_offenses + 2) hours.

In addition to private instructions from PBot, this channel will have a /topic and ChanServ on-join message with instructions explaining to the offender how to remove the forwarding.  The instructions are to message PBot with: `unbanme`.

Any messages sent to the public channel by the user at any time will reset their JOIN counter back to zero.  The unbanme command can only be used for the first two offenses -- the offense counter is decremented once every 24 hours.

The offender will be sent the following private message: "You have been banned from $channel due to join flooding.  If your connection issues have been resolved, or this was an accident, you may request an unban at any time by responding to this message with: `unbanme`, otherwise you will be automatically unbanned in $timeout."

Enter key abuse
---------------
If four (4) consecutive messages are sent with ten (10) seconds or less between individual messages and without another person speaking, an enter-key-abuse counter is incremented.  This counter will then continue to be incremented every two (2) consecutive messages with ten (10) seconds or less in between until another person speaks or more than ten (10) seconds have elapsed, whereupon it returns to requiring four (4) consecutive messages.  When this counter reaches three (3) or greater, the offender will be muted using the same timeout rules as message flooding.  This counter is automatically decremented once per hour.

The offender will be sent the following private message: "You have been muted due to abusing the enter key.  Please do not split your sentences over multiple messages.  You will be allowed to speak again in $timeout."

Nick flood
----------
If four (4) or more nick-changes are observed within thirty (30) minutes, the nick-change flood control is triggered.  The offender will be muted for 15 minutes for the first offense.  Each additional offense will result in the offender being muted for a much longer period.  The offense counter is decremented once every 24 hours.

The offender will be sent the following private message: "You have been temporarily banned due to nick-change flooding.  You will be unbanned in $timeout."

Anti-away/Nick-control
======================
PBot can detect nick-changes to undesirable nicks such as those ending with |away, as well as undesirable ACTIONs such as /me is away.

When such a case is detected, PBot will kick the offender with a link to http://sackheads.org/~bnaylor/spew/away_msgs.html in the kick message.

Anti-auto-rejoin control
========================
PBot can detect if someone immediately auto-rejoins after having been kicked.

When such a case is detected, PBot will kickban the offender (with a kick message of "$timeout ban for auto-rejoining after kick") for 5 minutes for the first offense. Each additional offense will result in the offender being banned for a much longer period. The offense counter is decremented once every 24 hours.

Opping/Deopping
===============
ChanServ can op and deop PBot as necessary, unless the channel `permop` meta-data is set to a true value. PBot will wait until about 5 minutes have elapsed before requesting a deop from ChanServ. This timeout can be controlled via the `general.deop_timeout` registry value, which can be overriden on a per-channel basis.

