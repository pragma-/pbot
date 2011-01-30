# File: PBot.pm
# Author: pragma_
#
# Purpose: IRC Bot (3rd generation)

# $Id$

package PBot::PBot;

use strict;
use warnings;

use PBot::VERSION;

use vars qw($VERSION);
$VERSION = PBot::VERSION::BUILD_NAME . " revision " . PBot::VERSION::BUILD_REVISION . " " . PBot::VERSION::BUILD_DATE;

# unbuffer stdout
STDOUT->autoflush(1);

use Carp ();
use PBot::Logger;

use PBot::StdinReader;

use PBot::IRC;
use PBot::IRCHandlers;
use PBot::Channels;

use PBot::LagChecker;
use PBot::AntiFlood;

use PBot::Interpreter;
use PBot::Commands;

use PBot::ChanOps;
use PBot::ChanOpCommands;

use PBot::Factoids; 
use PBot::FactoidCommands;

use PBot::BotAdmins;
use PBot::BotAdminCommands;

use PBot::IgnoreList;
use PBot::IgnoreListCommands;

use PBot::Quotegrabs;
# no PBot::QuotegrabsCommands (bundled inside PBot::Quotegrabs for a change)

use PBot::Timer;

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to Logger should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;

  my $self = bless {}, $class;
  $self->initialize(%conf);
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  my $log_file                = delete $conf{log_file};

  $self->{conf_dir}           = delete $conf{conf_dir}           // "$ENV{HOME}/pbot/config";
  $self->{data_dir}           = delete $conf{data_dir}           // "$ENV{HOME}/pbot/data";
  $self->{module_dir}         = delete $conf{module_dir}         // "$ENV{HOME}/pbot/modules";

  $self->{ircserver}          = delete $conf{ircserver}          // "irc.freenode.net";
  $self->{botnick}            = delete $conf{botnick}            // "pbot3";
  $self->{username}           = delete $conf{username}           // "pbot3";
  $self->{ircname}            = delete $conf{ircname}            // "http://code.google.com/p/pbot2-pl/";
  $self->{identify_password}  = delete $conf{identify_password}  // "";

  $self->{max_msg_len}        = delete $conf{max_msg_len}        // 430;
  $self->{MAX_FLOOD_MESSAGES} = delete $conf{MAX_FLOOD_MESSAGES} // 4;
  $self->{MAX_NICK_MESSAGES}  = delete $conf{MAX_NICK_MESSAGES}  // 12;

  $self->{trigger}            = delete $conf{trigger}            // '!';

  my $channels_file           = delete $conf{channels_file};
  my $admins_file             = delete $conf{admins_file};
  my $ignorelist_file         = delete $conf{ignorelist_file};

  my $factoids_file           = delete $conf{factoids_file};
  my $export_factoids_path    = delete $conf{export_factoids_path};
  my $export_factoids_site    = delete $conf{export_factoids_site};

  my $quotegrabs_file         = delete $conf{quotegrabs_file};
  my $export_quotegrabs_path  = delete $conf{export_quotegrabs_path};
  my $export_quotegrabs_site  = delete $conf{export_quotegrabs_site};

  $self->{logger}             = PBot::Logger->new(log_file => $log_file);
  $self->{commands}           = PBot::Commands->new(pbot => $self);
  $self->{timer}              = PBot::Timer->new(timeout => 10);

  $self->{admins}             = PBot::BotAdmins->new(pbot => $self, filename => $admins_file);

  $self->admins->load_admins();
  $self->admins->add_admin($self->{botnick}, '.*', "$self->{botnick}!stdin\@localhost", 60, 'admin');
  $self->admins->login($self->{botnick}, "$self->{botnick}!stdin\@localhost", 'admin');

  $self->{factoids} = PBot::Factoids->new(
      pbot        => $self,
      filename    => $factoids_file, 
      export_path => $export_factoids_path, 
      export_site => $export_factoids_site, 
  );

  $self->factoids->load_factoids() if defined $factoids_file;
  $self->factoids->add_factoid('text', '.*', $self->{botnick}, 'version', "/say $VERSION");

  $self->{lagchecker}   = PBot::LagChecker->new(pbot => $self);
  $self->{antiflood}    = PBot::AntiFlood->new(pbot => $self);

  $self->{ignorelist}   = PBot::IgnoreList->new(pbot => $self, filename => $ignorelist_file);
  $self->{ignorelist}->load_ignores() if defined $ignorelist_file;

  $self->interpreter(PBot::Interpreter->new(pbot => $self));
  $self->interpreter->register(sub { return $self->commands->interpreter(@_); });
  $self->interpreter->register(sub { return $self->factoids->interpreter(@_); });

  $self->{botadmincmds}   = PBot::BotAdminCommands->new(pbot => $self);
  $self->{factoidcmds}    = PBot::FactoidCommands->new(pbot => $self);
  $self->{ignorelistcmds} = PBot::IgnoreListCommands->new(pbot => $self);

  $self->{irc}            = PBot::IRC->new();
  $self->{irchandlers}    = PBot::IRCHandlers->new(pbot => $self);

  $self->{channels}       = PBot::Channels->new(pbot => $self, filename => $channels_file);
  $self->channels->load_channels() if defined $channels_file;

  $self->{chanops}       = PBot::ChanOps->new(pbot => $self);
  $self->{chanopcmds}    = PBot::ChanOpCommands->new(pbot => $self);

  $self->{chanops}->{unban_timeout}->load_hash();

  $self->{quotegrabs}    = PBot::Quotegrabs->new(
    pbot        => $self, 
    filename    => $quotegrabs_file,
    export_path => $export_quotegrabs_path,
    export_site => $export_quotegrabs_site,
  );

  $self->quotegrabs->add_quotegrab($self->{botnick}, "#pbot2", 0, "pragma_", "Who's a bot?");
  $self->quotegrabs->load_quotegrabs() if defined $quotegrabs_file;

  $self->timer->start();
}

