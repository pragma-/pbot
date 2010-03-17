#!/usr/bin/perl 
#
# File: pbot.pl
# Author: pragma_
#
# Purpose: IRC Bot (3rd generation)
#
# Version History:
########################

my $VERSION = "0.5.0-beta";

########################
# 0.5.0-beta (03/14/10): Initial version using PBot::PBot module

use strict;
use warnings;

use PBot::PBot;

my $home = $ENV{HOME};

my %config = ( log_file => "$home/pbot/log",

               channels_file   => "$home/pbot/channels",
               commands_file   => "$home/pbot/commands",
               quotegrabs_file => "$home/pbot/quotegrabs",

               ircserver => 'irc.freenode.net',
               botnick   => 'pbot3'
             );

my $pbot = PBot::PBot->new(%config);

$pbot->load_channels();
$pbot->load_quotegrabs();
$pbot->load_commands();

$pbot->connect();

while(1) {
  $pbot->do_one_loop();
}
