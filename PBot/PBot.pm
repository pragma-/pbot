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
  print "PBot version $VERSION\n";
}

# unbuffer stdout
STDOUT->autoflush(1);

use Carp ();
use PBot::Logger;
use PBot::Registry;
use PBot::SelectHandler;
use PBot::StdinReader;
use PBot::IRC;
use PBot::IRCHandlers;
use PBot::Channels;
use PBot::BanTracker;
use PBot::LagChecker;
use PBot::MessageHistory;
use PBot::AntiFlood;
use PBot::Interpreter;
use PBot::Commands;
use PBot::ChanOps;
use PBot::Factoids; 
use PBot::BotAdmins;
use PBot::IgnoreList;
use PBot::Quotegrabs;
use PBot::Timer;

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
  $self->{logger}   = PBot::Logger->new(log_file => delete $conf{log_file});

  $self->{atexit}   = PBot::Registerable->new();
  $self->{timer}    = PBot::Timer->new(timeout => 10);
  $self->{commands} = PBot::Commands->new(pbot => $self);

  my $config_dir = delete $conf{config_dir} // "$ENV{HOME}/pbot/config";

  # registry created, but not yet loaded, to allow modules to create default values and triggers
  $self->{registry} = PBot::Registry->new(pbot => $self, filename => delete $conf{registry_file} // "$config_dir/registry");

  $self->{registry}->add_default('text', 'general', 'config_dir',  $config_dir);
  $self->{registry}->add_default('text', 'general', 'data_dir',    delete $conf{data_dir}    // "$ENV{HOME}/pbot/data");
  $self->{registry}->add_default('text', 'general', 'module_dir',  delete $conf{module_dir}  // "$ENV{HOME}/pbot/modules");
  $self->{registry}->add_default('text', 'general', 'trigger',     delete $conf{trigger}     // '!');

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
  
  $self->{registry}->set('irc', 'SSL_ca_file',       'private', 1);
  $self->{registry}->set('irc', 'SSL_ca_path',       'private', 1);
  $self->{registry}->set('irc', 'identify_password', 'private', 1);

  $self->{registry}->add_trigger('irc', 'botnick', sub { $self->change_botnick_trigger(@_) });
 
  $self->{select_handler} = PBot::SelectHandler->new(pbot => $self);
  $self->{stdin_reader}   = PBot::StdinReader->new(pbot => $self);
  $self->{admins}         = PBot::BotAdmins->new(pbot => $self, filename => delete $conf{admins_file});
  $self->{bantracker}     = PBot::BanTracker->new(pbot => $self);
  $self->{lagchecker}     = PBot::LagChecker->new(pbot => $self, %conf);
  $self->{messagehistory} = PBot::MessageHistory->new(pbot => $self, filename => delete $conf{messagehistory_file}, %conf);
  $self->{antiflood}      = PBot::AntiFlood->new(pbot => $self, %conf);
  $self->{ignorelist}     = PBot::IgnoreList->new(pbot => $self, filename => delete $conf{ignorelist_file});
  $self->{irc}            = PBot::IRC->new();
  $self->{irchandlers}    = PBot::IRCHandlers->new(pbot => $self);
  $self->{channels}       = PBot::Channels->new(pbot => $self, filename => delete $conf{channels_file});
  $self->{chanops}        = PBot::ChanOps->new(pbot => $self);

  $self->{interpreter}    = PBot::Interpreter->new(pbot => $self);
  $self->{interpreter}->register(sub { return $self->{commands}->interpreter(@_); });
  $self->{interpreter}->register(sub { return $self->{factoids}->interpreter(@_); });

  $self->{factoids} = PBot::Factoids->new(
    pbot        => $self,
    filename    => delete $conf{factoids_file},
    export_path => delete $conf{export_factoids_path},
    export_site => delete $conf{export_factoids_site}, 
  );

  $self->{quotegrabs} = PBot::Quotegrabs->new(
    pbot        => $self, 
    filename    => delete $conf{quotegrabs_file},
    export_path => delete $conf{export_quotegrabs_path},
    export_site => delete $conf{export_quotegrabs_site},
  );

  # load registry entries from file to overwrite defaults
  $self->{registry}->load;

  # create implicit bot-admin account for bot
  my $botnick = $self->{registry}->get_value('irc', 'botnick');
  $self->{admins}->add_admin($botnick, '.*', "$botnick!stdin\@localhost", 60, 'admin', 1);
  $self->{admins}->login($botnick, "$botnick!stdin\@localhost", 'admin');

  # start timer
  $self->{timer}->start();
}

# TODO: add disconnect subroutine

sub connect {
  my ($self, $server) = @_;

  if($self->{connected}) {
    # TODO: disconnect, clean-up, etc
  }

  $server = $self->{registry}->get_value('irc', 'ircserver') if not defined $server;

  $self->{logger}->log("Connecting to $server ...\n");

  $self->{conn} = $self->{irc}->newconn( 
    Nick         => $self->{registry}->get_value('irc', 'botnick'),
    Username     => $self->{registry}->get_value('irc', 'username'),
    Ircname      => $self->{registry}->get_value('irc', 'ircname'),
    Server       => $server,
    SSL          => $self->{registry}->get_value('irc', 'SSL'),
    SSL_ca_file  => $self->{registry}->get_value('irc', 'SSL_ca_file'),
    SSL_ca_path  => $self->{registry}->get_value('irc', 'SSL_ca_path'),
    Port         => $self->{registry}->get_value('irc', 'port'))
    or Carp::croak "$0: Can't connect to IRC server.\n";

  $self->{connected} = 1;

  #set up default handlers for the IRC engine
  $self->{conn}->add_handler([ 251,252,253,254,302,255 ], sub { $self->{irchandlers}->on_init(@_)         });
  $self->{conn}->add_handler(376                        , sub { $self->{irchandlers}->on_connect(@_)      });
  $self->{conn}->add_handler('disconnect'               , sub { $self->{irchandlers}->on_disconnect(@_)   });
  $self->{conn}->add_handler('notice'                   , sub { $self->{irchandlers}->on_notice(@_)       });
  $self->{conn}->add_handler('caction'                  , sub { $self->{irchandlers}->on_action(@_)       });
  $self->{conn}->add_handler('public'                   , sub { $self->{irchandlers}->on_public(@_)       });
  $self->{conn}->add_handler('msg'                      , sub { $self->{irchandlers}->on_msg(@_)          });
  $self->{conn}->add_handler('mode'                     , sub { $self->{irchandlers}->on_mode(@_)         });
  $self->{conn}->add_handler('part'                     , sub { $self->{irchandlers}->on_departure(@_)    });
  $self->{conn}->add_handler('join'                     , sub { $self->{irchandlers}->on_join(@_)         });
  $self->{conn}->add_handler('kick'                     , sub { $self->{irchandlers}->on_kick(@_)         });
  $self->{conn}->add_handler('quit'                     , sub { $self->{irchandlers}->on_departure(@_)    });
  $self->{conn}->add_handler('nick'                     , sub { $self->{irchandlers}->on_nickchange(@_)   });
  $self->{conn}->add_handler('pong'                     , sub { $self->{lagchecker}->on_pong(@_)          });
  $self->{conn}->add_handler('whoisaccount'             , sub { $self->{antiflood}->on_whoisaccount(@_)   });
  $self->{conn}->add_handler('banlist'                  , sub { $self->{bantracker}->on_banlist_entry(@_) });
  $self->{conn}->add_handler('endofnames'               , sub { $self->{bantracker}->get_banlist(@_)      });
  $self->{conn}->add_handler(728                        , sub { $self->{bantracker}->on_quietlist_entry(@_) });
}

#main loop
sub do_one_loop {
  my $self = shift;
  $self->{irc}->do_one_loop();
  $self->{select_handler}->do_select();
}

sub start {
  my $self = shift;
  $self->connect() if not $self->{connected};
  while(1) { $self->do_one_loop(); }
}

sub register_signal_handlers {
  my $self = shift;
  $SIG{INT} = sub { $self->atexit; exit 0; };
}

sub atexit {
  my $self = shift;
  $self->{atexit}->execute_all;
}

sub change_botnick_trigger {
  my ($self, $section, $item, $newvalue) = @_;
  $self->{conn}->nick($newvalue) if $self->{connected};
}

1;
