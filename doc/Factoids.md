# Factoids

<!-- md-toc-begin -->
* [About](#about)
* [Special commands](#special-commands)
  * [/say](#say)
  * [/me](#me)
  * [/call](#call)
  * [/msg](#msg)
  * [/code](#code)
    * [Supported languages](#supported-languages)
    * [Special variables](#special-variables)
    * [testargs example](#testargs-example)
    * [Setting a usage message](#setting-a-usage-message)
    * [poll/vote example](#pollvote-example)
    * [SpongeBob Mock meme example](#spongebob-mock-meme-example)
    * [Using command-piping](#using-command-piping)
    * [Improving SpongeBob Mock meme](#improving-spongebob-mock-meme)
    * [Formatting and editing lengthy Code Factoids](#formatting-and-editing-lengthy-code-factoids)
* [Special variables](#special-variables-1)
  * [$args](#args)
  * [$arg[n]](#argn)
  * [$arg[n:m]](#argnm)
  * [$arglen](#arglen)
  * [$channel](#channel)
  * [$nick](#nick)
  * [$randomnick](#randomnick)
  * [$0](#0)
* [List variables](#list-variables)
  * [Expansion modifiers](#expansion-modifiers)
* [action_with_args](#action_with_args)
* [add_nick](#add_nick)
* [Channel namespaces](#channel-namespaces)
* [Adding/removing factoids](#addingremoving-factoids)
  * [factadd](#factadd)
  * [factrem](#factrem)
  * [forget](#forget)
  * [factalias](#factalias)
* [Displaying factoids](#displaying-factoids)
  * [fact](#fact)
  * [factshow](#factshow)
* [Editing factoids](#editing-factoids)
  * [factchange](#factchange)
  * [factmove](#factmove)
  * [factundo](#factundo)
  * [factredo](#factredo)
* [Factoid metadata](#factoid-metadata)
  * [factset](#factset)
  * [factunset](#factunset)
  * [Factoid metadata List](#factoid-metadata-list)
* [Information about factoids](#information-about-factoids)
  * [factfind](#factfind)
  * [factinfo](#factinfo)
  * [factlog](#factlog)
  * [factset](#factset-1)
  * [count](#count)
  * [histogram](#histogram)
  * [top20](#top20)
<!-- md-toc-end -->

## About
Factoids are a very special type of command. Anybody interacting with PBot can create, edit, delete and invoke factoids. Factoids can be locked by the creator of the factoid to prevent them from being edited by others.

At its most simple, a factoid merely displays the text the creator sets.

    <pragma-> !factadd hello /say Hello, $nick!
       <PBot> hello added to global channel.

    <pragma-> PBot, hello
       <PBot> Hello, pragma-!

Significantly more complex factoids can be built by using $variables, command-substitution, command-piping, /code invocation, and more. Read on!

## Special commands
### /say
If a factoid begins with `/say` then PBot will not use the `<factoid> is <description>` format when displaying the factoid. Instead, it will simply say only the `<description>`.

    <pragma-> !factadd global hi /say Well, hello there, $nick.
       <PBot> hi added to the global channel

       <prec> PBot, hi
       <PBot> Well, hello there, prec.

### /me
If a factoid begins with `/me` then PBot will `CTCP ACTION` the factoid.

    <pragma-> !factadd global bounce /me bounces around.
       <PBot> bounce added to the global channel

    <pragma-> !bounce
            * PBot bounces around.

### /call
If a factoid begins with `/call` then PBot will call an existing command. This is what [`factalias`](#factalias) does internally.

    <pragma-> !factadd global boing /call bounce
       <PBot> boing added to the global channel

    <pragma-> !boing
            * PBot bounces around.

### /msg
If a factoid begins with `/msg <nick>` then PBot will privately message the factoid text to `<nick>`. Only admins can use this command.

### /code
Code Factoids are a special type of factoid whose text is treated as code and executed with a chosen programming language
or interpreter. The output from code is then parsed and treated like any other factoid text. This allows anybody to add
new and unique commands to PBot without the need for installing Plugins or modules.

Code Factoids are executed within a virtual machine. You must install and set up a virtual machine with your operating system.
See the [Virtual Machine](VirtualMachine.md) documentation for more information.

To create a Code Factoid, use the `/code` command. The syntax is:

    factadd <keyword> /code <language> <code>

The `<language>` parameter selects a programming/scripting language or interpreter to use.

#### Supported languages

As of this writing, these are the languages and interpreters that PBot supports. It is easy to add additional
languages or interpreters.

Name | Description
--- | ---
[bash](../modules/compiler_vm/languages/bash.pm) | Bourne-again Shell scripting language
[bc](../modules/compiler_vm/languages/bc.pm) | An arbitrary precision calculator language
[bf](../modules/compiler_vm/languages/bf.pm) | BrainFuck esoteric language
[c11](../modules/compiler_vm/languages/c11.pm) | C programming language using GCC -std=c11
[c89](../modules/compiler_vm/languages/c89.pm) | C programming language using GCC -std=c89
[c99](../modules/compiler_vm/languages/c99.pm) | C programming language using GCC -std=c99
[clang11](../modules/compiler_vm/languages/clang11.pm) | C programming language using Clang -std=c11
[clang89](../modules/compiler_vm/languages/clang89.pm) | C programming language using Clang -std=c89
[clang99](../modules/compiler_vm/languages/clang99.pm) | C programming language using Clang -std=c99
[clang](../modules/compiler_vm/languages/clang.pm) | Alias for `clang11`
[clangpp](../modules/compiler_vm/languages/clangpp.pm) | C++ programming language using Clang
[clisp](../modules/compiler_vm/languages/clisp.pm) | Common Lisp dialect of the Lisp programming language
[cpp](../modules/compiler_vm/languages/cpp.pm) | C++ using GCC
[freebasic](../modules/compiler_vm/languages/freebasic.pm) | FreeBasic BASIC compiler/interpreter
[go](../modules/compiler_vm/languages/go.pm) | Golang programming language
[haskell](../modules/compiler_vm/languages/haskell.pm) | Haskell programming language
[java](../modules/compiler_vm/languages/java.pm) | Java programming language
[javascript](../modules/compiler_vm/languages/javascript.pm) | JavaScript programming language
[ksh](../modules/compiler_vm/languages/ksh.pm) | Korn shell scripting language
[lua](../modules/compiler_vm/languages/lua.pm) | Lua programming language
[perl](../modules/compiler_vm/languages/perl.pm) | Perl programming language
[python3](../modules/compiler_vm/languages/python3.pm) | Python3 programming language
[python](../modules/compiler_vm/languages/python.pm) | Python programming language
[qbasic](../modules/compiler_vm/languages/qbasic.pm) | QuickBasic option using FreeBasic
[ruby](../modules/compiler_vm/languages/ruby.pm) | Ruby programming language
[scheme](../modules/compiler_vm/languages/scheme.pm) | Scheme dialect of the Lisp programming language
[sh](../modules/compiler_vm/languages/sh.pm) | Bourne Shell scripting language
[tcl](../modules/compiler_vm/languages/tcl.pm) | TCL scripting language
[zsh](../modules/compiler_vm/languages/zsh.pm) | Z Shell scripting language

#### Special variables

All the variables listed in [Special Variables](#special-variables-1) are expanded within Code Factoids before
the code is executed or interpreted.

[List variables](#list-variables) are also expanded beforehand as well. You can prevent this by using [`factset`](#factset)
to set the `interpolate` [factoid metadata](#factoid-metadata) to `0`. Alternatively, you can prevent `$variables` in
the code from expanding by prefixing their name with an underscore, i.e. `$_variable`.

#### testargs example

Let's make a simple Code Factoid that demonstrates command-line arguments. Let's use
the C programming language because why not?

    <pragma-> !factadd testargs /code c11 printf("/say args: "); while (*++argv) printf("[%s] ", *argv);
       <PBot> testargs added to the global channel.

    <pragma-> testargs foo bar
       <PBot> args: [foo] [bar]

    <pragma-> testargs "abc 123" xyz
       <PBot> args: [abc 123] [xyz]

#### Setting a usage message

Suppose you want the command to display a usage message if there are no arguments provided. You can use
the [`factset`](#factset) command to set the `usage` [factoid metadata](#factoid-metadata).

     <pragma-> !testargs
        <PBot> args:

     <pragma-> !factset testargs usage Usage: testargs <arguments>
        <PBot> [global] testcargs 'usage' set to 'Usage: testargs <arguments>'

     <pragma-> !testargs
        <PBot> Usage: testargs <arguments>

#### poll/vote example

Here is a basic poll/vote example. Let's use Perl this time.

First we add the factoids. Note that we use `$_variable` with underscore prefixing
the name to prevent them from being expanded as [List Variables](#list-variables).

    <pragma-> !factadd startvote /code perl use Storable; my $_question = "@ARGV";
              print "Starting poll: $_question Use `vote <keyword>` to record your vote.";
              my %_votes = (); my @data = ({%_votes}, $_question);
              system 'rm -rf vote-data'; mkdir 'vote-data' or print "$!";
              store \@data, 'vote-data/data';

    <pragma-> !factset startvote usage Usage: startvote <question>

    <pragma-> !factadd vote /code perl use Storable; my $_data = retrieve 'vote-data/data';
              my %_votes = %{shift @$_data}; ($_votes{"$nick"}) = (lc "@ARGV");
              unshift @$_data, {%_votes}; store $_data, 'vote-data/data';

    <pragma-> !factset vote usage Usage: vote <keyword>

    <pragma-> !factadd votes /code perl no warnings; use Storable; my $_data = retrieve 'vote-data/data';
              my %_votes = %{shift @$_data}; my $_question = shift @$_data;
              if (not keys %_votes) { print "No votes for \"$_question\" yet."; exit; }
              my %_count; map { $_count{$_}++ } values %_votes;
              my $_result = "Poll results for \"$_question\": "; my $_comma = "";
              map { $_result .= "$_comma$_: $_count{$_}"; $_comma = ', '; }
              sort { $_count{$b} <=> $_count{$a} } keys %_count; print "/say $_result";

And action:

    <pragma-> !startvote Isn't this cool?
       <PBot> Starting poll: Isn't this cool? Use `vote <keyword>` to record your vote.

    <pragma-> !vote yes
    <luser69> !vote no
    <someguy> !vote yes
     <derpy3> !vote hamburger

    <pragma-> !votes
       <PBot> Poll results for "Isn't this cool?": yes: 2, no: 1, hamburger: 1

#### SpongeBob Mock meme example

Here is an example demonstrating how Code Factoids and command piping can work together.

The SpongeBob Mock meme takes something ridiculous somebody said and repeats it with the
letters in alternating lower and upper case.

    <derpy3> Girls are dumb!
     <SpBob> smh @ derpy3... gIrLs ArE dUmB!

Let's make a command, using a Code Factoid, to do this! `sm` stands for "SpongeBob Mock".
This time we'll use the Bash shell scripting language.

    <pragma-> !factadd sm /code bash echo "${@,,}"|perl -pe 's/(?<!^)[[:alpha:]].*?([[:alpha:]]|$)/\L\u$&/g'

    <pragma-> !factset sm usage Usage: sm <text>

    <pragma-> !sm Testing one, two...
       <PBot> tEsTiNg OnE, tWo...

#### Using command-piping

You can pipe the output of other commands to Code Factoids.

    <pragma-> !echo Testing three, four... | {sm}
       <PBot> tEsTiNg ThReE, fOuR...

    <pragma-> !version | {sm}
       <PBot> pBoT vErSiOn 2696 2020-01-04

#### Improving SpongeBob Mock meme

Let's improve the SpongeBob Mock meme by using the `recall` command to select
the mock text for us.

First of all, the `recall` command prints output like this:

     <derpy3> Girls are dumb!
    <pragma-> !recall derpy3 girls
       <PBot> [5m30s ago] <derpy3> Girls are dumb!

So we're going to use the `func` command to invoke the built-in `sed` function
to strip the timestamp and the name, leaving only the message. `smr` stands for
"SpongeBob Mock Recall".

    <pragma-> !factadd smr /call recall $args | {func sed s/^.*?\] (<.*?> )?(\S+:\s*)?//} | {sm}

     <derpy3> Girls are dumb!
    <pragma-> !smr derpy3 girls
       <PBot> gIrLs ArE dUmB!

We can make an alias with a more friendly name.

    <pragma-> !factalias mock smr

If the recalled message is the most recent, there is no need to use an argument (e.g., `girls`).

     <derpy3> Girls are dumb!
    <pragma-> !mock derpy3
       <PBot> gIrLs ArE dUmB!

#### Formatting and editing lengthy Code Factoids

The poll Code Factoid examples got pretty long, didn't they? It can be quite
difficult read them with the [`factshow`](#factshow) command. Editing them in
your IRC client can be awkward, too. What if you could use your local system's
text editor instead? And then upload the text to a Web-based paste site whose
URL you can give to PBot to update the factoid? Guess what? You can!

The [`factadd`](#factadd) command accepts a `-url` option that allows you
to set PBot factoid contents from an external Web-based text paste site. This
allows you to use your local text editor to craft Code Factoids that contain
line-breaks and indentation. You may combine this with the `-f` option to
force overwriting an existing Code Factoid with your latest modifications.

Likewise, the [`factshow`](#factshow) command accepts a `-p` option that will
paste the contents of the factoid to a Web paste site. This allows you to read
the factoid with its formatting preserved. You can also copy the paste to your
local text editor.

## Special variables
You can use the following variables in a factoid or, in some cases, as an argument to one.

### $args
`$args` expands to any text following the keyword.  If there is no text then it expands to the nick of the caller.

### $arg[n]
`$arg[n]` expands to the nth argument. Indexing begins from 0 (the first argument is `$arg[0]`).  You may use a negative number to count from the end; e.g., `$arg[-2]` means the 2nd argument from the end. Multiple words can be double-quoted to constitute one argument. If the argument does not exist, the variable and the leading space before it will be silently removed.

### $arg[n:m]
`$arg[n:m]` expands to a slice of arguments between `n` and `m`.  Indexing begins from 0 (the first argument is `$arg[0]`).  Omitting the `m` value will use up the arguments after the `n`th value; e.g., `$arg[2:]` means the remaining arguments after the first two.  Multiple words can be double-quoted to constitute one argument. If the argument does not exist, the variable and the leading space before it will be silently removed.

### $arglen
`$arglen` expands to the number of arguments provided to a factoid.

### $channel
`$channel` expands to the name of the channel in which the factoid is used.

### $nick
`$nick` expands to the nick of the caller.

### $randomnick
`$randomnick` expands to a random nick from the channel in which the factoid is used. Filtered to nicks who have spoken in channel in the last two hours.

### $0
`$0` expands to the original keyword used to invoke a factoid.

## List variables
You may create a factoid containing a list of values. Each value can optionally be quoted to preserve spaces within.

When this factoid is used as a `$variable` a random value will be selected from the list. You can further control
which or how many values are chosen via [expansion modifiers](#expansion-modifiers).

For example, first create a normal factoid.

    <pragma-> !factadd global colors is red green blue "bright yellow" pink "dark purple" orange
        <PBot> colors added to the global channel

Then use the factoid as a `$variable`.

    <pragma-> !echo $colors
       <PBot> red

<!-- -->

    <pragma-> !factadd global sky is /say The sky is $colors.
       <PBot> sky added to the global channel

    <pragma-> !sky
       <PBot> The sky is dark purple.

    <pragma-> !sky
       <PBot> The sky is green.

Another example, creating the RTFM trigger:

    <pragma-> !factadd global sizes is big large tiny small huge gigantic teeny
       <PBot> sizes added to the global channel

    <pragma-> !factadd global attacks is whaps thwacks bashes smacks punts whacks
       <PBot> attacks added to the global channel

    <pragma-> !factadd global rtfm is /me $attacks $args with a $sizes $colors manual.
       <PBot> rtfm added to the global channel

    <pragma-> !rtfm mauke
            * PBot thwacks mauke with a big red manual.

### Expansion modifiers
List `$variables` can accept trailing expansion modifier keywords prefixed with a colon. These can be chained together to combine their effects.

There are two categories of expansion modifiers. Selection modifiers and text modifiers.

Selection modifiers control how values are chosen from the `$variable`'s list.

    <pragma-> !echo $colors:pick(3)
       <PBot> red pink green

Note that modifiers may not contain spaces. `:pick(2, 3)` is invalid and must be written as `:pick(2,3)`.

Modifier | Description
--- | ---
`:<channel>` | Looks for variable in `<channel>` first; use `global` to refer to the global channel. This modifier must be the first modifier when chained with other modifiers.
`:index(n)` | Selects the `n`th element from the `$variable` list.
`:pick(x)` | Selects `x` count of random elements.
`:pick(x,y)` | Selects between `x` and `y`, inclusive, count of random elements.
`:pick_unique(x,y)` | Selects between `x` and `y`, inclusive, count of random elements without any repeated selections.

Text modifiers alter the selected values.

    <pragma-> !echo $colors:uc
       <PBot> RED

    <pragma-> !echo $colors:ucfirst
       <PBot> Blue

Modifier | Description
--- | ---
`:uc` | Uppercases the expansion.
`:lc` | Lowercases the expansion.
`:ucfirst` | Uppercases the first letter in the expansion.
`:title` | Lowercases the expansion and then uppercases the initial letter of each word.

The following text modifiers apply only to selection modifiers that return more than one selection. Using them otherwise has no effect.

Modifier | Description
--- | ---
`:sort` | Sorts the selected list in ascending order.
`:-sort` | Sorts the selected list in descending order.
`:comma` | Converts a selected list to a comma-separated list.
`:enumerate` | Converts a selected list to a comma-separated list with `and` replacing the final comma.

    <pragma-> !echo $colors:pick(5):comma
       <PBot> red, yellow, blue, dark purple, orange

    <pragma-> !echo $colors:pick(5):enumerate
       <PBot> blue, green, pink, orange and yellow

## action_with_args
You can use the [`factset`](#factset) command to set a special [factoid metadata](#factoid-metadata) key named `action_with_args` to trigger an alternate message if an argument has been supplied.

    <pragma-> !factadd global snack is /me eats a cookie.
       <PBot> snack added to the global channel

    <pragma-> !factset global snack action_with_args /me gives $args a cookie.
       <PBot> [Factoids] (global) snack: 'action_with_args' set to '/me gives $args a cookie.'

    <pragma-> !snack
            * PBot eats a cookie.

    <pragma-> !snack orbitz
            * PBot gives orbitz a cookie.

## add_nick
You can use the [`factset`](#factset) command to set a special [factoid metadata](#factoid-metadata) key named `add_nick` to prepend the nick of the caller to the output.  This is mostly useful for modules.

## Channel namespaces
Factoids added in one channel may be called/triggered in another channel or in private message, providing that the other channel doesn't already have a factoid of the same name (in which case that channel's factoid will be triggered).

Factoids may be added to a special channel named `global`. Factoids that are set in this channel will be accessible to any channels. Factoids that are set in a specific channel will override factoids of the same name that are set in the `global` channel or other channels.

For example, if there were factoid named `malloc` set in `##c` and in `global`, and you invoke it in `##c` then the `##c` version would be used. If the factoid were triggered in any other channel, then the `global` version would be invoked.

Now imagine `##c++` also has a `malloc` factoid. If you invoke it in `##c++` then its version of the factoid would be used instead of `##c`'s or `global`'s versions. If you invoke it in a channel that is not `##c++` or `##c` then the `global` version would be used.

However, if there is no `malloc` factoid in the `global` channel but there is one in `##c` and `##c++`, and you attempt to invoke it in any other channel then PBot will display a disambiguation message listing which channels it belongs to and instructing you to use the [`fact`](#fact) command to call the desired factoid.

## Adding/removing factoids
### factadd
To create a factoid, use the `factadd` command. This command can alternatively
accept a Web paste site via the `-url` option; this allows you to use your local
editor to set factoid text that can include line-breaks and indentation.

Usage: `factadd [-f] [channel] <keyword> (<description> | -url <Web paste site>)`

To add a factoid to the global channel, use `global` as the channel parameter.

    <pragma-> !factadd ##c c /say C rocks!

To force overwriting an existing factoid, use the `-f` option.

### factrem
### forget

To remove a factoid, use the `factrem` or `forget` command.

Usage: `factrem [channel] <keyword>` `forget [channel] <keyword>`

### factalias
To create an factoid that acts as an alias for a command, use the `factalias`
command or create a factoid with its text set to `/call <command>`.

Usage: `factalias [channel] <keyword> <command>`

    <pragma-> !factadd book /me points accusingly at $args, "Where is your book?"

    <pragma-> !book newbie
            * PBot points accusingly at newbie, "Where is your book?"

    <pragma-> !factalias rafb book

    <pragma-> !rafb runtime
            * PBot points accusingly at runtime, "Where is your book?"

<!-- -->

    <pragma-> !factadd offtopic /say In this channel, $args is off-topic.

    <pragma-> !offtopic C++
       <PBot> In this channel, C++ is off-topic.

    <pragma-> !factadd C++ /call offtopic C++

    <pragma-> !C++
       <PBot> In this channel, C++ is off-topic.

## Displaying factoids
To view or trigger a factoid, one merely issues its keyword as a command.

    <pragma-> PBot, c?
       <PBot> C rocks!

    <pragma-> !snack
            * PBot eats a cookie.

### fact
To view or trigger a factoid belonging to a specific channel, use the `fact` command.

Usage: `fact <channel> <keyword> [arguments]`

### factshow
To see a factoid's literal value without invoking the factoid, use the `factshow` command.

Usage: `factshow [-p] [channel] <keyword>`

    <pragma-> !factshow hi
       <PBot> hi: /say $greetings, $nick.

You can use the `-p` option to have PBot paste the factoid description to a Web-based
text paste site. PBot will output a link to the paste instead. This is useful if the
factoid was added with [`factadd`](#factadd)'s `-url` option and contains formatting
such as line-breaks and indentation.

## Editing factoids
### factchange
To change a factoid, use the `factchange` command. This command can alternatively
accept a Web paste site via the `-url` option; this allows you to use your local
editor to set factoid text that can include line-breaks and indentation.

Usage:  `factchange [channel] <keyword> (s/<pattern>/<change to>/[gi] | -url <paste site>)`

    <pragma-> !c
       <PBot> C rocks!

    <pragma-> !factchange ##c c s/rocks/rules/
       <PBot> c changed.

    <pragma-> !c
       <PBot> C rules!

Note that the final argument is a Perl-style substitution regex.  See `man perlre` on your system.

For instance, it is possible to append to a factoid by using: `factchange channel factoid s/$/text to append/`. Likewise, you can prepend to a factoid by using: `factchange channel factoid s/^/text to prepend/`.

### factmove
To rename a factoid or move a factoid to a different channel, use the `factmove` command:

Usage:  `factmove <source channel> <source factoid> <target channel/factoid> [target factoid]`

If three arguments are given, the factoid is renamed in the source channel.  If four arguments are given, the factoid is moved to the target channel with the target name.

### factundo
To revert to an older revision, use the `factundo` command. You can repeatedly undo a factoid until there are no more undos remaining.
You can also list all revisions and then directly jump to a specific revision.

Usage: `factundo [-l [N]] [-r <N>] [channel] <keyword>`

* `-l [N]` list undo history, optionally starting from `N`
* `-r <N>` jump to revision `N`

### factredo
To revert to a newer revision, use the `factredo` command. You can repeatedly redo a factoid until there are no more redos available.
You can also list all revisions and then directly jump to a specific revision.

Usage: `factredo [-l [N]] [-r <N>] [channel] <keyword>`

* `-l [N]` list undo history, optionally starting from `N`
* `-r <N>` jump to revision `N`

## Factoid metadata
### factset
To view or set [factoid metadata](#factoid-metadata-list), such as owner, rate-limit, etc, use the [`factset`](#factset) command.

Usage:  `factset [channel] <factoid> [<key> [value]]`

Omit `<key>` and `<value>` to list all the keys and values for a factoid.  Specify `<key>`, but omit `<value>` to see the value for a specific key.

### factunset
To unset [factoid metadata](#factoid-metadata-list), use the `factunset` command.

Usage: `factunset [channel] <factoid> <key>`

### Factoid metadata List
This is a list of recognized factoid metadata fields. A [user-capability](Admin.md#user-capabilities) of `none` signifies that anybody can set the field.

Name | Capability | Description
--- | --- | ---
`action` | none | The action to perform or text to display when the factoid is invoked.
`action_with_args` | none | Optional alternate action to perform if any arguments have been supplied when invoking the factoid.
`usage` | none | Prints a usage message when no arguments are provided.
`help` | none | The text to display when the [`help`](Commands.md#help) command is used on this factoid.
`created_on` | botowner | The timestamp of when the factoid was created.
`enabled` | chanop | Whether the factoid can be invoked or not. If it is disabled, the command will be silently ignored.
`last_referenced_in` | botowner | The channel or private-message in which the factoid was last used.
`last_referenced_on` | botowner | The timestamp of when the factoid was last used.
`modulelauncher_subpattern` | botowner | A substitution expression used to modify the arguments into a command-line for a module factoid.
`owner` | botowner | The creator of the factoid. The creator has the ability to lock the factoid, etc.
`rate_limit` | chanop | The factoid may be invoked only once per this many seconds. `0` for no limit.
`ref_count` | botowner | How many times the factoid has been invoked in its life-time.
`ref_user` | botowner | The hostmask of the last person to invoke the factoid.
`type` | botowner | The type of the factoid. "text" for regular factoid; "module" for module.
`edited_by` | botowner | The hostmask of the person to last edit the factoid.
`edited_on` | botowner | The timestamp of when the factoid was last edited.
`locked` | chanop | If enabled, prevents the factoid from being changed or removed.
`add_nick` | chanop | Prepends the nick of the person invoking the factoid to the output of the factoid.
`nooverride` | chanop | Prevents the creation of a factoid with an identical name in a different channel.
`cap-override` | botowner | Provides a user with the capability specified, just for this factoid invocation.
`persist-key` | admin | The storage key for allowing code-factoids to persist variables
`interpolate` | none | When set to a false value, `$variables` will not be expanded.
`keyword_override` | none | Once invoked, make PBot think this factoid is a different one.
`no_keyword_override` | none | Ignore the `--keyword-override=...` option.
`use_output_queue` | none | When set to a true value, the output will be delayed by a random number of seconds to simulate reading/typing.
`locked_to_channel` | none | This factoid can only be invoked in the channel in which it was created.
`allow_empty_args` | none | Do not replace empty arguments with `$nick`.
`require_explicit_args` | none | Aliases must have explicit `$args`.
`preserve_whitespace` | none | Do not collapse ajdacent whitespace characters.

## Information about factoids
### factfind
To search the database for a factoid, use the 'factfind` command.  You may optionally specify whether to narrow by channel and/or include factoid owner and/or last referenced by in the search.

If there is only one match for the query, it will display that factoid and its text, otherwise it will list all matching keywords.

Usage: `factfind [-channel channel] [-owner nick] [-by nick] [-regex] [text]`

If you specify the `-regex` flag, the `text` argument will be treated as a regex.

    <pragma-> !factfind cast
       <PBot> 3 factoids match: [##c] NULL casting dontcastmalloc

### factinfo
To get information about a factoid, such as who submitted it and when, use the `factinfo` command.

Usage: `factinfo [channel] <keyword>`

    <pragma-> !factinfo ##c NULL
       <PBot> NULL: Factoid submitted by Major-Willard for all channels
              on Sat Jan 1 16:17:42 2005 [5 years and 178 days ago],
              referenced 39 times (last by pragma- on Sun Jun 27 04:40:32 2010 [5 seconds ago])

### factlog
To see a factoid's changelog history, use the `factlog` command.

Usage: `factlog [-h] [-t] [channel] <factoid>`

`-h` shows full hostmasks instead of just the nick.

`-t` shows the actual timestamp instead of relative.

    <pragma-> !factadd hi /say Hello there!
       <PBot> hi added to global channel.

    <pragma-> !factchange hi s/!$/, $nick!/
       <PBot> Changed: hi is /say Hello there, $nick!

    <pragma-> !forget hi
       <PBot> hi removed from the global channel.

    <pragma-> !factadd hi /say Hi!

<!-- -->

    <pragma-> !factlog hi
       <PBot> [3m ago] pragma- created: /say Hi!
              [5m ago] pragma- deleted
              [8m ago] pragma- changed to /say Hello there, $nick!
              [10m ago] pragma- created: /say Hello there!

### factset
To view [factoid metadata](#factoid-metadata-list), such as owner, rate-limit, etc, use the `factset` command.

Usage:  `factset [channel] <factoid> [<key> [value]]`

Omit `<key>` and `<value>` to list all the keys and values for a factoid.  Specify `<key>`, but omit `<value>` to see the value for a specific key.

### count
To see how many factoids and what percentage of the database `<nick>` has submitted, use the `count` command.

Usage: `count <nick>`

    <pragma-> !count prec
       <PBot> prec has submitted 28 factoids out of 233 (12%)

    <pragma-> !count twkm
       <PBot> twkm has submitted 74 factoids out of 233 (31%)

    <pragma-> !count pragma
       <PBot> pragma has submitted 27 factoids out of 233 (11%)

### histogram
To see a histogram of the top factoid submitters, use the `histogram` command.

    <pragma-> !histogram
       <PBot> 268 factoids, top 10 submitters: twkm: 74 (27%) Major-Willard: 64 (23%) pragma-: 40 (14%) prec: 39 (14%) defrost: 14 (5%) PoppaVic: 10 (3%) infobahn: 7 (2%) orbitz: 3 (1%) mauke: 3 (1%) Tom^: 2 (1%)

### top20
To see the top 20 most popular factoids, use the `top20` command. It can also show you the 50 most recent factoids that were added to a channel.

Usage: `top20 <channel> [<nick> or 'recent']`

    <pragma-> !top20 ##c
       <PBot> Top 20 referenced factoids for ##c: explain (3459) c11 (2148) book (1070) books (1049) K&R (1000) dontcastmalloc (991) notC (696) standard (655) c99 (506) scanf (501) declare (453) std (434) cstd (344) tias (305) parens (291) int (287) c1x (272) UB (263) H&S (257) binky (236)

    <pragma-> !top20 ##c pragma-
       <PBot> 20 factoids last referenced by pragma- (pragma-!~chaos@unaffiliated/pragmatic-chaos): to [1d20h ago] realloc [3d15h ago] deport [4d16h ago] long [4d16h ago] decay [6d17h ago] x [6d16h ago] sizeof [13d18h ago] ENOQUESTION [13d19h ago] main [13d10h ago] cfaq [14d22h ago] heap [14d23h ago] malloc [15d15h ago] _ [16d20h ago] declareuse [17d15h ago] rot13 [17...

    <pragma-> !top20 ##c recent
       <PBot> 50 most recent ##c submissions: barometer [9h ago by kurahaupo] glib-pcre [21h ago by aozt] unspecified [1d13h ago by pragma-] rules [1d17h ago by oldlaptop] pjp [2d3h ago by d3738] gnu-errno-name-num [2d21h ago by aozt] cbreak [5d8h ago by jp] test case [5d9h ago by pragma-] googlearn [6d2h ago by glacial] threads [8d10h ago by glacial] cjeopard...

