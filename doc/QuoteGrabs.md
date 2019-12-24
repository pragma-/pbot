Quotegrabs
----------


<!-- md-toc-begin -->
  * [Quotegrabs](#quotegrabs)
    * [grab](#grab)
    * [getq](#getq)
    * [rq](#rq)
    * [delq](#delq)
<!-- md-toc-end -->


### grab
Grabs a message someone says, and adds it to the quotegrabs database.  You may grab multiple nicks/messages in one quotegrab by separating the arguments with a plus sign (the nicks need not be different -- you can grab multiple messages by the same nick by specifying a different history for each grab).

You can use the [recall](#recall) command to test the arguments before grabbing (please use a private message).

Usage: `grab <nick> [history [channel]] [+ ...]`
          where [history] is an optional argument regular expression used to search message contents;
          e.g., to grab a message containing the text "pizza", use: grab nick pizza

        <bob> Clowns are scary.
    <pragma-> grab bob clowns
       <PBot> Quote grabbed: 1: <bob> Clowns are scary.

<!-- -->

      <alice> Please put that in the right place.
        <bob> That's what she said!
    <pragma-> grab alice place + bob said
       <PBot> Quote grabbed 2: <alice> Please put that in the right place. <bob> That's what she said!

<!-- -->

    <charlie> I know a funny programming knock-knock joke.
    <charlie> Knock knock!
    <charlie> Race condition.
    <charlie> Who's there?
    <pragma-> grab charlie knock + charlie race + charlie there
       <PBot> Quote grabbed 3: <charlie> Knock knock! <charlie> Race condition. <charlie> Who's there?

### getq
Retrieves and displays a specific grabbed quote from the quotegrabs database.

Usage: `getq <quote-id>`

### rq
Retrieves and displays a random grabbed quote from the quotegrabs database.  You may filter by nick, channel and/or quote text.

Usage: `rq [nick [channel [text]]] [-c,--channel <channel>] [-t,--text <text>]`

### delq
Deletes a specific grabbed quote from the quotegrabs database.  You can only delete quotes you have grabbed unless you are logged in as an admin.

Usage: `delq <quote-id>`

