# File: PBot.pm
# Author: pragma_
#
# Purpose: IRC Bot (3rd generation)

# $Id$

package PBot::PBot;

use strict;
use warnings;

use PBot::VERSION;

BEGIN {
  use Exporter;
  our @ISA = 'Exporter';
  our @EXPORT = qw($VERSION);

  our $VERSION = PBot::VERSION::BUILD_NAME . " revision " . PBot::VERSION::BUILD_REVISION . " " . PBot::VERSION::BUILD_DATE;
  print "$VERSION\n";
}

# unbuffer stdout
STDOUT->autoflush(1);

use Carp ();
use PBot::Logger;
use PBot::Registry;
use PBot::SelectHandler;
use PBot::StdinReader;
use PBot::IRC;
use PBot::EventDispatcher;
use PBot::IRCHandlers;
use PBot::Channels;
use PBot::BanTracker;
use PBot::NickList;
use PBot::LagChecker;
use PBot::MessageHistory;
use PBot::AntiFlood;
use PBot::Interpreter;
use PBot::Commands;
use PBot::ChanOps;
use PBot::Factoids; 
use PBot::BotAdmins;
use PBot::IgnoreList;
use PBot::BlackList;
use PBot::Quotegrabs;
use PBot::Timer;
use PBot::AntiAway;
use PBot::AntiKickAutoRejoin;

sub new {
  if(ref($_[1]) eq 'HASH') {
    Carp::croak("Options to PBot should be key/value pairs, not hash reference");
  }

  my ($class, %conf) = @_;
  my $self = bless {}, $class;
  $self->initialize(%conf);
  $self->register_signal_handlers;
  return $self;
}