# TODO: add disconnect subroutine

sub connect {
  my ($self, $server) = @_;

  $server = $self->ircserver if not defined $server;

  if($self->{connected}) {
    # TODO: disconnect, clean-up, etc
  }

  $self->logger->log("Connecting to $server ...\n");

  $self->conn($self->irc->newconn( 
    Nick         => $self->{botnick},
    Username     => $self->{username},
    Ircname      => $self->{ircname},
    Server       => $server,
    Port         => $self->{port}))
      or Carp::croak "$0: Can't connect to IRC server.\n";

  $self->{connected} = 1;

  #set up default handlers for the IRC engine
  $self->conn->add_handler([ 251,252,253,254,302,255 ], sub { $self->irchandlers->on_init(@_)       });
  $self->conn->add_handler(376                        , sub { $self->irchandlers->on_connect(@_)    });
  $self->conn->add_handler('disconnect'               , sub { $self->irchandlers->on_disconnect(@_) });
  $self->conn->add_handler('notice'                   , sub { $self->irchandlers->on_notice(@_)     });
  $self->conn->add_handler('caction'                  , sub { $self->irchandlers->on_action(@_)     });
  $self->conn->add_handler('public'                   , sub { $self->irchandlers->on_public(@_)     });
  $self->conn->add_handler('msg'                      , sub { $self->irchandlers->on_msg(@_)        });
  $self->conn->add_handler('mode'                     , sub { $self->irchandlers->on_mode(@_)       });
  $self->conn->add_handler('part'                     , sub { $self->irchandlers->on_departure(@_)  });
  $self->conn->add_handler('join'                     , sub { $self->irchandlers->on_join(@_)       });
  $self->conn->add_handler('quit'                     , sub { $self->irchandlers->on_departure(@_)  });
  $self->conn->add_handler('pong'                     , sub { $self->lagchecker->on_pong(@_)         });
}

#main loop
sub do_one_loop {
  my $self = shift;

  # process IRC events
  $self->irc->do_one_loop();

  # process STDIN events
  $self->check_stdin();
}

sub start {
  my $self = shift;

  if(not defined $self->{connected} or $self->{connected} == 0) {
    $self->connect();
  }

  while(1) {
    $self->do_one_loop();
  }
}

sub check_stdin {
  my $self = shift;

  my $input = PBot::StdinReader::check_stdin();

  return if not defined $input;

  $self->logger->log("---------------------------------------------\n");
  $self->logger->log("Read '$input' from STDIN\n");

  my ($from, $text);

  if($input =~ m/^~([^ ]+)\s+(.*)/) {
    $from = $1;
    $text = "$self->{trigger}$2";
  } else {
    $from = undef;
    $text = "$self->{trigger}$input";
  }

  return $self->interpreter->process_line($from, $self->{botnick}, "stdin", "localhost", $text);
}

#-----------------------------------------------------------------------------------
# Getters/Setters
#-----------------------------------------------------------------------------------

sub irc {
  my $self = shift;
  return $self->{irc};
}

sub logger {
  my $self = shift;
  if(@_) { $self->{logger} = shift; }
  return $self->{logger};
}

sub channels {
  my $self = shift;
  if(@_) { $self->{channels} = shift; }
  return $self->{channels};
}

sub factoids {
  my $self = shift;
  if(@_) { $self->{factoids} = shift; }
  return $self->{factoids};
}

sub timer {
  my $self = shift;
  if(@_) { $self->{timer} = shift; }
  return $self->{timer};
}

sub conn {
  my $self = shift;
  if(@_) { $self->{conn} = shift; }
  return $self->{conn};
}

sub irchandlers {
  my $self = shift;
  if(@_) { $self->{irchandlers} = shift; }
  return $self->{irchandlers};
}

sub interpreter {
  my $self = shift;
  if(@_) { $self->{interpreter} = shift; }
  return $self->{interpreter};
}

sub admins {
  my $self = shift;
  if(@_) { $self->{admins} = shift; }
  return $self->{admins};
}

sub commands {
  my $self = shift;
  if(@_) { $self->{commands} = shift; }
  return $self->{commands};
}

sub botnick {
  my $self = shift;
  if(@_) { $self->{botnick} = shift; }
  return $self->{botnick};
}

sub identify_password {
  my $self = shift;
  if(@_) { $self->{identify_password} = shift; }
  return $self->{identify_password};
}

sub max_msg_len {
  my $self = shift;
  if(@_) { $self->{max_msg_len} = shift; }
  return $self->{max_msg_len};
}

sub module_dir {
  my $self = shift;
  if(@_) { $self->{module_dir} = shift; }
  return $self->{module_dir};
}

sub ignorelist {
  my $self = shift;
  if(@_) { $self->{ignorelist} = shift; }
  return $self->{ignorelist};
}

sub lagchecker {
  my $self = shift;
  if(@_) { $self->{lagchecker} = shift; }
  return $self->{lagchecker};
}

sub antiflood {
  my $self = shift;
  if(@_) { $self->{antiflood} = shift; }
  return $self->{antiflood};
}

sub quotegrabs {
  my $self = shift;
  if(@_) { $self->{quotegrabs} = shift; }
  return $self->{quotegrabs};
}

sub chanops {
  my $self = shift;
  if(@_) { $self->{chanops} = shift; }
  return $self->{chanops};
}

sub ircserver {
  my $self = shift;
  if(@_) { $self->{ircserver} = shift; }
  return $self->{ircserver};
}

1;
