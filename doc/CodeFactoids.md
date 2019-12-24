### code-factoids
Code-factoids are a special type of factoid whose text is executed as Perl instructions. The return value from these instructions is the final text of the factoid. This final text is then parsed and treated like any other factoid text.


<!-- md-toc-begin -->
    * [code-factoids](#code-factoids)
      * [Special variables](#special-variables)
      * [testargs example](#testargs-example)
      * [rtfm example](#rtfm-example)
      * [poll example](#poll-example)
<!-- md-toc-end -->


By default, the variables created within code-factoids do not persist between factoid invocations. This behavior can be overridden by factsetting a persist-key with a unique value.

To create a code-factoid, simply wrap the factoid text with curly braces.

    factadd keyword { code here }

#### Special variables

There are some special variables available to code-factoids.

* `@args` - any arguments passed to the factoid (note that invoker's nick is passed if no arguments are specified)
* `$nick` - nick of the person invoking the factoid
* `$channel` - channel in which the factoid is being invoked

#### testargs example

    <pragma-> factadd global testargs { return "/say No arguments!" if not @args;
              if (@args == 1) { return "/say One argument: $args[0]!" } elsif
              (@args == 2) { return "/say Two arguments: $args[0] and $args[1]!"; }
              my $results = join ', ', @args; return "/say $results"; }
       <PBot> testargs added to the global channel.
    <pragma-> testargs
       <PBot> One argument: pragma-!
    <pragma-> testargs "abc 123" xyz
       <PBot> Two arguments: abc 123 and xyz!

#### rtfm example

Remember that `rtfm` factoid from earlier? Let's modify it so that it doesn't attack Zhivago.

    <pragma-> forget rtfm
       <PBot> rtfm removed from the global channel.
    <pragma-> factadd global rtfm { return "/say Nonsense! Zhivago is a gentleman and
              a scholar." if $nick eq "Zhivago" or "@args" =~ /zhivago/i; return "/me
              $attacks $args[0] with a $sizes $colors manual." }
       <PBot> rtfm added to the global channel.
    <pragma-> rtfm luser
            * PBot smacks luser with a huge blue manual.
    <pragma-> rtfm Zhivago
       <PBot> Nonsense! Zhivago is a gentleman and a scholar.

#### poll example

An extremely basic aye/nay poll system. All code-factoids sharing the same persist-key will share the same persisted variables.

First we add the factoids:

    <pragma-> factadd global startpoll { %aye = (); %nay = (); $question = "@args";
              "/say Starting poll: $question" }
       <PBot> startpoll added to the global channel.
    <pragma-> factadd global aye { $aye{$nick} = 1; delete $nay{$nick}; "" }
       <PBot> aye added to the global channel.
    <pragma-> factadd global nay { $nay{$nick} = 1; delete $aye{$nick}; "" }
       <PBot> nay added to the global channel.
    <pragma-> factadd global pollresults { $ayes = keys %aye; $nays = keys %nay;
              "/say Results for poll \"$question\": ayes: $ayes, nays: $nays" }
       <PBot> pollresults added to the global channel.

Then we set their persist-key to the same value:

    <pragma-> factset global startpoll persist-key pragma-poll
       <PBot> [global] startpoll: 'persist-key' set to 'pragma-poll'
    <pragma-> factset global aye persist-key pragma-poll
       <PBot> [global] aye: 'persist-key' set to 'pragma-poll'
    <pragma-> factset global nay persist-key pragma-poll
       <PBot> [global] nay: 'persist-key' set to 'pragma-poll'
    <pragma-> factset global pollresults persist-key pragma-poll
       <PBot> [global] pollresults: 'persist-key' set to 'pragma-poll'

And action:

    <pragma-> startpoll Isn't this cool?
       <PBot> Starting poll: Isn't this cool?
    <pragma-> aye
    <luser69> nay
    <someguy> aye
    <pragma-> pollresults
       <PBot> Results for poll "Isn't this cool?": ayes: 2, nays: 1

* Exercise for the reader: extend this poll system to be per-channel using `$channel`.

* Experts: extend this to use a `vote <keyword>` factoid, and adjust `pollresults` to show a tally for each keyword.

