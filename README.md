PBot
----
PBot is a versatile IRC Bot written in Perl

<!-- md-toc-begin -->
  * [Installation / Quick Start](#installation--quick-start)
  * [Features](#features)
    * [Commands](#commands)
    * [Plugins](#plugins)
    * [Factoids](#factoids)
    * [Code Factoids](#code-factoids)
    * [Modules](#modules)
    * [Virtual machine](#virtual-machine)
    * [Useful IRC command improvements](#useful-irc-command-improvements)
    * [Channel management](#channel-management)
    * [Admin management](#admin-management)
    * [Easy configuration](#easy-configuration)
    * [Advanced interpreter](#advanced-interpreter)
      * [piping](#piping)
      * [command substitution](#command-substitution)
      * [command splitting](#command-splitting)
      * [$variable interpolation](#variable-interpolation)
      * [inline commands](#inline-commands)
  * [Documentation](#documentation)
  * [Support](#support)
  * [License](#license)
<!-- md-toc-end -->

Installation / Quick Start
--------------------------
To get up-and-running quickly, check out the [Quick Start guide](doc/QuickStart.md).

Features
--------

### Commands

PBot has several useful core built-in commands. Additional commands can be added to PBot through
Plugins and Factoids.

### Plugins

PBot can dynamically load and unload Perl modules to alter its behavior.

These are some of the plugins that PBot has, there are many more:

Plugin | Description
--- | ---
[GoogleSearch](Plugins/GoogleSearch.pm) | Performs Internet searches using the Google search engine.
[UrlTitles](Plugins/UrlTitles.pm) | When a URL is seen in a channel, intelligently display its title. It will not display titles that are textually similiar to the URL, in order to maintain the channel signal-noise ratio.
[Quotegrabs](Plugins/Quotegrabs.pm) | Grabs channel messages as quotes for posterity. Can grab messages from anywhere in the channel history. Can grab multiple messages at once!
[RemindMe](Plugins/RemindMe.pm) | Lets people set up reminders. Lots of options.
[ActionTrigger](Plugins/ActionTrigger.pm) | Lets admins set regular expression triggers to execute PBot commands or factoids.
[AntiAway](Plugins/AntiAway.pm) | Detects when a person uses annoying in-channel away messages and warns them.
[AutoRejoin](Plugins/AutoRejoin.pm) | Automatically rejoin channels if kicked or removed.
[AntiNickSpam](Plugins/AntiNickSpam.pm) | Detects when a person is spamming an excessive number of nicks in the channel and removes them.
[AntiRepeat](Plugins/AntiRepeat.pm) | Warn people about excessively repeating messages. Kicks if they fail to heed warnings.
[AntiTwitter](Plugins/AntiTwitter.pm) | Warn people about addressing others with `@<nick>`. Kicks if they fail to heed warnings.

There are even a few games!

Plugin | Description
--- | ---
[Spinach](Plugins/Spinach.pm) | An advanced multiplayer Trivia game engine with a twist! A question is shown, everybody privately submits a false answer, all false answers and the true answer is shown, everybody tries to guess the true answer, points are gained when people pick your false answer!
[Battleship](Plugins/Battleship.pm) | The classic Battleship board game, simplified for IRC
[Connect4](Plugins/Connect4.pm) | The classic Connect-4 game.

### Factoids

Factoids are a very special type of command. Anybody interacting with PBot
can create, edit, delete and invoke factoids. Factoids can be locked by the
creator of the factoid to prevent them from being edited by others.

At its most simple, factoids merely output the text the creator sets.

    <pragma-> !factadd hello /say Hello, $nick!
       <PBot> hello added to global channel.

    <pragma-> PBot, hello
       <PBot> Hello, pragma-!

Significantly more complex factoids can be built by using `$variables`, command-substitution,
command-piping, `/code` invocation, and more!

PBot factoids include these advanced features:

* metadata (e.g. owner, times used, last used date, locked, etc)
* advanced argument processing (indexing, splicing, etc)
* special commands: `/say`, `/me`, `/msg`, `/code`, etc
* advanced `$variable` interpolation (`$var:lc` to lowercase contents, `$var:ucfirst` to uppercase first letter, etc)
* factoid-based variable lists (e.g., add a factoid `colors` containing "red green blue" and then `!echo $colors` will randomly pick one)
* changelog history
* undo/redo history
* and much, much more!

For more information, see the [Factoids documentation](doc/Factoids.md).

### Code Factoids

Code Factoids are a special type of factoid that begin with the `/code` command.

    /code <language> <code>

That's right! Anybody can create a factoid that can execute arbitrary code in
[any language](doc/Factoids.md#supported-languages)! This is one of PBot's most powerful features.

How is this safe? Because the code is executed within a virtual machine that
has been configured to fall-back to a previously saved state whenever it times out.

For example, the venerable `rot13` function:

    <pragma-> !factadd rot13 /code sh echo "$@" | tr a-zA-Z n-za-mN-ZA-M
       <PBot> rot13 added to global channel.

    <pragma-> !rot13 Pretty neat, huh?
       <PBot> Cerggl arng, uhu?

You can pipe output from other commands to Code Factoids.

    <pragma-> !echo test | {rot13}
       <PBot> grfg

For more information, see the [Code Factoid documentation](doc/Factoids.md#code).

### Modules

Modules are external command-line executable programs and scripts that can be
loaded via PBot Factoids.

Suppose you have the [Qalculate!](https://qalculate.github.io/) command-line
program and you want to provide a PBot command for it. You can create a _very_ simple
shell script containing:

    #!/bin/sh
    qalc "$*"

And let's call it `qalc.sh` and put it in PBot's `modules/` directory.

Then you can add the `qalc` factoid:

    !factadd global qalc qalc.sh

And then set its `type` to `module`:

    !factset global qalc type module

Now you have a `qalc` calculator in PBot!

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

### Virtual machine

PBot can integrate with a virtual machine to safely execute arbitrary user-submitted
operating system commands or code.

PBot supports [several shells and languages](doc/Factoids.md#supported-languages) out of the box!

    <pragma-> !sh echo Remember rot13? | tr a-zA-Z n-za-mN-ZA-M
       <PBot> Erzrzore ebg13?

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

### Useful IRC command improvements

* `mode` command can take wildcards, e.g. `mode +ov foo* bar*` to op nicks beginning with `foo` and voice nicks beginning with `bar`
* `unban <nick>` and `unmute <nick>` can remove all bans/mutes matching `<nick>`'s hostmask or account
* `ban` and `mute` will intelligently set banmasks; supports timeouts
* `ban` and `mute` can take a comma-separate list of nicks. Will intelligently group them into multiple `MODE +bbbb` commands
* `kick` can take a comma-separated list of nicks; accepts wildcards
* and much, much, more

### Channel management

PBot can perform the typical channel management tasks.

* opping/deopping, etc
* channel-mode tracking
* user hostmask/alias tracking
* ban-evasion detection
* flood detection
* whitelisting, blacklisting, etc
* spam/advertisement detection
* and much, much more

For more information, see the [Channels documentation](doc/Channels.md) and the [AntiAbuse documentation](doc/AntiAbuse.md)

### Admin management

PBot has easy admin management via simple built-in commands.

* admins can be global admins or channel-specific admins
* admins can be required to login with a password
* admins can be set to be permanently logged-in
* admin abilities configured by admin-levels

For more information, see the [Admin documentation.](doc/Admin.md)

### Easy configuration

PBot's settings are contained in a central registry of key/value pairs grouped by sections.

These settings can easily be configured via several methods:

* PBot's command-line arguments
* simple built-in commands (`regset`, `regunset`, etc)
* editing the [`$data_dir/registry`](data/registry) plain-text JSON file

For more information, see the [Registry documentation.](doc/Registry.md)

### Advanced interpreter

PBot has an advanced command interpreter with useful functionality.

#### piping

You can pipe output from one command as input into another command, indefinitely.

    <pragma-> !echo hello world | {sed s/world/everybody/} | {uc}
       <PBot> HELLO EVERYBODY

#### command substitution

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

#### command splitting

You can execute multiple commands sequentially as one command.

    <pragma-> !echo Test! ;;; me smiles. ;;; version
       <PBot> Test! * PBot smiles. PBot version 2696 2020-01-04

#### $variable interpolation

You can use factoids as variables and interpolate them within commands.

    <pragma-> !factadd greeting "Hello, world"

    <pragma-> !echo greeting is $greeting
       <PBot> greeting is Hello, world

#### inline commands

You can invoke up to three commands inlined within a message.  If the message
is address to a nick, the output will also be addressed to them.

    <pragma-> newuser13: Check the !{version} and the !{help} documentation.
       <PBot> newuser13: PBot version 2696 2020-01-04
       <PBot> newuser13: To learn all about me, see https://github.com/pragma-/pbot/tree/master/doc

Documentation
-------------
See the [PBot documentation](doc) for more information.

Support
-------
For questions and support, feel free to join the `#pbot2` channel on the [Freenode](https://freenode.net/kb/answer/chat) IRC network ([Web Chat](https://webchat.freenode.net/#pbot2)).

License
-------
PBot is licensed under the [Mozilla Public License, version 2](https://www.mozilla.org/en-US/MPL/2.0/).
