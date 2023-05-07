# Anti-Abuse

PBot can monitor channels for abusive behavior and take appropriate action.

<!-- md-toc-begin -->
* [Flood control](#flood-control)
  * [Message flood](#message-flood)
  * [Join flood](#join-flood)
  * [Enter key abuse](#enter-key-abuse)
  * [Nick flood](#nick-flood)
* [Anti-away/Nick-control](#anti-awaynick-control)
* [Anti-auto-rejoin control](#anti-auto-rejoin-control)
* [Opping/Deopping](#oppingdeopping)
* [Setting up automatic join-flood enforcement](#setting-up-automatic-join-flood-enforcement)
<!-- md-toc-end -->

## Flood control
PBot can monitor the channel for excessive rapid traffic originating from an individual and automatically ban the offender for a certain length of time.

### Message flood
If four (4) or more messages are sent within five (5) seconds, the flood control is triggered.  The offender will be muted for 30 seconds for the first offense.  Each additional offense will result in the offender being muted for a much longer period.  For example, the first offense will result in 30 seconds, the 2nd offense will be 5 minutes, the 3rd will be 1 hour, and so on.  The offense counter is decremented once every 24 hours.

The offender will be sent the following private message: "You have been muted due to flooding.  Please use a web paste service such as http://ideone.com for lengthy pastes.  You will be allowed to speak again in $timeout."

### Join flood
If four (4) or more JOINs are observed within thirty (30) minutes *without any messages in between joins*, the offender will be forwarded to another channel for a limited time: 2^(number_of_offenses + 2) hours.

In addition to private instructions from PBot, this channel will have a /topic and ChanServ on-join message with instructions explaining to the offender how to remove the forwarding.  The instructions are to message PBot with: `unbanme`.

Any messages sent to the public channel by the user at any time will reset their JOIN counter back to zero.  The unbanme command can only be used for the first two offenses -- the offense counter is decremented once every 24 hours.

The offender will be sent the following private message: "You have been banned from $channel due to join flooding.  If your connection issues have been resolved, or this was an accident, you may request an unban at any time by responding to this message with: `unbanme`, otherwise you will be automatically unbanned in $timeout."

### Enter key abuse
If four (4) consecutive messages are sent with ten (10) seconds or less between individual messages and without another person speaking, an enter-key-abuse counter is incremented.  This counter will then continue to be incremented every two (2) consecutive messages with ten (10) seconds or less in between until another person speaks or more than ten (10) seconds have elapsed, whereupon it returns to requiring four (4) consecutive messages.  When this counter reaches three (3) or greater, the offender will be muted using the same timeout rules as message flooding.  This counter is automatically decremented once per hour.

The offender will be sent the following private message: "You have been muted due to abusing the enter key.  Please do not split your sentences over multiple messages.  You will be allowed to speak again in $timeout."

### Nick flood
If four (4) or more nick-changes are observed within thirty (30) minutes, the nick-change flood control is triggered.  The offender will be muted for 15 minutes for the first offense.  Each additional offense will result in the offender being muted for a much longer period.  The offense counter is decremented once every 24 hours.

The offender will be sent the following private message: "You have been temporarily banned due to nick-change flooding.  You will be unbanned in $timeout."

## Anti-away/Nick-control
PBot can detect nick-changes to undesirable nicks such as those ending with |away, as well as undesirable ACTIONs such as /me is away.

When such a case is detected, PBot will kick the offender with a link to http://sackheads.org/~bnaylor/spew/away_msgs.html in the kick message.

## Anti-auto-rejoin control
PBot can detect if someone immediately auto-rejoins after having been kicked.

When such a case is detected, PBot will kickban the offender (with a kick message of "$timeout ban for auto-rejoining after kick") for 5 minutes for the first offense. Each additional offense will result in the offender being banned for a much longer period. The offense counter is decremented once every 24 hours.

## Opping/Deopping
ChanServ can op and deop PBot as necessary, unless the channel `permop` metadata is set to a true value. PBot will wait until about 5 minutes have elapsed before requesting a deop from ChanServ. This timeout can be controlled via the `general.deop_timeout` registry value, which can be overriden on a per-channel basis.

## Setting up automatic join-flood enforcement
PBot performs its join-flood enforcement in a separate channel to reduce noise in the main channel.

Let's say you want to set up join-flood enforcement for your channel, let's call it `#chan`. Here are all of the steps required to do that. Be sure to replace all occurences of `#chan` with your actual channel, including within `#chan-floodbans`.

* Create and register the `#stop-join-flood` channel. This is where PBot will forward join-flooders. Set its `/topic` to "You have been forwarded here due to join-flooding. If your IRC client or network issues have been resolved, you may `/msg PBot unbanme` to remove the ban-forward." Replace "PBot" with your bot's IRC nick. If the channel already exists, you may configure the `antiflood.join_flood_channel` registry entry to point at a different channel (see [regset](Registry.md#regset)).
* Set an extended-ban in `#chan`: `/mode #chan +b $j:#chan-floodbans$#stop-join-flood`. This will retrieve the bans from `#chan-floodbans` for use in `#chan` and forward banned users to `#stop-join-flood`. Use the channel you configured in `antiflood.join_flood_channel` if someone else has already created `#stop-join-flood`.
* Create and register the `#chan-floodbans` channel. This is where your instance of PBot will do the banning/unbanning; give it channel OPs here (`chanadd #chan-floodbans`, `chanset #chan-floodbans chanop 1` and optionally `chanset #chan-floodbans permop 1`). Be sure add PBot to the channel's access list for +o via ChanServ or equivalent.
* Join PBot to both `#chan` and `#chan-floodbans` so it can monitor `#chan` and set/remove the bans in `#chan-floodbans`.
* Optionally, configure the `#chan.join_flood_threshold` and `#chan.join_flood_time_threshold` registry entries if the defaults are not desirable (see [regset](Registry.md#regset)).
