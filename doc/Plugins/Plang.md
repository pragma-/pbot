# Plang

<!-- md-toc-begin -->
* [About](#about)
* [The Plang Language](#the-plang-language)
* [`plang` command](#plang-command)
* [`plangrepl` command](#plangrepl-command)
* [PBot built-in Plang functions](#pbot-built-in-plang-functions)
  * [factget](#factget)
  * [factset](#factset)
  * [factappend](#factappend)
  * [userget](#userget)
<!-- md-toc-end -->

## About
The Plang plugin provides a scripting interface to PBot. It has access to PBot
internal APIs and state.

## The Plang Language
The scripting language is [Plang](https://github.com/pragma-/Plang). It was
written specifically for PBot, but is powerful enough to be used as a general-purpose
scripting language embedded into any Perl application.

This document describes PBot's Plang plugin. To learn how to use the Plang scripting
language, see the [Plang documentation](https://github.com/pragma-/Plang/blob/master/README.md).

## `plang` command
Use the `plang` command to run a Plang script.

Usage: `plang <code>`

## `plangrepl` command
The `plangrepl` command is identical to the `plang` command, except the environment
is preserved in-between commands and the types of values is output along with the value.

## PBot built-in Plang functions
[Plang](https://github.com/pragma-/Plang) lets you add custom built-in functions.
Several have been added for PBot; they are described here.

### factget
    factget(channel, keyword, meta = "action")

Use the `factget` function to retrieve metadata from factoids.

The `factget` function takes three paramaters: `channel`, `keyword` and `meta`. The `meta`
parameter can be omitted and will default to `"action"`.

The `factget` function returns a `String` containing the value of the factoid metadata key.

### factset
    factset(channel, keyword, text)

Use the `factset` function to set the `action` metadata value for factoids.

The `factset` function takes three parameters: `channel`, `keyword` and `text`.

The `factset` function returns a `String` containing the value of `text`.

### factappend
    factappend(channel, keyword, text)

Use the `factappend` function to append text to the `action` metadata for factoids.

The `factappend` function takes three parameters: `channel`, `keyword` and `text`.

The `factappend` function returns a `String` containing the value of factoid's `action`
metadata with `text` appended.

### userget
    userget(name)

Use the `userget` function to retrieve user metadata.

The `userget` function takes one parameter: `name`.

The `userget` function returns a `Map` containing all the metadata of the user, or
`nil` if there is no user matching `name`.

See the [Plang Map documentation](https://github.com/pragma-/Plang#map) for a refresher on using Plang maps.

Examples:

    <pragma-> !plang userget('pragma-')
       <PBot> { channels: "global", hostmasks: "*!*@unaffiliated/pragmatic-chaos", botowner: 1 }

    <pragma-> !plang userget('pragma-')['botowner']
       <PBot> 1
