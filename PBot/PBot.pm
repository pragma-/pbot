# File: PBot.pm
# Author: pragma_
#
# Purpose: IRC Bot

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

package PBot::PBot;

use strict; use warnings;
use feature 'unicode_strings';
use utf8;

use Carp ();
use PBot::Logger;
use PBot::VERSION;
use PBot::AntiFlood;
use PBot::AntiSpam;
use PBot::BanList;
use PBot::BlackList;
use PBot::Capabilities;
use PBot::Commands;
use PBot::Channels;
use PBot::ChanOps;
use PBot::DualIndexHashObject;
use PBot::DualIndexSQLiteObject;
use PBot::EventDispatcher;
use PBot::Factoids;
use PBot::Functions;
use PBot::HashObject;
use PBot::IgnoreList;
use PBot::Interpreter;
use PBot::IRC;
use PBot::IRCHandlers;
use PBot::LagChecker;
use PBot::MessageHistory;
use PBot::Modules;
use PBot::MiscCommands;
use PBot::NickList;
use PBot::Plugins;
use PBot::ProcessManager;
use PBot::Registry;
use PBot::Refresher;
use PBot::SelectHandler;
use PBot::StdinReader;
use PBot::Timer;
use PBot::Updater;
use PBot::Users;
use PBot::Utils::ParseDate;
use PBot::WebPaste;

# unbuffer stdout stream
STDOUT->autoflush(1);

# set standard output streams to encode as utf8
binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

# decode command-line arguments from utf8
use Encode;
@ARGV = map { decode('UTF-8', $_, 1) } @ARGV;

sub new {
    my ($proto, %conf) = @_;
    my $class = ref($proto) || $proto;
    my $self  = bless {}, $class;
    $self->initialize(%conf);
    return $self;
}

