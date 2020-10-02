# Plang

<!-- md-toc-begin -->
* [About](#about)
* [The Plang Language](#the-plang-language)
* [PBot commands](#pbot-commands)
  * [plang](#plang-1)
  * [plangrepl](#plangrepl)
* [PBot built-in Plang functions](#pbot-built-in-plang-functions)
  * [factget](#factget)
  * [factset](#factset)
  * [factappend](#factappend)
  * [userget](#userget)
* [Examples](#examples)
  * [Basic examples](#basic-examples)
  * [Karma example](#karma-example)
<!-- md-toc-end -->

## About
The Plang plugin provides a scripting interface to PBot. It has access to PBot
internal APIs and state.

## The Plang Language
The scripting language is [Plang](https://github.com/pragma-/Plang). It was
written specifically for PBot, but aims to be powerful enough to be used as a general-purpose
scripting language embedded into any Perl application.

This document describes PBot's Plang plugin. To learn how to use the Plang scripting
language, see the [Plang documentation](https://github.com/pragma-/Plang/blob/master/README.md).

## PBot commands
### plang
Use the `plang` command to run a Plang script.

Usage: `plang <code>`

### plangrepl
The `plangrepl` command is identical to the `plang` command, except the environment
is preserved in-between commands and the types of values is output along with the value.

## PBot built-in Plang functions
[Plang](https://github.com/pragma-/Plang) lets you add custom built-in functions.
Several have been added for PBot; they are described here.

Function | Description
--- | ---
[factget](#factget) | Retrieve metadata from factoids
[factset](#factset) | Sets metadata on factoids
[factappend](#factappend) | Appends to the `action` metadata on factoids
[userget](#userget) | Retrieve metadata from users

### factget
Use the `factget` function to retrieve metadata from factoids.

Signature: `factget(channel: String, keyword: String, meta: String = "action") -> String | Null`

The `factget` function takes three paramaters: `channel`, `keyword` and `meta`. The `meta`
parameter can be omitted and will default to `"action"`.

The `factget` function returns a `String` containing the value of the factoid metadata or
`null` if the factoid does not exist.

### factset
Use the `factset` function to set metadata values for factoids. The factoid
will be created if it does not exist.

Signature: `factset(channel: String, keyword: String, text: String, meta: String = "action") -> String`

The `factset` function takes four parameters: `channel`, `keyword`, `text`,
and optionally `meta`. If the `meta` parameter is omitted it will default to
`"action"`.

The `factset` function returns a `String` containing the value of `text`.

### factappend
Use the `factappend` function to append text to the `action` metadata for factoids.

Signature: `factappend(channel: String, keyword: String, text: String) -> String`

The `factappend` function takes three parameters: `channel`, `keyword` and `text`.

The `factappend` function returns a `String` containing the value of factoid's `action`
metadata with `text` appended.

### userget
Use the `userget` function to retrieve user metadata.

Signature: `userget(name: String) -> Map | Null`

The `userget` function takes one parameter: `name`.

The `userget` function returns a `Map` containing all the metadata of the user, or
`null` if there is no user matching `name`.

See the [Plang Map documentation](https://github.com/pragma-/Plang#maps) for a refresher on using Plang maps.

## Examples
### Basic examples

    <pragma-> !plang userget('pragma-')
       <PBot> { channels: "global", hostmasks: "*!*@unaffiliated/pragmatic-chaos", botowner: 1 }

    <pragma-> !plang userget('pragma-').botowner
       <PBot> 1

    <pragma-> !plang if userget('pragma-').botowner then print('Greetings master!') else print('Hello mortal.')
       <PBot> Greetings master!

### Karma example

Here is a quick-and-dirty way to make a simple Karma system. This is a demonstration of what is
currently possible with Plang. This will not be its final form. Support for classes will be added
soon.

We'll use the `factget()` and `factset()` functions to get and store Karma values to an
unique unused channel. Let's call it `#karma-data`. To get the first command argument,
we'll use PBot's special factoid variable `$arg[0]`.

First we add the `++` command.

    <pragma-> !factadd ++ /call plang var karma = Integer(factget('#karma-data', '$arg[0]')); karma += 1; factset('#karma-data', '$arg[0]', String(karma));
       <PBot> ++ added to global channel.

Similarly, we add the `--` command.

    <pragma-> !factadd -- /call plang var karma = Integer(factget('#karma-data', '$arg[0]')); karma -= 1; factset('#karma-data', '$arg[0]', String(karma));
       <PBot> -- added to global channel.

Finally, we add the `karma` command.

    <pragma-> !factadd karma /call plang var k = factget('#karma-data', '$arg[0]'); if k == null then print('No karma for $arg[0] yet.') else print($'Karma for $arg[0]: {k}')
       <PBot> karma added to global channel.

A short demonstration:

    <pragma-> !karma nf
       <PBot> No karma for nf yet.

    <pragma-> !-- nf
       <PBot> -1

    <pragma-> !-- nf
       <PBot> -2

    <pragma-> !++ nf
       <PBot> -1

    <pragma-> !karma nf
       <PBot> Karma for nf: -1

You can use double quotes to group multiple words as one argument (but not single quotes due to how `$arg[0]` is inserted
into single-quoted strings in the Plang snippets).

    <pragma-> !++ "this and that"
       <PBot> 1

    <pragma-> !karma "this and that"
       <PBot> Karma for "this and that": 1