sub initialize {
  my ($self, %conf) = @_;

  # logger created first to allow other modules to log things
  $self->{logger}   = PBot::Logger->new(log_file => delete $conf{log_file}, %conf);

  $self->{atexit}   = PBot::Registerable->new(%conf);
  $self->{timer}    = PBot::Timer->new(timeout => 10, %conf);
  $self->{commands} = PBot::Commands->new(pbot => $self, %conf);

  my $config_dir = delete $conf{config_dir} // "$ENV{HOME}/pbot/config";

  # registry created, but not yet loaded, to allow modules to create default values and triggers
  $self->{registry} = PBot::Registry->new(pbot => $self, filename => delete $conf{registry_file} // "$config_dir/registry", %conf);

  $self->{registry}->add_default('text', 'general', 'config_dir',  $config_dir);
  $self->{registry}->add_default('text', 'general', 'data_dir',    delete $conf{data_dir}    // "$ENV{HOME}/pbot/data");
  $self->{registry}->add_default('text', 'general', 'module_dir',  delete $conf{module_dir}  // "$ENV{HOME}/pbot/modules");
  $self->{registry}->add_default('text', 'general', 'trigger',     delete $conf{trigger}     // '!');

  $self->{registry}->add_default('text', 'irc',     'debug',       delete $conf{irc_debug}   // 0);
  $self->{registry}->add_default('text', 'irc',     'show_motd',   delete $conf{show_motd}   // 1);
  $self->{registry}->add_default('text', 'irc',     'max_msg_len', delete $conf{max_msg_len} // 425);
  $self->{registry}->add_default('text', 'irc',     'ircserver',   delete $conf{ircserver}   // "irc.freenode.net");
  $self->{registry}->add_default('text', 'irc',     'port',        delete $conf{port}        // 6667);
  $self->{registry}->add_default('text', 'irc',     'SSL',         delete $conf{SSL}         // 0);
  $self->{registry}->add_default('text', 'irc',     'SSL_ca_file', delete $conf{SSL_ca_file} // 'none');
  $self->{registry}->add_default('text', 'irc',     'SSL_ca_path', delete $conf{SSL_ca_path} // 'none');
  $self->{registry}->add_default('text', 'irc',     'botnick',     delete $conf{botnick}     // "pbot3");
  $self->{registry}->add_default('text', 'irc',     'username',    delete $conf{username}    // "pbot3");
  $self->{registry}->add_default('text', 'irc',     'ircname',     delete $conf{ircname}     // "http://code.google.com/p/pbot2-pl/");
  $self->{registry}->add_default('text', 'irc',     'identify_password', delete $conf{identify_password} // 'none');
  $self->{registry}->add_default('text', 'irc',     'log_default_handler', 1);
  
  $self->{registry}->set('irc', 'SSL_ca_file',       'private', 1);
  $self->{registry}->set('irc', 'SSL_ca_path',       'private', 1);
  $self->{registry}->set('irc', 'identify_password', 'private', 1);

  $self->{registry}->add_trigger('irc', 'botnick', sub { $self->change_botnick_trigger(@_) });
  $self->{registry}->add_trigger('irc', 'debug',   sub { $self->irc_debug_trigger(@_)      });
 
  $self->{event_dispatcher}   = PBot::EventDispatcher->new(pbot => $self, %conf);
  $self->{select_handler}     = PBot::SelectHandler->new(pbot => $self, %conf);
  $self->{stdin_reader}       = PBot::StdinReader->new(pbot => $self, %conf);
  $self->{admins}             = PBot::BotAdmins->new(pbot => $self, filename => delete $conf{admins_file}, %conf);
  $self->{bantracker}         = PBot::BanTracker->new(pbot => $self, %conf);
  $self->{nicklist}           = PBot::NickList->new(pbot => $self, %conf);
  $self->{lagchecker}         = PBot::LagChecker->new(pbot => $self, %conf);
  $self->{messagehistory}     = PBot::MessageHistory->new(pbot => $self, filename => delete $conf{messagehistory_file}, %conf);
  $self->{antiflood}          = PBot::AntiFlood->new(pbot => $self, %conf);
  $self->{ignorelist}         = PBot::IgnoreList->new(pbot => $self, filename => delete $conf{ignorelist_file}, %conf);
  $self->{blacklist}          = PBot::BlackList->new(pbot => $self, filename => delete $conf{blacklist_file}, %conf);
  $self->{irc}                = PBot::IRC->new();
  $self->{irchandlers}        = PBot::IRCHandlers->new(pbot => $self, %conf);
  $self->{channels}           = PBot::Channels->new(pbot => $self, filename => delete $conf{channels_file}, %conf);
  $self->{chanops}            = PBot::ChanOps->new(pbot => $self, %conf);
  $self->{antiaway}           = PBot::AntiAway->new(pbot => $self, %conf);
  $self->{antikickautorejoin} = PBot::AntiKickAutoRejoin->new(pbot => $self, %conf);

  $self->{interpreter}        = PBot::Interpreter->new(pbot => $self, %conf);
  $self->{interpreter}->register(sub { return $self->{commands}->interpreter(@_); });
  $self->{interpreter}->register(sub { return $self->{factoids}->interpreter(@_); });

  $self->{factoids} = PBot::Factoids->new(
    pbot        => $self,
    filename    => delete $conf{factoids_file},
    export_path => delete $conf{export_factoids_path},
    export_site => delete $conf{export_factoids_site}, 
    %conf
  );

  $self->{quotegrabs} = PBot::Quotegrabs->new(
    pbot        => $self, 
    filename    => delete $conf{quotegrabs_file},
    export_path => delete $conf{export_quotegrabs_path},
    export_site => delete $conf{export_quotegrabs_site},
    %conf
  );

  # load registry entries from file to overwrite defaults
  $self->{registry}->load;

  # create implicit bot-admin account for bot
  my $botnick = $self->{registry}->get_value('irc', 'botnick');
  $self->{admins}->add_admin($botnick, '.*', "$botnick!stdin\@localhost", 90, 'admin', 1);
  $self->{admins}->login($botnick, "$botnick!stdin\@localhost", 'admin');

  # start timer
  $self->{timer}->start();
}

sub random_nick {
  my @chars = ("A".."Z", "a".."z", "0".."9");
  my $nick = $chars[rand @chars - 10]; # nicks cannot start with a digit
  $nick .= $chars[rand @chars] for 1..9;
  return $nick;
}

# TODO: add disconnect subroutine
sub connect {
  my ($self, $server) = @_;

  if($self->{connected}) {
    # TODO: disconnect, clean-up, etc
  }

  $server = $self->{registry}->get_value('irc', 'ircserver') if not defined $server;

  $self->{logger}->log("Connecting to $server ...\n");

  while (not $self->{conn} = $self->{irc}->newconn( 
      Nick         => random_nick,
      Username     => $self->{registry}->get_value('irc', 'username'),
      Ircname      => $self->{registry}->get_value('irc', 'ircname'),
      Server       => $server,
      SSL          => $self->{registry}->get_value('irc', 'SSL'),
      SSL_ca_file  => $self->{registry}->get_value('irc', 'SSL_ca_file'),
      SSL_ca_path  => $self->{registry}->get_value('irc', 'SSL_ca_path'),
      Port         => $self->{registry}->get_value('irc', 'port'))) {
    $self->{logger}->log("$0: Can't connect to $server:" . $self->{registry}->get_value('irc', 'port') . ". Retrying in 15 seconds...\n");
    sleep 15;
  }

  $self->{connected} = 1;

  #set up handlers for the IRC engine
  $self->{conn}->add_default_handler(sub { $self->{irchandlers}->default_handler(@_) }, 1);
  $self->{conn}->add_handler([ 251,252,253,254,255,302 ], sub { $self->{irchandlers}->on_init(@_) });

  # ignore these events
  $self->{conn}->add_handler(['whoisuser', 
                              'whoisserver', 
                              'whoiscountry', 
                              'whoischannels',
                              'whoisidle',
                              'motdstart',
                              'endofmotd',
                              'away',
                              'endofbanlist'], sub {});
}

#main loop
sub do_one_loop {
  my $self = shift;
  $self->{irc}->do_one_loop();
  $self->{select_handler}->do_select();
}

sub start {
  my $self = shift;
  while(1) { 
    $self->connect() if not $self->{connected};
    $self->do_one_loop() if $self->{connected}; 
  }
}

sub register_signal_handlers {
  my $self = shift;
  $SIG{INT} = sub { $self->atexit; exit 0; };
}

sub atexit {
  my $self = shift;
  $self->{atexit}->execute_all;
}

sub irc_debug_trigger {
  my ($self, $section, $item, $newvalue) = @_;
  $self->{irc}->debug($newvalue);
  $self->{conn}->debug($newvalue) if $self->{connected};
}

sub change_botnick_trigger {
  my ($self, $section, $item, $newvalue) = @_;
  $self->{conn}->nick($newvalue) if $self->{connected};
}

1;
