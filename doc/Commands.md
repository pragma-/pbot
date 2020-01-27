
# Commands

<!-- md-toc-begin -->
* [Command interpreter](#command-interpreter)
  * [Piping](#piping)
  * [Substitution](#substitution)
  * [Chaining](#chaining)
  * [Variables](#variables)
  * [Inline invocation](#inline-invocation)
* [Types of commands](#types-of-commands)
  * [Built-in commands](#built-in-commands)
    * [Creating new built-in commands](#creating-new-built-in-commands)
    * [Plugins](#plugins)
  * [Factoids](#factoids)
    * [Code Factoids](#code-factoids)
    * [Modules](#modules)
* [Commands documented here](#commands-documented-here)
  * [version](#version)
  * [help](#help)
  * [uptime](#uptime)
  * [my](#my)
  * [date](#date)
  * [weather](#weather)
* [Commands documented elsewhere](#commands-documented-elsewhere)
  * [Administrative commands](#administrative-commands)
    * [Logging in and out of PBot](#logging-in-and-out-of-pbot)
      * [login](Admin.md#login)
      * [logout](Admin.md#logout)
    * [User management commands](#user-management-commands)
      * [useradd](Admin.md#useradd)
      * [userdel](Admin.md#userdel)
      * [userset](Admin.md#userset)
      * [userunset](Admin.md#userunset)
      * [list users](Admin.md#listing-users)
    * [Channel management commands](#channel-management-commands)
      * [join](Admin.md#join)
      * [part](Admin.md#part)
      * [chanadd](Admin.md#chanadd)
      * [chanrem](Admin.md#chanrem)
      * [chanset](Admin.md#chanset)
      * [chanunset](Admin.md#chanunset)
      * [chanlist](Admin.md#chanlist)
      * [ignore](Admin.md#ignore)
      * [unignore](Admin.md#unignore)
      * [whitelist](Admin.md#whitelist)
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
    * [Module management commands](#module-management-commands)
      * [load](Admin.md#load)
      * [unload](Admin.md#unload)
      * [list modules](Admin.md#listing-modules)
    * [Plugin management commands](#plugin-management-commands)
      * [plug](Admin.md#plug)
      * [unplug](Admin.md#unplug)
      * [replug](Admin.md#replug)
      * [pluglist](Admin.md#pluglist)
    * [Command metadata](#command-metadata)
      * [cmdset](Admin.md#cmdset)
      * [cmdunset](Admin.md#cmdunset)
    * [Registry commands](#registry-commands)
      * [regset](Registry.md#regset)
      * [regunset](Registry.md#regunset)
      * [regchange](Registry.md#regchange)
      * [regshow](Registry.md#regshow)
      * [regfind](Registry.md#regfind)
      * [regsetmeta](Registry.md#regsetmeta)
      * [regunsetmeta](Registry.md#regunsetmeta)
    * [Miscellaneous admin commands](#miscellaneous-admin-commands)
      * [export](Admin.md#export)
      * [refresh](Admin.md#refresh])
      * [reload](Admin.md#reload])
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

### Piping
You can pipe output from one command as input into another command, indefinitely.

    <pragma-> !echo hello world | {sed s/world/everybody/} | {uc}
       <PBot> HELLO EVERYBODY

### Substitution
You can insert the output from another command at any point within a command. This
substitutes the command with its output at the point where the command was used.

    <pragma-> !echo This is &{echo a demonstration} of command substitution
       <PBot> This is a demonstration of command substitution

For example, suppose you want to make a Google Image Search command. The naive
way would be to simply do:

    <pragma-> !factadd img /call echo https://google.com/search?tbm=isch&q=$args

Unfortuately this would not support queries containing spaces or certain symbols. But
never fear! We can use command substitution and the `uri_escape` function from the
`func` command.

Note that you must escape the command substitution to insert it literally into the
factoid otherwise it will be expanded first.

    <pragma-> !factadd img /call echo https://google.com/search?tbm=isch&q=\&{func uri_escape $args}

    <pragma-> !img spaces & stuff
       <PBot> https://google.com/search?tbm=isch&q=spaces%20%26%20stuff

### Chaining
You can execute multiple commands sequentially as one command.

    <pragma-> !echo Test! ;;; me smiles. ;;; version
       <PBot> Test! * PBot smiles. PBot version 2696 2020-01-04

### Variables
You can use factoids as variables and interpolate them within commands.

    <pragma-> !factadd greeting "Hello, world"

    <pragma-> !echo greeting is $greeting
       <PBot> greeting is Hello, world

PBot variable interpolation supports [expansion modifiers](doc/Factoids.md#expansion-modifiers), which can be chained to
combine their effects.

    <pragma-> !echo $greeting:uc
       <PBot> HELLO, WORLD

### Inline invocation
You can invoke up to three commands inlined within a message.  If the message
is addressed to a nick, the output will also be addressed to them.

    <pragma-> newuser13: Check the !{version} and the !{help} documentation.
       <PBot> newuser13: PBot version 2696 2020-01-04
       <PBot> newuser13: To learn all about me, see https://github.com/pragma-/pbot/tree/master/doc

## Types of commands
There are several ways of adding new commands to PBot. We'll go over them here.

### Built-in commands
Built-in commands are commands that are internal and native to PBot. They are
executed within PBot's API and context. They have access to PBot internal
subroutine and data structures.

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

## Commands documented here
These are the commands documented in this file. For commands documented in
other files see the [PBot documentation](../doc).

There is also a list of of commands and links to their documentation in the
[Commands documented elsewhere](#commands-documented-elsewhere) section in this file.

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
metadata.

Usage: `my [<key> [value]]`

If `key` is omitted, the command will list all metadata keys and values for your
user account.

    <pragma-> my timezone los angeles
       <PBot> [global] *!*@unaffiliated/pragmatic-chaos: timezone set to los angeles

<!-- -->

    <pragma-> my
       <PBot> Usage: my [<key> [value]]; [global] *!*@unaffiliated/pragmatic-chaos keys:
              autologin => 1; level => 100;  loggedin => 1; name => pragma;
              password => <private>; timezone => los angeles

See also [user metadata list](Admin.md#user-metadata-list).

### date
The `date` command displays the date and time. Note that it uses the Linux
timezone files to find timezones.

Usage: `date [timezone]`

If `timezone` is omitted, the command will show the UTC date and time unless you
have the `timezone` user metadata set on your user account in which case the command
will use that timezone instead.

You may use the [`my`](#my) command to set the user metadata `timezone`
to have the command remember your timezone.

    <pragma-> !date los angeles
       <PBot> It's Mon 27 Jan 2020 04:20:00 PM PST in Los Angeles.

### weather
The `weather` command displays the weather conditions and temperature for a location.

Usage: `weather [location]`

If `location` is omitted, the command will use the `location` user metadata set on your
user account.

You may use the [`my`](#my) command to set the user metadata `location`
to have the command remember your location.

    <pragma-> !weather los angeles
       <PBot> Weather for Los Angeles, CA: Currently: Mostly Sunny: 71F/21C;
              Forecast: High: 72F/22C Low: 53F/11C Warmer with sunshine

## Commands documented elsewhere
### Administrative commands
#### Logging in and out of PBot
##### [login](Admin.md#login)
##### [logout](Admin.md#logout)

#### User management commands
##### [useradd](Admin.md#useradd)
##### [userdel](Admin.md#userdel)
##### [userset](Admin.md#userset)
##### [userunset](Admin.md#userunset)
##### [list users](Admin.md#listing-users)

#### Channel management commands
##### [join](Admin.md#join)
##### [part](Admin.md#part)
##### [chanadd](Admin.md#chanadd)
##### [chanrem](Admin.md#chanrem)
##### [chanset](Admin.md#chanset)
##### [chanunset](Admin.md#chanunset)
##### [chanlist](Admin.md#chanlist)
##### [ignore](Admin.md#ignore)
##### [unignore](Admin.md#unignore)
##### [whitelist](Admin.md#whitelist)
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

#### Module management commands

##### [load](Admin.md#load)
##### [unload](Admin.md#unload)
##### [list modules](Admin.md#listing-modules)

#### Plugin management commands

##### [plug](Admin.md#plug)
##### [unplug](Admin.md#unplug)
##### [replug](Admin.md#replug)
##### [pluglist](Admin.md#pluglist)

#### Command metadata
##### [cmdset](Admin.md#cmdset)
##### [cmdunset](Admin.md#cmdunset)

#### Registry commands

##### [regset](Registry.md#regset)
##### [regunset](Registry.md#regunset)
##### [regchange](Registry.md#regchange)
##### [regshow](Registry.md#regshow)
##### [regfind](Registry.md#regfind)
##### [regsetmeta](Registry.md#regsetmeta)
##### [regunsetmeta](Registry.md#regunsetmeta)

#### Miscellaneous admin commands
##### [export](Admin.md#export)
##### [refresh](Admin.md#refresh])
##### [reload](Admin.md#reload])
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
