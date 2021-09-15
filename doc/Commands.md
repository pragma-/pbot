
# Commands

<!-- md-toc-begin -->
* [Command interpreter](#command-interpreter)
  * [Command invocation](#command-invocation)
  * [Addressing output to users](#addressing-output-to-users)
  * [Inline invocation](#inline-invocation)
  * [Chaining](#chaining)
  * [Piping](#piping)
  * [Substitution](#substitution)
  * [Variables](#variables)
  * [Selectors](#selectors)
  * [Background processing](#background-processing)
* [Types of commands](#types-of-commands)
  * [Built-in commands](#built-in-commands)
    * [Listing all built-in commands](#listing-all-built-in-commands)
    * [Creating new built-in commands](#creating-new-built-in-commands)
    * [Plugins](#plugins)
    * [Functions](#functions)
  * [Factoids](#factoids)
    * [Code Factoids](#code-factoids)
    * [Modules](#modules)
      * [Listing all loaded modules](#listing-all-loaded-modules)
* [Commands documented here](#commands-documented-here)
  * [version](#version)
  * [help](#help)
  * [uptime](#uptime)
  * [my](#my)
  * [date](#date)
  * [weather](#weather)
* [Commands documented elsewhere](#commands-documented-elsewhere)
  * [Administrative](#administrative)
    * [Logging in and out of PBot](#logging-in-and-out-of-pbot)
      * [login](Admin.md#login)
      * [logout](Admin.md#logout)
    * [User-management](#user-management)
      * [useradd](Admin.md#useradd)
      * [userdel](Admin.md#userdel)
      * [userset](Admin.md#userset)
      * [userunset](Admin.md#userunset)
      * [users](Admin.md#listing-users)
    * [Channel-management](#channel-management)
      * [join](Admin.md#join)
      * [part](Admin.md#part)
      * [chanadd](Admin.md#chanadd)
      * [chanrem](Admin.md#chanrem)
      * [chanset](Admin.md#chanset)
      * [chanunset](Admin.md#chanunset)
      * [chanlist](Admin.md#chanlist)
      * [ignore](Admin.md#ignore)
      * [unignore](Admin.md#unignore)
      * [blacklist](Admin.md#blacklist)
      * [op](Admin.md#op)
      * [deop](Admin.md#deop)
      * [voice](Admin.md#voice)
      * [devoice](Admin.md#devoice)
      * [mode](Admin.md#mode)
      * [ban/mute](Admin.md#banmute)
      * [unban/unmute](Admin.md#unbanunmute)
      * [invite](Admin.md#invite)
      * [kick](Admin.md#kick)
      * [nicklist](Admin.md#nicklist)
      * [banlist](Admin.md#banlist)
      * [checkban](Admin.md#checkban)
      * [checkmute](Admin.md#checkmute)
    * [Module-management](#module-management)
      * [load](Admin.md#load)
      * [unload](Admin.md#unload)
      * [list modules](Admin.md#listing-modules)
    * [Plugin-management](#plugin-management)
      * [plug](Admin.md#plug)
      * [unplug](Admin.md#unplug)
      * [replug](Admin.md#replug)
      * [pluglist](Admin.md#pluglist)
    * [Command metadata](#command-metadata)
      * [cmdset](Admin.md#cmdset)
      * [cmdunset](Admin.md#cmdunset)
    * [Event-queue management](#event-queue-management)
      * [eventqueue](Admin.md#eventqueue)
    * [Process-management](#process-management)
      * [ps](Admin.md#ps)
      * [kill](Admin.md#kill)
    * [Registry](#registry)
      * [regset](Registry.md#regset)
      * [regunset](Registry.md#regunset)
      * [regchange](Registry.md#regchange)
      * [regshow](Registry.md#regshow)
      * [regfind](Registry.md#regfind)
      * [regsetmeta](Registry.md#regsetmeta)
      * [regunsetmeta](Registry.md#regunsetmeta)
    * [Message-history/user-tracking](#message-historyuser-tracking)
      * [recall](Admin.md#recall)
      * [aka](Admin.md#aka)
      * [akalink](Admin.md#akalink)
      * [akaunlink](Admin.md#akaunlink)
      * [akadelete](Admin.md#akadelete)
      * [id](Admin.md#id)
    * [Miscellaneous admin commands](#miscellaneous-admin-commands)
      * [export](Admin.md#export)
      * [refresh](Admin.md#refresh)
      * [reload](Admin.md#reload)
      * [sl](Admin.md#sl)
      * [die](Admin.md#die)
  * [Factoid commands](#factoid-commands)
    * [Adding/removing factoids](#addingremoving-factoids)
      * [factadd](Factoids.md#factadd)
      * [factrem](Factoids.md#factrem)
      * [factalias](Factoids.md#factalias)
    * [Displaying factoids](#displaying-factoids)
      * [fact](Factoids.md#fact)
      * [factshow](Factoids.md#factshow)
    * [Editing factoids](#editing-factoids)
      * [factchange](Factoids.md#factchange)
      * [factmove](Factoids.md#factmove)
      * [factundo](Factoids.md#factundo)
      * [factredo](Factoids.md#factredo)
    * [Factoid metadata](#factoid-metadata)
      * [factset](Factoids.md#factset)
      * [factunset](Factoids.md#factunset)
    * [Information about factoids](#information-about-factoids)
      * [factfind](Factoids.md#factfind)
      * [factinfo](Factoids.md#factinfo)
      * [factlog](Factoids.md#factlog)
      * [count](Factoids.md#count)
      * [histogram](Factoids.md#histogram)
      * [top20](Factoids.md#top20)
<!-- md-toc-end -->

## Command interpreter
PBot has a powerful command interpreter with useful functionality.

### Command invocation
There are a number of ways to invoke commands with PBot.

The documentation and syntax of PBot's commands largely follow Unix/POSIX conventions:

Square brackets `[optional]` indicate that the enclosed element (parameter, value, or information) is optional.
You can choose one or more items or no items. Do not type the square brackets themselves in the command line.

Angle brackets `<required>` indicate that the enclosed element (parameter, value, or information) is mandatory.
You are required to replace the text within the angle brackets with the appropriate information.
Do not type the angle brackets themselves in the command line.

A parenthesized set of elements delimited by a vertical bar `(x|y|z)` indicates mutually exclusive choices. You
must pick one and only one. Do not type the parentheses in the command line.

A single command's syntax is:

    <keyword> [arguments]

`<keyword>` is one token containing no whitespace, and is required as denoted by the angle brackets.

`[arguments]` is a list of tokens which can be quoted to contain whitespace, and is optional as denoted by the square brackets.

We will refer to this as `<command>` throughout this documentation.

The most straight-forward way to invoke a command is:

    <bot trigger> <command>

`<bot trigger>` is the bot's trigger sequence, defined in the `general.trigger` registry setting
(defined to be the exclamation mark by default).

Example:

    <pragma-> !echo hi
       <PBot> hi

You can also prefix or postfix address PBot by its nickname:

    <bot nick> <command>
    <command> <bot nick>

Examples:

    <pragma-> PBot: hello
       <PBot> Hi there, pragma-

    <pragma-> bye, PBot
       <PBot> Good-bye, pragma-

### Addressing output to users
There are a number of ways to address command output to users.

You can prefix the `<bot trigger>`-based invocation with the user's nickname:

    <nickname> <bot trigger> <command>

Examples:

    <pragma-> dave: !echo Testing
       <PBot> dave: Testing

    <pragma-> mike: !time
       <PBot> mike: It's Sun 31 May 2020 06:03:08 PM PDT in Los Angeles.

You can use the `tell` keyword:

    tell <nickname> (about|the) <command>

Examples:

    <pragma-> !tell dave about echo Testing
       <PBot> dave: Testing

    <pragma-> !tell mike the time
       <PBot> mike: It's Sun 31 May 2020 06:03:08 PM PDT in Los Angeles.

You can use the `give` keyword:

    give <nickname> <command>

Examples:

    <pragma-> !give dave echo Testing
       <PBot> dave: Testing

    <pragma-> !give mike time
       <PBot> mike: It's Sun 31 May 2020 06:03:08 PM PDT in Los Angeles.

You can use [inline invocation](#inline-invocation), as well -- see the next section.

### Inline invocation
You can invoke up to three commands inlined within a message.  If the message
is addressed to a nick, the output will also be addressed to them.

The syntax for inline invocation is:

    [nickname:] [text] <bot trigger>{ <command> } [text]

`[nickname:]` may optionally be prefixed to the message to address the command output to them.

`[text]` is optional message text that is ignored.

`<bot trigger>` is the bot's command trigger; which defaults to the exclamation mark (!).

`<command>` is the command to invoke.

Example:

    <pragma-> newuser13: Check the !{version} and the !{help} documentation.
       <PBot> newuser13: PBot version 2696 2020-01-04
       <PBot> newuser13: To learn all about me, see https://github.com/pragma-/pbot/tree/master/doc

### Chaining
You can execute multiple commands sequentially as one command.

The syntax for chaining is:

    <command> ;;; <command> [...]

Example:

    <pragma-> !echo Test! ;;; me smiles. ;;; version
       <PBot> Test! * PBot smiles. PBot version 2696 2020-01-04

### Piping
You can pipe output from one command as input into another command, indefinitely.

The syntax for piping is:

    <command> | { <command> } [...]

Example:

    <pragma-> !echo hello world | {sed s/world/everybody/} | {uc}
       <PBot> HELLO EVERYBODY

### Substitution
You can insert the output from another command at any point within a command. This
substitutes the command with its output at the point where the command was used.

The syntax for substitution is:

    <command &{ <command> } >

Example:

    <pragma-> !echo This is &{echo a demonstration} of command substitution
       <PBot> This is a demonstration of command substitution

Suppose you want to make a Google Image Search command. The naive way would be to simply do:

    <pragma-> !factadd img /call echo https://google.com/search?tbm=isch&q=$args

Unfortuately this would not support queries containing spaces or certain symbols. To fix this,
We can use command substitution and the `uri_escape` function from the `func` command.

Note that you must escape the command substitution to insert it literally into the
factoid otherwise it will be expanded first.

    <pragma-> !factadd img /call echo https://google.com/search?tbm=isch&q=\&{func uri_escape $args}

    <pragma-> !img spaces & stuff
       <PBot> https://google.com/search?tbm=isch&q=spaces%20%26%20stuff

### Variables
You can use factoids as variables and interpolate them within commands.

    <pragma-> !factadd greeting "Hello, world"

    <pragma-> !echo greeting is $greeting
       <PBot> greeting is Hello, world

PBot variable interpolation supports [expansion modifiers](Factoids.md#expansion-modifiers), which can be chained to
combine their effects.

    <pragma-> !echo $greeting:uc
       <PBot> HELLO, WORLD

### Selectors
You can select a random item from a selection list and interpolate the value within commands.

The syntax for Selectors is:

    %(<list of selections>)[:modifiers]

`<list of selections>` is a list of items or [`$variables`](Factoids.md#list-variables) separated by a vertical bar.

`[:modifiers]` is an optional list of modifiers, each prefixed with a colon. See [expansion-modifiers](Factoids.md#expansion-modifiers).

Examples:

    <pragma-> !echo This is a %(neat|cool|awesome) bot.
       <PBot> This is a cool bot.

    <pragma-> !echo IRC is %(fun|weird|confusing|amazing):pick_unique(2):enumerate
       <PBot> IRC is weird and fun

You can use Selectors to create a command that picks randomly from a list of commands!

Example:

    <pragma-> !factadd lart /call %(kick|slap|insult) $args
       <PBot> lart added

    <pragma-> !lart someuser
       <PBot> someuser: If I ever need a brain transplant, I'd choose yours because I'd want a brain that had never been used.

    <pragma-> !lart someuser
            * PBot slaps someuser with a large rabid turkey.

To allow an unprivileged (not bot owner, admin, etc) user to use the `kick` command within the `lart` command, you must
set the `cap-override` [Factoid metadata](Factoids.md#factoid-metadata):

    <pragma-> !factset lart cap-override can-kick 1

### Background processing
Any command can be flagged to be executed as a background process. For example, suppose you
make a Plugin that has a command that may potentially take a long time to complete, which could
cause PBot to be non-responsive...

Not a problem! You can use the [`cmdset`](Admin.md#cmdset) command to set the `background-process` [command metadata](Admin.md#command-metadata-list)
and the command will now run as a background process, allowing PBot to carry on with its duties.

The familiar [`ps`](Admin.md#ps) and [`kill`](Admin.md#kill) commands can be used to list and kill the background processes.

You can also [`cmdset`](Admin.md#cmdset) the `process-timeout` [command metadata](Admin.md#command-metadata-list) to set the timeout, in seconds, before the command is automatically killed. Otherwise the `processmanager.default_timeout` [registry value](Registry.md) will be used.

## Types of commands
There are several ways of adding new commands to PBot. We'll go over them here.

### Built-in commands
Built-in commands are commands that are internal and native to PBot. They are
executed within PBot's API and context. They have access to PBot internal
subroutine and data structures.

#### Listing all built-in commands
To list all built-in commands, use the `list commands` command.

Commands prefixed with a `+` require the user to have the respective `can-<command>`
[user-capability](Admin.md#user-capabilities) in order to invoke it.

    <pragma-> list commands
       <PBot> Registered commands: +actiontrigger aka +akadelete +akalink +akaunlink +antispam +ban +ban-exempt banlist battleship +blacklist cap +chanadd +chanlist ... etc

#### Creating new built-in commands
Built-in commands are created via the `register()` function of the `Commands`
module. Such commands are registered throughout PBot's source code. The owner
of the PBot instance can add new commands by editing PBot's source code
or by acquiring and loading Plugins.

* only bot owner can create new built-in commands
* built-in commands have access to PBot internal API functions and data structures

#### Plugins
Additional built-in commands can be created by loading PBot Plugins. Plugins are
stand-alone self-contained units of code that can be loaded by the PBot owner.

* only bot owner can install and load PBot Plugins
* PBot Plugins have access to PBot internal API functions and data structures

#### Functions
Functions are commands that accept input, manipulate it and then output the result. They are extremely
useful with [piping](#piping) or [command substituting](#substitution).

For example, the `uri_escape` function demonstrated in the [Substitution](#substitution) section earlier
makes text safe for use in a URL. We also saw the `sed` and `uc` functions demonstrated in [Piping](#piping).

Functions can be loaded via PBot Plugins.

* only bot owner can load new Functions
* Functions have access to PBot internal API functions and data structures

For more information, see the [Functions documentation.](Functions.md)

### Factoids
Factoids are another type of command. Factoids are simple text commands which
anybody can create. In their most basic form, they simply display their text
when invoked. However, significantly more complex Factoids can be created by
using the [powerful interpreter features](#command-interpreter) and by using the even more powerful
[`/code` Factoid command](Factoids.md#code).

* anybody can create Factoids
* Factoids do not have access to PBot internal API functions and data structures (unless the [`eval`](Admin.md#eval) command is used)

For more information, see the [Factoids documentations.](Factoids.md)

#### Code Factoids
Code Factoids are Factoids whose text begins with the `/code` command.
These Factoids will execute their text using the scripting or programming
language specified by the argument following the `/code` command.

* anybody can create Code Factoids
* Code Factoids do not have access to PBot internal API functions and data structures (unless the [`eval`](Admin.md#eval) command is used)

For more information, see the [Code Factoid documentation.](Factoids.md#code)

#### Modules
Modules are simple stand-alone external command-line scripts and programs. Just
about any application that can be run in your command-line shell can be loaded as
a PBot module.

* only bot owner can install new command-line modules
* Modules do not have access to PBot internal API functions and data structures

For more information, see the [Modules documentation.](Modules.md)

##### Listing all loaded modules
To list all of the currently loaded modules, use the `list modules` command.

    <pragma-> list modules
       <PBot> Loaded modules: ago bashfaq bashpf c11std c2english c99std cdecl cfact cfaq ... etc.

## Commands documented here
These are the commands documented in this file. For commands documented in
other files see the [PBot documentation](../doc).

There is also a list of of commands and links to their documentation in the
[Commands documented elsewhere](#commands-documented-elsewhere) section of this file.

### version
The `version` command displays the currently installed PBot revision and
revision date. It will also check to see if there is a new version available.

    <pragma-> !version
       <PBot> PBot version 2845 2020-01-19; new version available: 2850 2020-01-20!

### help
The `help` command displays useful information about built-in commands and Factoids.

Usage: `help [keyword] [channel]`

### uptime
The `uptime` command displays the date and time your instance of PBot was started
and how long it has been running.

    <pragma-> !uptime
       <PBot> Tue Jan 14 01:55:40 2020 [8 days and 13 hours]

### my
The `my` command allows non-admin users to view and manipulate their user account
metadata. If there is no user account, one will be created with an appropriate
hostmask.

Usage: `my [<key> [value]]`

If `key` is omitted, the command will list all metadata keys and values for your
user account.

    <pragma-> my timezone los angeles
       <PBot> [global] *!*@unaffiliated/pragmatic-chaos: timezone set to los angeles

<!-- -->

    <pragma-> my
       <PBot> Usage: my [<key> [value]]; [global] *!*@unaffiliated/pragmatic-chaos keys:
              autologin => 1; botowner => 1; location => PST, loggedin => 1; name => pragma;
              password => <private>; timezone => los angeles

See also [user metadata list](Admin.md#user-metadata-list).

### date
The `date` command displays the date and time. Note that it uses the Linux
timezone files to find timezones.

Usage: `date [-u <user account>] [timezone]`

If `timezone` is omitted, the command will show the UTC date and time unless you
have the `timezone` user metadata set on your user account in which case the command
will use that timezone instead.

If the `-u <user account>` option is specified, the command will use the `timezone`
user metadata set for `<user account>`.

You may use the [`my`](#my) command to set the user metadata `timezone`
to have the command remember your timezone.

    <pragma-> !date los angeles
       <PBot> It's Mon 27 Jan 2020 16:20:00 PM PST in Los Angeles.

### weather
The `weather` command displays the weather conditions and temperature for a location.

Usage: `weather [-u <user account>] [location]`

If `location` is omitted, the command will use the `location` user metadata set on your
user account.

If the `-u <user account>` option is specified, the command will use the `location`
user metadata set for `<user account>`.

You may use the [`my`](#my) command to set the user metadata `location`
to have the command remember your location.

    <pragma-> !weather los angeles
       <PBot> Weather for Los Angeles, CA: Currently: Mostly Sunny: 71F/21C;
              Forecast: High: 72F/22C Low: 53F/11C Warmer with sunshine

## Commands documented elsewhere
### Administrative
#### Logging in and out of PBot
##### [login](Admin.md#login)
##### [logout](Admin.md#logout)

#### User-management
##### [useradd](Admin.md#useradd)
##### [userdel](Admin.md#userdel)
##### [userset](Admin.md#userset)
##### [userunset](Admin.md#userunset)
##### [users](Admin.md#listing-users)

#### Channel-management
##### [join](Admin.md#join)
##### [part](Admin.md#part)
##### [chanadd](Admin.md#chanadd)
##### [chanrem](Admin.md#chanrem)
##### [chanset](Admin.md#chanset)
##### [chanunset](Admin.md#chanunset)
##### [chanlist](Admin.md#chanlist)
##### [ignore](Admin.md#ignore)
##### [unignore](Admin.md#unignore)
##### [blacklist](Admin.md#blacklist)
##### [op](Admin.md#op)
##### [deop](Admin.md#deop)
##### [voice](Admin.md#voice)
##### [devoice](Admin.md#devoice)
##### [mode](Admin.md#mode)
##### [ban/mute](Admin.md#banmute)
##### [unban/unmute](Admin.md#unbanunmute)
##### [invite](Admin.md#invite)
##### [kick](Admin.md#kick)
##### [nicklist](Admin.md#nicklist)
##### [banlist](Admin.md#banlist)
##### [checkban](Admin.md#checkban)
##### [checkmute](Admin.md#checkmute)

#### Module-management
##### [load](Admin.md#load)
##### [unload](Admin.md#unload)
##### [list modules](Admin.md#listing-modules)

#### Plugin-management
##### [plug](Admin.md#plug)
##### [unplug](Admin.md#unplug)
##### [replug](Admin.md#replug)
##### [pluglist](Admin.md#pluglist)

#### Command metadata
##### [cmdset](Admin.md#cmdset)
##### [cmdunset](Admin.md#cmdunset)

#### Event-queue management
##### [eventqueue](Admin.md#eventqueue)

#### Process-management
##### [ps](Admin.md#ps)
##### [kill](Admin.md#kill)

#### Registry
##### [regset](Registry.md#regset)
##### [regunset](Registry.md#regunset)
##### [regchange](Registry.md#regchange)
##### [regshow](Registry.md#regshow)
##### [regfind](Registry.md#regfind)
##### [regsetmeta](Registry.md#regsetmeta)
##### [regunsetmeta](Registry.md#regunsetmeta)

#### Message-history/user-tracking
##### [recall](Admin.md#recall)
##### [aka](Admin.md#aka)
##### [akalink](Admin.md#akalink)
##### [akaunlink](Admin.md#akaunlink)
##### [akadelete](Admin.md#akadelete)
##### [id](Admin.md#id)

#### Miscellaneous admin commands
##### [export](Admin.md#export)
##### [refresh](Admin.md#refresh)
##### [reload](Admin.md#reload)
##### [sl](Admin.md#sl)
##### [die](Admin.md#die)

### Factoid commands
#### Adding/removing factoids
##### [factadd](Factoids.md#factadd)
##### [factrem](Factoids.md#factrem)
##### [factalias](Factoids.md#factalias)

#### Displaying factoids
##### [fact](Factoids.md#fact)
##### [factshow](Factoids.md#factshow)

#### Editing factoids
##### [factchange](Factoids.md#factchange)
##### [factmove](Factoids.md#factmove)
##### [factundo](Factoids.md#factundo)
##### [factredo](Factoids.md#factredo)

#### Factoid metadata
##### [factset](Factoids.md#factset)
##### [factunset](Factoids.md#factunset)

#### Information about factoids
##### [factfind](Factoids.md#factfind)
##### [factinfo](Factoids.md#factinfo)
##### [factlog](Factoids.md#factlog)
##### [count](Factoids.md#count)
##### [histogram](Factoids.md#histogram)
##### [top20](Factoids.md#top20)
