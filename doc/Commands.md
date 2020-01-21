
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
  * [Command documentation](#command-documentation)
    * [Administrative commands](#administrative-commands)
      * [Logging in and out of PBot](#logging-in-and-out-of-pbot)
      * [Admin management commands](#admin-management-commands)
      * [Channel management commands](#channel-management-commands)
      * [Module management commands](#module-management-commands)
      * [Plugin management commands](#plugin-management-commands)
      * [Registry commands](#registry-commands)
      * [Miscellaneous admin commands](#miscellaneous-admin-commands)
    * [Factoid commands](#factoid-commands)
      * [Adding factoids](#adding-factoids)
      * [Viewing factoids](#viewing-factoids)
      * [Deleting factoids](#deleting-factoids)
      * [Aliasing commands](#aliasing-commands)
      * [Moving/renaming factoids](#movingrenaming-factoids)
      * [Editing factoids](#editing-factoids)
      * [Information about a factoid](#information-about-a-factoid)
    * [Miscellaneous commands](#miscellaneous-commands)
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
of the PBot instance can locally add new commands by editing PBot's source code
or by acquiring and loading new Plugins.

#### Plugins

Additional built-in commands can be created by loading PBot Plugins. Plugins are
stand-alone self-contained units of code that can be loaded by the PBot owner.
Plugins have access to PBot's internal APIs and data structures.

### Factoids

Factoids are another type of command. Factoids are simple textual strings that
anybody can create. At their most simple, they simply display their text when
invoked. However, significantly more complex Factoids can be created by using
the powerful interpreter and by using the even more powerful `/code` Factoid
command.

Factoids do not have access to PBot's internal API or data structures.

#### Code Factoids

Code Factoids are simple Factoids that are created using the `/code` command.
These Factoids will execute their textual string using the scripting or programming
language invoked by the `/code` command.

Code Factoids do not have access to PBot's internal API or data structures.

#### Modules

Modules are simple stand-alone external command-line scripts and programs. Just
about any application that can be run in your command-line shell can be loaded as
a PBot module.

Modules do not have access to PBot's internal API or data structures.

## Command documentation

Here is the documentation for all of PBot's commands.

### Administrative commands

#### Logging in and out of PBot

#### Admin management commands

#### Channel management commands

#### Module management commands

#### Plugin management commands

#### Registry commands

#### Miscellaneous admin commands

### Factoid commands

#### Adding factoids

#### Viewing factoids

#### Deleting factoids

#### Aliasing commands

#### Moving/renaming factoids

#### Editing factoids

#### Information about a factoid

### Miscellaneous commands


