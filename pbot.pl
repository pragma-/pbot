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

  # IRC port
  port => '6667',

  # Use SSL?  0 = disabled, 1 = enabled
  # Note that you may need to use a specific port for SSL; e.g., freenode uses 6697 or 7000 for SSL
  # Uncomment SSL_ca_path or SSL_ca_file below to enable SSL verification (will still work without
  # verification, but will be susceptible to man-in-the-middle attacks)
  SSL => 0,

  # SSL CA certificates path; e.g., linux: /etc/ssl/certs
  # SSL_ca_path => '/etc/ssl/certs',

  # SSL CA file, if SSL_ca_path will not do; e.g., OpenBSD: /etc/ssl/cert.pem
  # SSL_ca_file => '/etc/ssl/cert.pem',

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

  export_factoids_path      => "$bothome/factoids.html",   # change to a path in your webroot
  export_factoids_site      => 'http://your.website.com/factoids.html',

  export_quotegrabs_path    => "$bothome/quotegrabs.html", # change to a path in your webroot
  export_quotegrabs_site    => 'http://your.website.com/quotegrabs.html',

  # -----------------------------------------------------
  # You shouldn't need to change anything below this line.
  # -----------------------------------------------------

  # Path to data directory
  data_dir        => "$bothome/data",

  # Path to config directory
  config_dir      => "$bothome/config",

  # Path to directory containing external script-like modules
  module_dir      => "$bothome/modules",

  # Location of file where bot log information will be output (in addition to stdout)
  # (if you use pbot.sh and you change log_file, be sure to also change the log path in pbot.sh)
  log_file        => "$bothome/log/log",
);

# Location of file containing configuration registry
$config{registry_file}   = "$config{config_dir}/registry";

# Location of file containing bot admin information
$config{admins_file}     = "$config{config_dir}/admins";

# Location of file containing channel information
$config{channels_file}   = "$config{config_dir}/channels";

# Location of file containing ignorelist entries
$config{ignorelist_file} = "$config{config_dir}/ignorelist";

# Location of file containing factoids and modules
$config{factoids_file}   = "$config{data_dir}/factoids";

# Location of file containing channel user quotes
$config{quotegrabs_file} = "$config{data_dir}/quotegrabs.sqlite3";

# Location of file containing message history
$config{message_history_file} = "$config{data_dir}/message_history.sqlite3";

# Create and initialize bot object
my $pbot = PBot::PBot->new(%config);

# Start the bot main loop; doesn't return
$pbot->start();
