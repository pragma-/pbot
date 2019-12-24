Factoids
========


<!-- md-toc-begin -->
* [Factoids](#factoids)
    * [Channel namespaces](#channel-namespaces)
    * [Special commands](#special-commands)
      * [/say](#say)
      * [/me](#me)
      * [/call](#call)
      * [/msg](#msg)
    * [Special variables](#special-variables)
      * [$nick](#nick)
      * [$args](#args)
      * [$arg[n]](#argn)
      * [$arg[n:m]](#argnm)
      * [$arglen](#arglen)
      * [$channel](#channel)
      * [$randomnick](#randomnick)
      * [$0](#0)
    * [adlib list variables](#adlib-list-variables)
      * [modifiers](#modifiers)
    * [action_with_args](#action_with_args)
    * [add_nick](#add_nick)
  * [Viewing/triggering a factoid](#viewingtriggering-a-factoid)
  * [Viewing/triggering another channel's factoid](#viewingtriggering-another-channels-factoid)
    * [fact](#fact)
  * [Adding a factoid](#adding-a-factoid)
    * [factadd](#factadd)
  * [Deleting a factoid](#deleting-a-factoid)
    * [factrem](#factrem)
    * [forget](#forget)
  * [Aliasing a factoid](#aliasing-a-factoid)
    * [factalias](#factalias)
  * [Moving/renaming a factoid](#movingrenaming-a-factoid)
    * [factmove](#factmove)
  * [Changing a factoid](#changing-a-factoid)
    * [factchange](#factchange)
    * [factundo](#factundo)
    * [factredo](#factredo)
    * [factset](#factset)
      * [Factoid Metadata List](#factoid-metadata-list)
    * [factunset](#factunset)
  * [Finding a factoid](#finding-a-factoid)
    * [factfind](#factfind)
  * [Information about a factoid](#information-about-a-factoid)
    * [factinfo](#factinfo)
    * [factshow](#factshow)
    * [factset](#factset-1)
    * [factlog](#factlog)
    * [count](#count)
    * [histogram](#histogram)
    * [top20](#top20)
<!-- md-toc-end -->


### Channel namespaces
Factoids added in one channel may be called/triggered in another channel or in private message, providing that the other channel doesn't already have a factoid of the same name (in which case that channel's factoid will be triggered).

Factoids may also be added to a special channel named `global` or `.*`.  Factoids that are set in this channel will be accessible to any channel, including private messages.  However, factoids that are set in a specific channel will override factoids of the same name that are set in the global channel or other channels.

For example, a factoid named `malloc` set in `##c` will be called instead of `malloc` set in `global`, if the factoid were triggered in `##c`; otherwise, the latter 'malloc' will be triggered if the factoid were triggered in another channel.

Similiarily, if there were no `malloc` factoid in the `global` namespace, but only in `##c` and you attempted to use this factoid in a channel other than `##c`, that channel will invoke `##c`'s version of `malloc`, providing that channel doesn't have its own `malloc` factoid.

Likewise, if there is a `malloc` factoid set in `##c++` and the factoid is triggered in the `##c++` channel, then this version of `malloc` will be called instead of the `##c` or the `global` factoid.

However, if you are in a channel that doesn't have a `malloc` factoid and there is no `malloc` factoid in the global channel, and you attempt to call `malloc` then the bot will display a message notifying you that `malloc` is ambiguous and which channels it belongs to so that you may use the [fact](#fact) command to call the correct factoid.

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

Adding a factoid
----------------
### factadd
Usage: `factadd [channel] <keyword> <description>`

To add a factoid to the global channel, use `global` or `.*` as the channel.  `.*` is regex-speak for "everything".

    <pragma-> factadd ##c c /say C rocks!

Deleting a factoid
------------------
### factrem
### forget

To remove a factoid, use the `factrem` or `forget` command.

Usage: `factrem <channel> <keyword>` `forget <channel> <keyword>`

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

