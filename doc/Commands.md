
# Commands

<!-- md-toc-begin -->
  * [About](#about)
  * [Advanced interpreter](#advanced-interpreter)
    * [piping](#piping)
    * [command substitution](#command-substitution)
    * [command splitting](#command-splitting)
    * [advanced $variable interpolation](#advanced-variable-interpolation)
    * [inline commands](#inline-commands)
  * [Types of commands](#types-of-commands)
    * [Built-in commands](#built-in-commands)
      * [Plugins](#plugins)
    * [Factoids](#factoids)
      * [Code Factoids](#code-factoids)
      * [Modules](#modules)
  * [Command documentation](#command-documentation)
    * [Administrative commands](#administrative-commands)
    * [Channel management commands](#channel-management-commands)
    * [Miscellaneous commands](#miscellaneous-commands)
<!-- md-toc-end -->

## About

PBot has an advanced interpreter and several useful core built-in commands.

## Advanced interpreter

PBot has an advanced command interpreter with useful functionality.

### piping

You can pipe output from one command as input into another command, indefinitely.

    <pragma-> !echo hello world | {sed s/world/everybody/} | {uc}
       <PBot> HELLO EVERYBODY

### command substitution

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

### command splitting

You can execute multiple commands sequentially as one command.

    <pragma-> !echo Test! ;;; me smiles. ;;; version
       <PBot> Test! * PBot smiles. PBot version 2696 2020-01-04

### advanced $variable interpolation

You can use factoids as variables and interpolate them within commands.

    <pragma-> !factadd greeting "Hello, world"

    <pragma-> !echo greeting is $greeting
       <PBot> greeting is Hello, world

PBot variable interpolation supports [expansion modifiers](doc/Factoids.md#expansion-modifiers), which can be chained to
combine their effects.

    <pragma-> !echo $greeting:uc
       <PBot> HELLO, WORLD

### inline commands

You can invoke up to three commands inlined within a message.  If the message
is addressed to a nick, the output will also be addressed to them.

    <pragma-> newuser13: Check the !{version} and the !{help} documentation.
       <PBot> newuser13: PBot version 2696 2020-01-04
       <PBot> newuser13: To learn all about me, see https://github.com/pragma-/pbot/tree/master/doc

## Types of commands

There are a few different types of commands in PBot.

### Built-in commands

#### Plugins

### Factoids

#### Code Factoids

#### Modules

## Command documentation

### Administrative commands

### Channel management commands

### Miscellaneous commands


