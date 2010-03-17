# File: PBot.pm
# Author: pragma_
#
# Purpose: IRC Bot (3rd generation)

package PBot::PBot;

use strict;
use warnings;

BEGIN {
  use Exporter ();
  use vars qw($VERSION @ISA @EXPORT_OK);

  $VERSION = "0.5.0-beta";
  @ISA = qw(Exporter);
  # TODO: move all of these into the pbot object and pass that around instead
  @EXPORT_OK = qw($VERSION %flood_watch $logger %commands $conn %admins $botnick %internal_commands
                  %is_opped @op_commands %quieted_nicks %ignore_list %unban_timeout @quotegrabs
                  $channels_file $MAX_NICK_MESSAGES %flood_watch $quotegrabs_file $export_quotegrabs_path $export_quotegrabs_timeout
                  $commands_file $module_dir $admins_file $export_factoids_timeout $export_factoids_path $max_msg_len
                  $export_factoids_time $export_quotegrabs_time $MAX_FLOOD_MESSAGES $identify_password);
}

use vars @EXPORT_OK;

# unbuffer stdout
STDOUT->autoflush(1);

use Net::IRC;                            # for the main IRC engine
use HTML::Entities;                      # for exporting
use Time::HiRes qw(gettimeofday alarm);  # for timers
use Carp ();
use Data::Dumper;

use PBot::Logger;
use PBot::IRCHandlers;
use PBot::InternalCommands;
use PBot::ChannelStuff;
use PBot::StdinReader;
use PBot::Quotegrabs;
use PBot::FactoidStuff;
use PBot::Interpreter;
use PBot::IgnoreList;
use PBot::BotAdminStuff;
use PBot::Modules;
use PBot::AntiFlood;
use PBot::OperatorStuff;
use PBot::TimerStuff;

*admins = \%PBot::BotAdminStuff::admins;
*commands = \%PBot::FactoidStuff::commands;
*quotegrabs = \@PBot::Quotegrabs::quotegrabs;

# TODO: Move these into pbot object
my $ircserver;

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to Logger should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $log_file          = delete $conf{log_file};

  # TODO: Move all of these into pbot object
  $channels_file     = delete $conf{channels_file};
  $commands_file     = delete $conf{commands_file};
  $quotegrabs_file   = delete $conf{quotegrabs_file};
  $admins_file       = delete $conf{admins_file};
  $module_dir        = delete $conf{module_dir};
  $ircserver         = delete $conf{ircserver};
  $botnick           = delete $conf{botnick};
  $identify_password = delete $conf{identify_password};
  $max_msg_len       = delete $conf{max_msg_len};

  $export_factoids_timeout = delete $conf{export_factoids_timeout};
  $export_factoids_path = delete $conf{export_factoids_path};

  $export_quotegrabs_timeout = delete $conf{export_quotegrabs_timeout}; 
  $export_quotegrabs_path = delete $conf{export_quotegrabs_path};

  $MAX_FLOOD_MESSAGES = delete $conf{MAX_FLOOD_MESSAGES};
  $MAX_NICK_MESSAGES = delete $conf{MAX_NICK_MESSAGES};

  my $home = $ENV{HOME};
  $channels_file      = "$home/pbot/channels" unless defined $channels_file;
  $commands_file      = "$home/pbot/commands" unless defined $commands_file;
  $quotegrabs_file    = "$home/pbot/quotegrabs" unless defined $quotegrabs_file;
  $admins_file        = "$home/pbot/admins" unless defined $admins_file;
  $module_dir         = "$home/pbot/modules" unless defined $module_dir;
  $ircserver          = "irc.freenode.net" unless defined $ircserver;
  $botnick            = "pbot2" unless defined $botnick;
  $identify_password  = "" unless defined $identify_password;

  $export_factoids_timeout  = -1 unless defined $export_factoids_timeout;
  $export_factoids_time  = gettimeofday + $export_factoids_timeout;

  $export_quotegrabs_timeout  = -1 unless defined $export_quotegrabs_timeout;
  $export_quotegrabs_time  = gettimeofday + $export_quotegrabs_timeout;

  $max_msg_len  = 460 unless defined $max_msg_len;
  $MAX_FLOOD_MESSAGES  = 4 unless defined $MAX_FLOOD_MESSAGES;
  $MAX_NICK_MESSAGES  = 8 unless defined $MAX_NICK_MESSAGES;

  $commands{version} = {
                       enabled   => 1, 
                       owner     => $botnick,
                       text      => "/say pbot2 version $VERSION", 
                       timestamp => 0,
                       ref_count => 0, 
                       ref_user  => "nobody" }; 

  # TODO: wrap these in Setters/Getters
  unshift @quotegrabs, ({ 
                       nick      => $botnick,
                       text      => "Who's a bot?", 
                       channel   => "#pbot2", 
                       grabbed_by => "pragma_", 
                       id         => 1,
                       timestamp => 0 });

  $admins{$botnick} = { 
                       password => '*', 
                       level    => 50,
                       login    => 1,
                       host => "localhost" };
  
  my $self = {
    # TODO: add conf variables here
  };

  $logger = new PBot::Logger(log_file => $log_file);

  bless $self, $class;
  return $self;
}

