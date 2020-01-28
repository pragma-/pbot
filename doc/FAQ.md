# Frequently Asked Questions
This is a work in progress. More questions coming soon!

<!-- md-toc-begin -->
  * [How do I change my password?](#how-do-i-change-my-password)
  * [How do I make PBot remember my `date` timezone?](#how-do-i-make-pbot-remember-my-date-timezone)
  * [How do I make PBot remember my `weather` location?](#how-do-i-make-pbot-remember-my-weather-location)
  * [How do I change the bot trigger?](#how-do-i-change-the-bot-trigger)
<!-- md-toc-end -->

### How do I change my password?
Use the [`my`](Commands.md#my) command to set the `password` user metadata for your
user account.

    my password <your password>

### How do I make PBot remember my `date` timezone?
Use the [`my`](Commands.md#my) command to set the `timezone` user metadata for your
user account.

    my timezone <your timezone>

### How do I make PBot remember my `weather` location?
Use the [`my`](Commands.md#my) command to set the `location` user metadata for your
user account.

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


