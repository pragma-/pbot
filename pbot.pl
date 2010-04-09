#!/usr/bin/perl 
#
# File: pbot.pl
# Author: pragma_
#
# Purpose: IRC Bot (3rd generation)
#
# Version History:
########################

my $VERSION = "1.0.0";

########################
# 1.0.0 (03/14/10): Initial version using PBot::PBot module

use strict;
use warnings;

use PBot::PBot;

my $home = $ENV{HOME};

my %config = ( log_file => "$home/pbot/log",

               admins_file          => "$home/pbot/admins",
               channels_file        => "$home/pbot/channels",
               ignorelist_file      => "$home/pbot/ignorelist",

               factoids_file           => "$home/pbot/factoids",
               export_factoids_path    => "$home/pbot/factoids.html",
               export_factoids_site    => 'http://blackshell.com/~msmud/pbot2/factoids.html',
               module_dir              => "$home/pbot/modules",

               quotegrabs_file           => "$home/pbot/quotegrabs",
               export_quotegrabs_path    => "$home/pbot/quotegrabs.html",
               export_quotegrabs_site    => 'http://blackshell.com/~msmud/pbot2/quotegrabs.html',

               ircserver => 'irc.freenode.net',
               botnick   => 'pbot3',
               username  => 'pbot3',
               ircname   => 'http://www.iso-9899.info/wiki/Candide',
               identify_password => '*',
             );

my $pbot = PBot::PBot->new(%config);

$pbot->start();

# not reached
