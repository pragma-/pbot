#!perl 
#
# File: pbot.pl
# Author: pragma_
#
# Purpose: IRC Bot (3rd generation)
########################

my $VERSION = "1.0.0";

use strict;
use warnings;

use PBot::PBot;

# Be sure to set $bothome to the location PBot was extracted (default assumes ~/pbot).  
# This location must contain the PBot directory, among others configured below.
my $bothome = "$ENV{HOME}/pbot";

my %config = ( 
               # -----------------------------------------------------
               # Be sure to set your IRC information to a registered NickServ account
               # if you want channel auto-join to work.
               # -----------------------------------------------------

               # IRC server address to connect to
               ircserver => 'irc.freenode.net',

               # IRC nick (what people see when you talk in channels)
               # (must be a nick registered with a NickServ account for channel auto-join to work)
               botnick   => 'pbot3',
               
               # IRC username (what appears in front of your hostname in /whois)
               username  => 'pbot3',
               
               # IRC realname (extra /whois information)
               ircname   => 'http://www.iso-9899.info/wiki/Candide',
               
               # Password to send to NickServ for identification
               # (channels will not be auto-joined until identified)
               identify_password  => '*',

               # The bot is triggered by using its name, or the following trigger SINGLE character
               trigger => '.',

               # -----------------------------------------------------
               # The bot can export the latest factoids and quotegrabs to an HTML
               # document.  If you run a webserver or something similiar, you may
               # wish to set the following items ending with 'path' to point to
               # a suitable location for the webserver, and to set the items
               # ending with 'site' to the public-facing URL where the files
               # may be viewed in a browser.
               # -----------------------------------------------------

               export_factoids_path      => "$bothome/factoids.html",
               export_factoids_site      => 'http://blackshell.com/~msmud/candide/factoids.html',

               export_quotegrabs_path    => "$bothome/quotegrabs.html",
               export_quotegrabs_site    => 'http://blackshell.com/~msmud/candide/quotegrabs.html',

               # -----------------------------------------------------
               # You shouldn't need to change anything below this line.
               # -----------------------------------------------------

               # Path to data directory
               data_dir        => "$bothome/data",

               # Path to config directory
               conf_dir        => "$bothome/config",

               # Path to directory containing external script-like modules
               module_dir      => "$bothome/modules",

               # Location of file where bot log information will be output (in addition to stdout)
               # (if you use pbot.sh and you change log_file, be sure to also change the log path in pbot.sh)
               log_file        => "$bothome/log/log",

               # Location of file containing bot admin information
               admins_file     => "$bothome/config/admins",

               # Location of file containing channel information
               channels_file   => "$bothome/config/channels",

               # Location of file containing ignorelist entries
               ignorelist_file => "$bothome/config/ignorelist",

               # Location of file containing factoids and modules
               factoids_file   => "$bothome/data/factoids",

               # Location of file containing channel user quotes
               quotegrabs_file => "$bothome/data/quotegrabs",
             );

# Create and initialize bot object
my $pbot = PBot::PBot->new(%config);

# Start the bot main loop; doesn't return
$pbot->start();
