PBot
----
PBot is a versatile IRC Bot written in Perl

Features
--------

## Advanced Interpreter

PBot has an advanced command interpreter with useful functionality.

* piping
* command substitution
* command separation
* inline commands
* $variable interpolation
* aliases
* and more!

## Factoids

PBot has factoids with advanced features.

* metadata (e.g. owner, times used, last used date, locked, etc)
* advanced argument processing (indexing, splicing, etc)
* special commands: `/say`, `/me`, `/msg`, `/code`, etc
* advanced `$variable` interpolation (`$var:lc` to lowercase contents, `$var:ucfirst` to uppercase first letter, etc)
* factoid-based variable lists (e.g., add a factoid `$colors` containing "red green blue" and then `!echo $colors` will randomly pick one)
* changelog history
* undo/redo history
* and much, much more!

## Code Factoids

Code factoids are a special type of factoid that begin with the `/code` command.

    /code <language> <code>

That's right! Anybody can create a factoid that can execute arbitrary code in
any language! This is one of PBot's most powerful features.

How is this safe? Because the code is executed within a virtual machine that
has been configured to fall-back to a previously saved state whenever it times out.

## Modules

PBot can execute any command-line program or script as an internal command. We call
these modules.

These are just some of the more notable modules; there are several more:

Module | Description
--- | ---
[C-to-English translator](modules/c2english) | Translates C code to natural English sentences.
[C precedence analyzer](modules/paren) | Adds parentheses to C code to demonstrate precedence.
[C Jeopardy! game](modules/cjeopardy) | C programming trivia game based on the Jeopardy! TV game show.
[Virtual machine](modules/compiler_vm) | Executes arbitrary code and commands within a virtual machine.
[C Standard citations](modules/c11std.pl) | Cite specified sections/paragraphs from the C standard.
[dict.org Dictionary](modules/dict.org.pl) | Interface to dict.org for definitions, translations, acronyms, etc.
[Urban Dictionary](modules/urban) | Search Urban Dictionary for definitions.
[Manpages](modules/man.pl) | Display a concise formatting of manual pages (designed for C functions)

## Plugins

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

## Channel management

PBot can perform the expected channel management tasks.

* opping/deopping, etc
* channel-mode tracking
* user hostmask/alias tracking
* ban-evasion detection
* flood detection
* whitelisting, blacklisting, etc
* spam/advertisement detection
* and much, much more

## Admin management

PBot has easy admin management via simple built-in commands.

* admins can be global admins or channel-specific admins
* admins can be required to login with a password
* admins can be set to be permanently logged-in
* admin abilities configured by admin-levels

## Useful IRC command improvements

* `mode` command can take wildcards, e.g. `mode +ov foo* bar*` to op nicks beginning with `foo` and voice nicks beginning with `bar`
* `unban <nick>` and `unmute <nick>` can remove all bans/mutes matching `<nick>`'s hostmask or account
* `ban` and `mute` will intelligently set banmasks; also supports timeouts
* `ban` and `mute` can take a comma-separate list of nicks. Will intelligently group them into multiple `MODE +bbbb` commands
* `kick` can take a comma-separated list of nicks
* `kick` can also accept wildcards
* and much, much, more

## Easy configuration

PBot's settings are contained in a central registry of key/value pairs grouped by sections.

These settings can easily be configured via several methods:

* PBot's command-line arguments
* simple built-in commands (`regset`, `regunset`, etc)
* editing the [`$data_dir/registry`](data/registry) plain-text JSON file

Installation / Quick Start
--------------------------
To get up-and-running quickly, check out the [Quick Start guide](https://github.com/pragma-/pbot/blob/master/doc/QuickStart.md).

Documentation
-------------
See the [PBot documentation](https://github.com/pragma-/pbot/tree/master/doc) for more information.

