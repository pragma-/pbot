# PBot
PBot is a versatile IRCv3 Bot written in Perl

<!-- md-toc-begin -->
  * [Installation / Quick Start](#installation--quick-start)
  * [Features](#features)
    * [IRCv3 capable](#ircv3-capable)
    * [Powerful command interpreter](#powerful-command-interpreter)
      * [Piping](#piping)
      * [Substitution](#substitution)
      * [Variables](#variables)
      * [Selectors](#selectors)
      * [Inline invocation](#inline-invocation)
      * [Chaining](#chaining)
      * [Background processing](#background-processing)
    * [Scripting interface](#scripting-interface)
    * [Extensible](#extensible)
      * [Factoids](#factoids)
      * [Code factoids](#code-factoids)
      * [Plugins](#plugins)
      * [Modules](#modules)
      * [Functions](#functions)
    * [Virtual machine to safely execute user-submitted code](#virtual-machine-to-safely-execute-user-submitted-code)
    * [Powerful user management](#powerful-user-management)
    * [Useful IRC quality-of-life improvements](#useful-irc-quality-of-life-improvements)
    * [Channel management and protection](#channel-management-and-protection)
    * [Easy configuration](#easy-configuration)
    * [Live reloading of core modules or data files](#live-reloading-of-core-modules-or-data-files)
  * [Documentation](#documentation)
  * [Frequently Asked Questions](#frequently-asked-questions)
  * [Support](#support)
  * [License](#license)
<!-- md-toc-end -->

## Installation / Quick Start
To get up-and-running quickly, check out the [Quick Start guide](doc/QuickStart.md).

## Features

### IRCv3 capable
PBot supports several features of the IRCv3 specification.

* client capability negotiation
* SASL authentication
* account-notify, extended-join, and more.

### Powerful command interpreter
PBot has a powerful command interpreter with useful functionality, and tons of
built-in commands.

For more information, see the [Commands documentation.](doc/Commands.md)

#### Piping
You can pipe output from one command as input into another command, indefinitely.

    <pragma-> !echo hello world | {sed s/world/everybody/} | {uc}
       <PBot> HELLO EVERYBODY

[Learn more.](doc/Commands.md#piping)

#### Substitution
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

[Learn more.](doc/Commands.md#substitution)

#### Variables
You can use factoids as variables and interpolate them within commands.

    <pragma-> !factadd greeting "Hello, world"

    <pragma-> !echo greeting is $greeting
       <PBot> greeting is Hello, world

PBot variable interpolation supports [expansion modifiers](doc/Factoids.md#expansion-modifiers), which can be chained to
combine their effects.

    <pragma-> !echo $greeting:uc
       <PBot> HELLO, WORLD

[Learn more.](doc/Factoids.md#list-variables)

#### Selectors
You can select a random item from a selection list and interpolate the value within commands.

    <pragma-> !echo This is a %(neat|cool|awesome) bot.
       <PBot> This is a cool bot.

[Learn more.](doc/Commands.md#selectors)

#### Inline invocation
You can invoke up to three commands inlined within a message.  If the message
is addressed to a nick, the output will also be addressed to them.

    <pragma-> newuser13: Check the !{version} and the !{help} documentation.
       <PBot> newuser13: PBot version 2696 2020-01-04
       <PBot> newuser13: To learn all about me, see https://github.com/pragma-/pbot/tree/master/doc

[Learn more.](doc/Commands.md#command-invocation)

#### Chaining
You can execute multiple commands sequentially as one command.

    <pragma-> !echo Test! ;;; me smiles. ;;; version
       <PBot> Test! * PBot smiles. PBot version 2696 2020-01-04

[Learn more.](doc/Commands.md#chaining)

#### Background processing
All of PBot's internal commands complete instantly, but suppose you make a Plugin that provides a command that may potentially take a long time to complete?
Not a problem! You can use the [`cmdset`](doc/Admin.md#cmdset) command to set the `background-process` [command metadata](doc/Admin.md#command-metadata-list)
and the command will now run as a background process, allowing PBot to carry on with its duties.

The familiar [`ps`](doc/Admin.md#ps) and [`kill`](doc/Admin.md#kill) commands can be used to list and kill the background processes.

You can also [`cmdset`](doc/Admin.md#cmdset) the `process-timeout` [command metadata](doc/Admin.md#command-metadata-list) to set the timeout, in seconds, before the command is automatically killed. Otherwise the `processmanager.default_timeout` [registry value](doc/Registry.md) will be used.

### Scripting interface
PBot uses [Plang](https://github.com/pragma-/Plang) as a scripting language. You can use the
scripting language to construct advanced commands that are capable of interacting with PBot
internal API functions.

[Learn more.](doc/Plugins/Plang.md)

### Extensible
Additional commands and functionality can  be added to PBot in the following ways.

#### Factoids
Factoids are a very special type of command. Anybody interacting with PBot
can create, edit, delete and invoke factoids.

A simple factoid merely displays the text the creator sets.

    <pragma-> !factadd hello /say Hello, $nick!
       <PBot> hello added to global channel.

    <pragma-> PBot, hello
       <PBot> Hello, pragma-!

Significantly more complex factoids can be built by using `$variables`, command-substitution,
command-piping, `/code` invocation, command prefixes such as `/say`, `/me`, `/msg`, and more!

PBot factoids include these advanced features:

* [undo/redo history](doc/Factoids.md#factundo)
* [changelog history](doc/Factoids.md#factlog)
* [channel namespaces](doc/Factoids.md#channel-namespaces)
* [`factadd`](doc/Factoids.md#factadd) and [`factchange`](doc/Factoids.md#factchange) commands accept a `-url` option that sets the factoid contents from a paste website. In other words, you can edit a factoid's contents using your local editor, preserving line-breaks and indentation.
* [advanced `$variable` interpolation](doc/Factoids.md#expansion-modifiers) (`$var:lc` to lowercase contents, `$var:ucfirst` to uppercase first letter, etc)
* [factoid-based variable lists](doc/Factoids.md#list-variables) (e.g., add a factoid `colors` containing "red green blue" and then `!echo $colors` will randomly pick one)
* [advanced argument processing](doc/Factoids.md#special-variables-1) (indexing, splicing, etc)
* [metadata](doc/Factoids.md#factoid-metadata) (e.g. owner, times used, last used date, locked, etc)
* [special commands](doc/Factoids.md#special-commands) (`/say`, `/me`, `/msg`, `/code`, etc)
* and much, much more!

For more information, see the [Factoids documentation](doc/Factoids.md).

#### Code factoids
Code factoids are a special type of factoid that executes its contents within a sandboxed virtual machine.

The contents of code factoids must begin with the `/code` command:

    /code <language> <code>

For example, the venerable `rot13` function:

    <pragma-> !factadd rot13 /code sh echo "$@" | tr a-zA-Z n-za-mN-ZA-M
       <PBot> rot13 added to global channel.

    <pragma-> !rot13 Pretty neat, huh?
       <PBot> Cerggl arng, uhu?

Making a `choose` command:

    <pragma-> !factadd choose /code zsh _arr=($args); print $_arr[$((RANDOM % $#_arr + 1))]
       <PBot> choose added to global channel.

Using the `choose` command via an [embedded command](doc/Commands.md#inline-invocation):

    <pragma-> hmm, what should I have for dinner? !{choose chicken "roast beef" pizza meatloaf}
       <PBot> pizza

You can even pipe output from other commands to Code Factoids.

    <pragma-> !echo test | {rot13}
       <PBot> grfg

For more information, see the [Code Factoid documentation](doc/Factoids.md#code).

#### Plugins
PBot can dynamically load and unload Perl modules to alter its behavior.

These are some of the plugins that PBot has; there are many more:

Plugin | Description
--- | ---
[GoogleSearch](Plugins/GoogleSearch.pm) | Performs Internet searches using the Google search engine.
[UrlTitles](Plugins/UrlTitles.pm) | When a URL is seen in a channel, intelligently display its title. It will not display titles that are textually similiar to the URL, in order to maintain the channel signal-noise ratio.
[Quotegrabs](Plugins/Quotegrabs.pm) | Grabs channel messages as quotes for posterity. Can grab messages from anywhere in the channel history. Can grab multiple messages at once!
[Weather](Plugins/Weather.pm) | Fetches and shows weather data for a location.
[Wttr](Plugins/Wttr.pm) | Advanced weather Plugin with tons of options. Uses wttr.in.
[RemindMe](Plugins/RemindMe.pm) | Lets people set up reminders. Lots of options.
[ActionTrigger](Plugins/ActionTrigger.pm) | Lets admins set regular expression triggers to execute PBot commands or factoids.
[AntiAway](Plugins/AntiAway.pm) | Detects when a person uses annoying in-channel away messages and warns them.
[AutoRejoin](Plugins/AutoRejoin.pm) | Automatically rejoin channels if kicked or removed.
[AntiNickSpam](Plugins/AntiNickSpam.pm) | Detects when a person is spamming an excessive number of nicks in the channel and removes them.
[AntiRepeat](Plugins/AntiRepeat.pm) | Warn people about excessively repeating messages. Kicks if they fail to heed warnings.
[AntiTwitter](Plugins/AntiTwitter.pm) | Warn people about addressing others with `@<nick>`. Kicks if they fail to heed warnings.
[Date](Plugins/Date.pm) | Displays date and time for a timezone.

There are even a few games!

Plugin | Description
--- | ---
[Spinach](Plugins/Spinach.pm) | An advanced multiplayer Trivia game engine with a twist! A question is shown. Everybody privately submits a false answer. All false answers and the true answer is shown. Everybody tries to guess the true answer. Points are gained when people pick your false answer!
[Battleship](Plugins/Battleship.pm) | The classic Battleship board game, simplified for IRC
[Connect4](Plugins/Connect4.pm) | The classic Connect-4 game.

#### Modules
Modules are external command-line executable programs and scripts that can be
loaded as PBot commands.

Suppose you have the [Qalculate!](https://qalculate.github.io/) command-line
program and you want to provide a PBot command for it. You can create a _very_ simple
shell script containing:

    #!/bin/sh
    qalc "$*"

And let's call it `qalc.sh` and put it in PBot's `modules/` directory.

Then you can load it with the [`load`](doc/Admin.md#load) command.

    !load qalc qalc.sh

Now you have a [Qalculate!](https://qalculate.github.io/) calculator in PBot!

    <pragma-> !qalc 2 * 2
       <PBot> 2 * 2 = 4

These are just some of the modules PBot comes with; there are several more:

Module | Description
--- | ---
[C-to-English translator](modules/c2english) | Translates C code to natural English sentences.
[C precedence analyzer](modules/paren) | Adds parentheses to C code to demonstrate precedence.
[C Jeopardy! game](modules/cjeopardy) | C programming trivia game based on the Jeopardy! TV game show.
[C Standard citations](modules/c11std.pl) | Cite specified sections/paragraphs from the C standard.
[Virtual machine](modules/compiler_vm) | Executes arbitrary code and commands within a virtual machine.
[dict.org Dictionary](modules/dict.org.pl) | Interface to dict.org for definitions, translations, acronyms, etc.
[Urban Dictionary](modules/urban) | Search Urban Dictionary for definitions.
[Manpages](modules/man.pl) | Display a concise formatting of manual pages (designed for C functions)

For more information, see the [Modules documentation](doc/Modules.md).

#### Functions
Functions are commands that accept input, manipulate it and then output the result. They are extremely
useful with [piping](#piping) or [command substituting](#substitution).

For example, the `uri_escape` function demonstrated in the [Substitution](#substitution) section earlier
makes text safe for use in a URL.

    <pragma-> uri_escape thing's & words
       <PBot> thing%27s%20%26%20words

We also saw the `sed` and `uc` functions demonstrated in [Piping](#piping). The `sed` function
replaces text using a substitution regex. The `uc` function uppercases the text.

    <pragma-> echo Hello world! | {sed s/world/universe/} | {uc}
       <PBot> HELLO UNIVERSE!

Here's a short list of the Functions that come with PBot.

Name | Description
--- | ---
`uri_escape` | Percent-encodes unsafe URI characters.
`sed` | Performs sed-like regex substitution.
`grep` | Searches a string for a regex and prints the matching whole-word (e.g. `echo pizza hamburger hotdog | {grep burger}` outputs `hamburger`).
`pluralize` | Intelligently makes a word or phrase plural.
`unquote` | Removes surrounding quotation marks.
`title` | Title-cases text. That is, lowercases the text then uppercases the first letter of each word.
`ucfirst` | Uppercases the first character of the text.
`uc` | Uppercases all characters.
`lc` | Lowercases all characters.

Additional Functions can easily be added by making a very simple PBot Plugin.

For more information, see the [Functions documentation](doc/Functions.md).

### Virtual machine to safely execute user-submitted code
PBot can integrate with a virtual machine to safely execute arbitrary user-submitted
operating system commands or code.

PBot supports [several shells and languages](doc/Factoids.md#supported-languages) out of the box!

One of PBot's most powerful features, [Code Factoids](#code-factoids), would not be possible without this.

    <pragma-> !sh echo Remember rot13? | tr a-zA-Z n-za-mN-ZA-M
       <PBot> Erzrzore ebg13?

<!-- -->

        <nil> !go package main\nimport "fmt"\nfunc main() { fmt.Print("foo" == "foo"); }
       <PBot> true

<!-- -->

    <pragma-> !python print('Hello there!')
       <PBot> Hello there!

PBot has extensive support for the C programming language. For instance, the C programming language
plugin is integrated with the GNU Debugger. It will print useful debugging information.

    <pragma-> !cc char *p = 0; *p = 1;
       <PBot> runtime error: store to null pointer of type 'char'
              Program received signal SIGSEGV, Segmentation fault at
              statement: *p = 1; <local variables: p = 0x0>

It can display the value of the most recent statement if there is no program output.

    <pragma-> !cc sizeof (int)
       <PBot> no output: sizeof(int) = 4

For more information about the C programming language plugin, see [the `cc` command in the Modules documentation.](doc/Modules.md#cc)

For more information about the virtual machine, see the [Virtual Machine documentation.](doc/VirtualMachine.md)

### Powerful user management
PBot has powerful yet simple user management functionality and commands.

* instead of generic access-levels, [fine-grained user capabilities](doc/Admin.md#user-capabilities) limit what users may do
* user accounts can be global or channel-specific
* users can be recognized by hostmask or required to login with password
* users can adjust their [user-metadata](doc/Admin.md#user-metadata-list) with the [`my`](doc/Commands.md#my) command
* and much, much more!

For more information, see the [Admin documentation.](doc/Admin.md#user-management-commands)

### Useful IRC quality-of-life improvements
* [`mode`](doc/Admin.md#mode) command can take wildcards, e.g. `mode +ov foo* bar*` to op nicks beginning with `foo` and voice nicks beginning with `bar`
* `unban <nick>` and `unmute <nick>` will remove all bans/mutes matching their current or previously seen hostmasks or accounts
* [`ban`](doc/Admin.md#banmute) and [`mute`](doc/Admin.md#banmute) will intelligently set banmasks; supports timeouts
* [`ban`](doc/Admin.md#banmute) and [`mute`](doc/Admin.md#banmute) can take a comma-separate list of nicks. Will intelligently group them into multiple `MODE +bbbb` commands
* [`kick`](doc/Admin.md#kick) can take a comma-separated list of nicks; also accepts wildcards
* and much, much more!

For more information, see the [Admin documentation.](doc/Admin.md)

### Channel management and protection
PBot can perform the typical channel management tasks.

* opping/deopping, etc
* channel-mode tracking
* user hostmask/alias tracking
* ban-evasion detection
* flood detection
* whitelisting, blacklisting, etc
* spam/advertisement detection
* and much, much more!

For more information, see the [Channels documentation](doc/Admin.md#channel-management-commands) and the [Anti-abuse documentation](doc/AntiAbuse.md)

### Easy configuration
PBot's settings are contained in a central registry of key/value pairs grouped by sections.

These settings can easily be configured via several methods:

* [PBot's command-line arguments](doc/Registry.md#overriding-registry-values-via-command-line)
* [simple built-in commands (`regset`, `regunset`, etc)](doc/Registry.md#registry-commands)
* [editing](doc/Registry.md#editing-registry-file) the [`$data_dir/registry`](data/registry) plain-text JSON file

For more information, see the [Registry documentation.](doc/Registry.md)

### Live reloading of core modules or data files
Suppose you edit some PBot source file, be it a core file such as [PBot/Interpreter.pm](PBot/Interpreter.pm) or
a Plugin such as [Plugins/Wttr.pm](Plugins/Wttr.pm). Or suppose there's a PBot update available. Most simple
bots would require you to shut down the bot and restart it in order to see the modifications.

Not PBot! you can simply use the [`refresh`](doc/Admin.md#refresh) command to reload all modified
PBot core files and Plugins without bot restart.

You can also use the [`reload`](doc/Admin.md#reload) command to reload any modified
configuration or data files.

## Documentation
See the [PBot documentation](doc) for more information.

## Frequently Asked Questions
If you have a question, try the [PBot FAQ](doc/FAQ.md)!

## Support
For additional questions and support, feel free to join the `#pbot` channel on the [Libera.Chat](https://libera.chat/guides) IRC network ([Web Chat](https://web.libera.chat/#pbot)).

## License
PBot is licensed under the [Mozilla Public License, version 2](https://www.mozilla.org/en-US/MPL/2.0/).
