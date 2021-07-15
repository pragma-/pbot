# Frequently Asked Questions
This is a work in progress. More questions coming soon!

<!-- md-toc-begin -->
  * [How do I change my password?](#how-do-i-change-my-password)
  * [How do I make PBot remember my `date` timezone?](#how-do-i-make-pbot-remember-my-date-timezone)
  * [How do I make PBot remember my `weather` location?](#how-do-i-make-pbot-remember-my-weather-location)
  * [How do I change the bot trigger?](#how-do-i-change-the-bot-trigger)
  * [How do I whitelist a user?](#how-do-i-whitelist-a-user)
  * [How do I change how the bot outputs multi-line messages?](#how-do-i-change-how-the-bot-outputs-multi-line-messages)
<!-- md-toc-end -->

### How do I change my password?
Use the [`my`](Commands.md#my) command to set the `password` user metadata for your
user account. Your hostmask must match the user account.

    my password <your password>

### How do I make PBot remember my `date` timezone?
Use the [`my`](Commands.md#my) command to set the `timezone` user metadata for your
user account. Your hostmask must match the user account.

    my timezone <your timezone>

### How do I make PBot remember my `weather` location?
Use the [`my`](Commands.md#my) command to set the `location` user metadata for your
user account. Your hostmask must match the user account.

    my location <your location>

### How do I change the bot trigger?
To change the default `!` trigger to a different character use the [`regset`](Registry.md#regset)
command to change the `general.trigger` value.

For example, to change it to the `~` character:

    regset general.trigger ~

To change it to both `!` and `~` (and others):

    regset general.trigger [!~]

To use only the bot's nick:

    regset general.trigger ""

You can also override the trigger on a per-channel basis by use the channel name
in place of `general`.

For example, to override the trigger specifically for `#channel`:

    regset #channel.trigger ~

### How do I whitelist a user?
Whitelisting a user exempts them from anti-flood enforcement, ban-evasion checking,
being automatically muted or kicked for various offenses, and more.

To whitelist a user, use the [`useradd`](Admin.md#useradd) command with the
`is-whitelisted` capability argument.  To whitelist them in all channels, add
the user to the global channel.

Usage: `useradd <username> <hostmasks> <channels> is-whitelisted`

If the user already exists, use the [`userset`](Admin.md#userset) command to
grant them the `is-whitelisted` capability.

Usage: `userset <username> is-whitelisted 1`

### How do I change how the bot outputs multi-line messages?
When output from a command contains newlines, PBot will convert the newlines
to spaces and output it as one message.

If you prefer to output each line instead, you can control this behavior with
the `general.preserve_newlines` and `general.max_newlines` registry entries. To
set this behavior for specific channels, replace `general` with the `#channel`.

For example:

    <pragma-> !sh printf "a\nb\nc\nd\ne\n"
       <PBot> a b c d e

    <pragma-> !regset general.preserve_newlines 1
       <PBot> general.preserve_newlines set to 1

    <pragma-> !regset general.max_newlines 4
       <PBot> general.max_newlines set to 4

    <pragma-> !sh printf "a\nb\nc\nd\ne\n"
       <PBot> a
       <PBot> b
       <PBot> c
       <PBot> And that's all I have to say about that. See https://0x0.st/-Okb.txt for full text.
