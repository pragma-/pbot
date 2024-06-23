# Frequently Asked Questions
This is a work in progress. More questions coming soon!

<!-- md-toc-begin -->
* [When I type `!version` it say "new version available"?](#when-i-type-version-it-say-new-version-available)
* [How do I change the bot trigger?](#how-do-i-change-the-bot-trigger)
* [How do I whitelist a user?](#how-do-i-whitelist-a-user)
* [How do I change how the bot outputs multi-line messages?](#how-do-i-change-how-the-bot-outputs-multi-line-messages)
* [I made a command. It's supposed to output formatting with spaces and tabs?](#i-made-a-command-its-supposed-to-output-formatting-with-spaces-and-tabs)
* [How do I change my password?](#how-do-i-change-my-password)
* [How do I make PBot remember my `date` timezone?](#how-do-i-make-pbot-remember-my-date-timezone)
* [How do I make PBot remember my `weather` location?](#how-do-i-make-pbot-remember-my-weather-location)
* [How do I set up automatic join-flood enforcement?](#how-do-i-set-up-automatic-join-flood-enforcement)
<!-- md-toc-end -->

## When I type `!version` it say "new version available"?
The PBot [`version`](Commands.md#version) command checks PBot's version information on GitHub.
The command caches and reuses this version result for 5 minutes before issuing another GitHub version check.

You can live-update PBot without shutting it down. None of your files in your custom
data-directories will be touched unless the update includes a migration script in the
[`updates/`](../updates) directory.

If you used `git` to install PBot, type `git pull` in the `pbot` directory. This will
update the PBot files to the latest version from GitHub. If you used ZIP archives, download
the latest files and extract them again.

Then, in your PBot instance on IRC, use the [`refresh`](Admin.md#refresh) command to refresh
the PBot core and plugins. No restart required!

If there is a migration script for this update then [`refresh`](Admin.md#refresh) will say "Migration available;
restart required." and you will need to restart PBot at some point for the update to take effect.

## How do I change the bot trigger?
To change the default `!` trigger to a different character use the [`regset`](Registry.md#regset)
command to change the `general.trigger` value. Use `#channel.trigger` to change the trigger only
for that channel.

For example, to change it to the `~` character:

    regset general.trigger ~

To change it to both `!` and `~` (and others):

    regset general.trigger [!~]

To use only the bot's nick:

    regset general.trigger ""

## How do I whitelist a user?
Whitelisting a user exempts them from anti-flood enforcement, ban-evasion checking,
being automatically muted or kicked for various offenses, and more.

To whitelist a user, use the [`useradd`](Admin.md#useradd) command with the
`is-whitelisted` capability argument.  To whitelist them in all channels, add
the user to the global channel.

Usage: `useradd <username> <hostmasks> <channels> is-whitelisted`

If the user already exists, use the [`userset`](Admin.md#userset) command to
grant them the `is-whitelisted` capability.

Usage: `userset <username> is-whitelisted 1`

## How do I change how the bot outputs multi-line messages?
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

## I made a command. It's supposed to output formatting with spaces and tabs?
By default, PBot collapses adjacent whitespace in command output. This is intended to
reduce visual noise in IRC channels.

If your command is registered by a plugin, use the [`cmdset`](Admin.md#cmdset) command
to set the `preserve_whitespace` [command metadata](Admin.md#command-metadata-list) to
control this behavior.

If your command is a command-line applet, use the [`factset`](Factoids.md#factset) command
to set the `preserve_whitespace` [factoid metadata](Factoids.md#factoid-metadata-list) instead.

## How do I change my password?
If you have a NickServ account or a unique hostmask, you don't need a PBot password.
The `autologin` and `stayloggedin` metadata on your user account can be set instead.

But if you prefer to be safe instead of sorry, use the [`my`](Commands.md#my) command
to set the `password` and unset the `autologin` and `stayloggedin` metadata for your
user account. Your hostmask must match the user account and you must be logged in.

    my password <your password>
    my autologin 0
    my stayloggedin 0

If you are unable to log in, ask an admin to set a temporary password for you
with the [`userset`](Admin.md#userset) command. Log in with the temporary
password and then use the above commands to update your password.

## How do I make PBot remember my `date` timezone?
Use the [`my`](Commands.md#my) command to set the `timezone` user metadata for your
user account. Your hostmask must match the user account. The `my` command will automatically
create a user account for you if one does not exist.

    my timezone <your timezone>

## How do I make PBot remember my `weather` location?
Use the [`my`](Commands.md#my) command to set the `location` user metadata for your
user account. Your hostmask must match the user account. The `my` command will automatically
create a user account for you if one does not exist.

    my location <your location>

## How do I set up automatic join-flood enforcement?
[See how to set up automatic join-flood enforcement here.](AntiAbuse.md#setting-up-automatic-join-flood-enforcement)