sub initialize {
    my ($self, %conf) = @_;

    $self->{startup_timestamp} = time;

    # process command-line arguments for path and registry overrides
    foreach my $arg (@ARGV) {
        if ($arg =~ m/^-?(?:general\.)?((?:data|module|plugin|update)_dir)=(.*)$/) {
            # check command-line arguments for directory overrides
            my $override = $1;
            my $value    = $2;
            $value =~ s/[\\\/]$//; # strip trailing directory separator
            $conf{data_dir}    = $value if $override eq 'data_dir';
            $conf{module_dir}  = $value if $override eq 'module_dir';
            $conf{plugin_dir}  = $value if $override eq 'plugin_dir';
            $conf{update_dir}  = $value if $override eq 'update_dir';
        } else {
            # check command-line arguments for registry overrides
            my ($item, $value) = split /=/, $arg, 2;

            if (not defined $item or not defined $value) {
                print STDERR "Fatal error: unknown argument `$arg`; arguments must be in the form of `section.key=value` (e.g.: irc.botnick=newnick)\n";
                exit;
            }

            my ($section, $key) = split /\./, $item, 2;

            if (not defined $section or not defined $key) {
                print STDERR "Fatal error: bad argument `$arg`; registry entries must be in the form of section.key (e.g.: irc.botnick)\n";
                exit;
            }

            $section =~ s/^-//;    # remove a leading - to allow arguments like -irc.botnick due to habitual use of -args
            $self->{overrides}->{"$section.$key"} = $value;
        }
    }

    # make sure the paths exist
    foreach my $path (qw/data_dir module_dir plugin_dir update_dir/) {
        if (not -d $conf{$path}) {
            print STDERR "$path path ($conf{$path}) does not exist; aborting.\n";
            exit;
        }
    }

    # let modules register atexit subroutines
    $self->{atexit} = PBot::Registerable->new(pbot => $self, %conf);

    # register default signal handlers
    $self->register_signal_handlers;

    # prepare and open logger
    $self->{logger} = PBot::Logger->new(pbot => $self, filename => "$conf{data_dir}/log/log", %conf);

    # log command-line arguments
    $self->{logger}->log("Args: @ARGV\n") if @ARGV;

    # log configured paths
    $self->{logger}->log("module_dir: $conf{module_dir}\n");
    $self->{logger}->log("plugin_dir: $conf{plugin_dir}\n");
    $self->{logger}->log("  data_dir: $conf{data_dir}\n");
    $self->{logger}->log("update_dir: $conf{update_dir}\n");

    # prepare the updater
    $self->{updater} = PBot::Updater->new(pbot => $self, data_dir => $conf{data_dir}, update_dir => $conf{update_dir});

    # update any data files to new locations/formats
    # --- this must happen before any data files are opened! ---
    if ($self->{updater}->update) {
        $self->{logger}->log("Update failed.\n");
        exit 0;
    }

    # create capabilities so commands can add new capabilities
    $self->{capabilities} = PBot::Capabilities->new(pbot => $self, filename => "$conf{data_dir}/capabilities", %conf);

    # create commands so the modules can register new commands
    $self->{commands} = PBot::Commands->new(pbot => $self, filename => "$conf{data_dir}/commands", %conf);

    # add 'cap' capability command here since $self->{commands} is created after $self->{capabilities}
    $self->{commands}->register(sub { $self->{capabilities}->cmd_cap(@_) }, "cap");

    # prepare the version information and `version` command
    $self->{version} = PBot::VERSION->new(pbot => $self, %conf);
    $self->{logger}->log($self->{version}->version . "\n");

    # prepare registry
    $self->{registry} = PBot::Registry->new(pbot => $self, filename => "$conf{data_dir}/registry", %conf);

    # ensure user has attempted to configure the bot
    if (not length $self->{registry}->get_value('irc', 'botnick')) {
        $self->{logger}->log("Fatal error: IRC nickname not defined; please set registry key irc.botnick in $conf{data_dir}/registry to continue.\n");
        exit;
    }

    # prepare remaining core PBot modules -- do not change this order
    $self->{timer} = PBot::Timer->new(pbot => $self, timeout => 10, name => 'PBot Timer', %conf);
    $self->{event_dispatcher} = PBot::EventDispatcher->new(pbot => $self, %conf);
    $self->{users}            = PBot::Users->new(pbot => $self, filename => "$conf{data_dir}/users", %conf);
    $self->{antiflood}        = PBot::AntiFlood->new(pbot => $self, %conf);
    $self->{antispam}         = PBot::AntiSpam->new(pbot => $self, %conf);
    $self->{banlist}          = PBot::BanList->new(pbot => $self, %conf);
    $self->{blacklist}        = PBot::BlackList->new(pbot => $self, filename => "$conf{data_dir}/blacklist", %conf);
    $self->{channels}         = PBot::Channels->new(pbot => $self, filename => "$conf{data_dir}/channels", %conf);
    $self->{chanops}          = PBot::ChanOps->new(pbot => $self, %conf);
    $self->{factoids}         = PBot::Factoids->new(pbot => $self, filename => "$conf{data_dir}/factoids.sqlite3", %conf);
    $self->{functions}        = PBot::Functions->new(pbot => $self, %conf);
    $self->{refresher}        = PBot::Refresher->new(pbot => $self);
    $self->{ignorelist}       = PBot::IgnoreList->new(pbot => $self, filename => "$conf{data_dir}/ignorelist", %conf);
    $self->{irc}              = PBot::IRC->new();
    $self->{irchandlers}      = PBot::IRCHandlers->new(pbot => $self, %conf);
    $self->{interpreter}      = PBot::Interpreter->new(pbot => $self, %conf);
    $self->{lagchecker}       = PBot::LagChecker->new(pbot => $self, %conf);
    $self->{misc_commands}    = PBot::MiscCommands->new(pbot => $self, %conf);
    $self->{messagehistory}   = PBot::MessageHistory->new(pbot => $self, filename => "$conf{data_dir}/message_history.sqlite3", %conf);
    $self->{modules}          = PBot::Modules->new(pbot => $self, %conf);
    $self->{nicklist}         = PBot::NickList->new(pbot => $self, %conf);
    $self->{parsedate}        = PBot::Utils::ParseDate->new(pbot => $self, %conf);
    $self->{plugins}          = PBot::Plugins->new(pbot => $self, %conf);
    $self->{process_manager}  = PBot::ProcessManager->new(pbot => $self, %conf);
    $self->{select_handler}   = PBot::SelectHandler->new(pbot => $self, %conf);
    $self->{stdin_reader}     = PBot::StdinReader->new(pbot => $self, %conf);
    $self->{webpaste}         = PBot::WebPaste->new(pbot => $self, %conf);

    # register command/factoid interpreters
    $self->{interpreter}->register(sub { $self->{commands}->interpreter(@_) });
    $self->{interpreter}->register(sub { $self->{factoids}->interpreter(@_) });

    # give botowner all capabilities
    # -- this must happen last after all modules have registered their capabilities --
    $self->{capabilities}->rebuild_botowner_capabilities;

    # flush all pending save events to disk at exit
    $self->{atexit}->register(sub {
            $self->{timer}->execute_and_dequeue_event('save *');
            return;
        }
    );
}