my $irc = new Net::IRC;

sub connect {
  my ($self, $server) = @_;

  $server = $ircserver if not defined $server;

  $logger->log("Connecting to $server ...\n");
  $conn = $irc->newconn( 
    Nick         => $botnick,
    Username     => 'pbot3',                                 # FIXME: make this config
    Ircname      => 'http://www.iso-9899.info/wiki/Candide', # FIXME: make this config
    Server       => $server,
    Port         => 6667)                                    # FIXME: make this config
    or die "$0: Can't connect to IRC server.\n";

  #set up handlers for the IRC engine
  $conn->add_handler([ 251,252,253,254,302,255 ], \&PBot::IRCHandlers::on_init       );
  $conn->add_handler(376                        , \&PBot::IRCHandlers::on_connect    );
  $conn->add_handler('disconnect'               , \&PBot::IRCHandlers::on_disconnect );
  $conn->add_handler('notice'                   , \&PBot::IRCHandlers::on_notice     );
  $conn->add_handler('caction'                  , \&PBot::IRCHandlers::on_action     );
  $conn->add_handler('public'                   , \&PBot::IRCHandlers::on_public     );
  $conn->add_handler('msg'                      , \&PBot::IRCHandlers::on_msg        );
  $conn->add_handler('mode'                     , \&PBot::IRCHandlers::on_mode       );
  $conn->add_handler('part'                     , \&PBot::IRCHandlers::on_departure  );
  $conn->add_handler('join'                     , \&PBot::IRCHandlers::on_join       );
  $conn->add_handler('quit'                     , \&PBot::IRCHandlers::on_departure  );
}

#main loop
sub do_one_loop {
  # process IRC events
  $irc->do_one_loop();

  # process STDIN events
  check_stdin();
}

sub check_stdin {
  my $input = PBot::StdinReader::check_stdin();

  return if not defined $input;

  $logger->log("---------------------------------------------\n");
  $logger->log("Read '$input' from STDIN\n");

  my ($from, $text);

  if($input =~ m/^~([^ ]+)\s+(.*)/) {
    $from = $1;
    $text = "!$2";
  } else {
    $from = undef;
    $text = "!$input";
  }

  return PBot::Interpreter::process_line($from, $botnick, "stdin", "localhost", $text);
}

sub load_channels {
  return PBot::ChannelStuff::load_channels();
}

sub load_quotegrabs {
  return PBot::Quotegrabs::load_quotegrabs();
}

sub load_commands {
  return PBot::FactoidStuff::load_commands();
}

1;
