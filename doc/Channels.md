Channel Management
==================


<!-- md-toc-begin -->
    * [Channel Management](#channel-management)
      * [chanadd](#chanadd)
      * [chanrem](#chanrem)
      * [chanset](#chanset)
        * [Channel Metadata List](#channel-metadata-list)
      * [chanunset](#chanunset)
      * [chanlist](#chanlist)
<!-- md-toc-end -->


#### chanadd
`chanadd` adds a channel to PBot's list of channels to auto-join and manage.

Usage: `chanadd <channel>`

#### chanrem
`chanrem` removes a channel from PBot's list of channels to auto-join and manage.

Usage: `chanrem <channel>`

#### chanset
`chanset` sets a channel's meta-data. See [channel meta-data list](#Channel_Metadata_List)

Usage: `chanset <channel> [key [value]]`

If both `key` and `value` are omitted, chanset will show all the keys and values for that channel. If only `value` is omitted, chanset will show the value for that key.

##### Channel Metadata List
* `enabled`: when set to a true value, PBot will auto-join this channel after identifying to NickServ (unless `general.autojoin_wait_for_nickserv` is `0`, in which case auto-join happens immediately).
* `chanop`: when set to a true value, PBot will perform channel management (anti-flooding, ban-evasion, etc).
* `permop`: when set to a true value, PBot will automatically op itself when joining and remain opped instead of automatically opping and deopping as necessary.

#### chanunset
`chanunset` deletes a channel's meta-data key.

Usage: `chanunset <channel> <key>`

#### chanlist
`chanlist` lists all added channels and their meta-data keys and values.