sub random_nick {
    my ($self, $length) = @_;
    $length //= 9;
    my @chars = ("A" .. "Z", "a" .. "z", "0" .. "9");
    my $nick  = $chars[rand @chars - 10];               # nicks cannot start with a digit
    $nick .= $chars[rand @chars] for 1 .. $length;
    return $nick;
}

# TODO: add disconnect subroutine and connect/disconnect/reconnect commands
sub connect {
    my ($self) = @_;
    return if $ENV{PBOT_LOCAL};

    if ($self->{connected}) {
        # TODO: disconnect, clean-up, etc
    }

    my $server = $self->{registry}->get_value('irc', 'server');
    my $port   = $self->{registry}->get_value('irc', 'port');
    my $delay  = $self->{registry}->get_value('irc', 'reconnect_delay') // 10;

    $self->{logger}->log("Connecting to $server:$port\n");

    while (
        not $self->{conn} = $self->{irc}->newconn(
            Nick     => $self->{registry}->get_value('irc', 'randomize_nick') ? $self->random_nick : $self->{registry}->get_value('irc', 'botnick'),
            Username => $self->{registry}->get_value('irc', 'username'),
            Ircname  => $self->{registry}->get_value('irc', 'realname'),
            Server      => $server,
            Port        => $port,
            Pacing      => 1,
            UTF8        => 1,
            SSL         => $self->{registry}->get_value('irc', 'SSL'),
            SSL_ca_file => $self->{registry}->get_value('irc', 'SSL_ca_file'),
            SSL_ca_path => $self->{registry}->get_value('irc', 'SSL_ca_path'),
        )
      )
    {
        $self->{logger}->log("$0: Can't connect to $server:$port: $!\nRetrying in $delay seconds...\n");
        sleep $delay;
    }

    $self->{connected} = 1;

    # start timer once connected
    $self->{timer}->start;

    # set up handlers for the IRC engine
    $self->{conn}->add_default_handler(sub { $self->{irchandlers}->default_handler(@_) }, 1);
    $self->{conn}->add_handler([251, 252, 253, 254, 255, 302], sub { $self->{irchandlers}->on_init(@_) });

    # ignore these events
    $self->{conn}->add_handler(
        [
            'whoisserver',
            'whoiscountry',
            'whoischannels',
            'whoisidle',
            'motdstart',
            'endofmotd',
            'away',
        ],
        sub { }
    );
}

sub register_signal_handlers {
    my $self = shift;

    $SIG{INT} = sub {
        $self->{logger}->log("SIGINT received, exiting immediately.\n");
        $self->atexit;
        exit 0;
    };
}

# called when PBot terminates
sub atexit {
    my $self = shift;
    $self->{atexit}->execute_all;
    alarm 0;
    $self->{logger}->log("Good-bye.\n");
}

# main loop
sub do_one_loop {
    my $self = shift;
    $self->{irc}->do_one_loop() if $self->{connected};
    $self->{select_handler}->do_select;
}

# main entry point
sub start {
    my $self = shift;
    while (1) {
        $self->connect if not $self->{connected};
        $self->do_one_loop;
    }
}

1;
